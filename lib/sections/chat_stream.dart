import 'dart:typed_data';
import 'dart:convert';
import '/widgets/chat_input_box.dart';
import '/widgets/item_image_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SectionStreamChat extends StatefulWidget {
  final String language;

  const SectionStreamChat({super.key, required this.language});

  @override
  State<SectionStreamChat> createState() => _SectionStreamChatState();
}

class _SectionStreamChatState extends State<SectionStreamChat> {
  final controller = TextEditingController();
  final gemini = Gemini.instance;
  final ImagePicker picker = ImagePicker();

  bool _loading = false;
  bool _isListening = false;
  List<Uint8List>? images;

  bool get loading => _loading;
  set loading(bool set) => setState(() => _loading = set);

  final List<Content> chats = [];

  final int maxChatHistoryLength = 10;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _saveChats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> chatsEncoded =
        chats.map((chat) => jsonEncode(chat.toJson())).toList();
    await prefs.setStringList('chats', chatsEncoded);
  }

  Future<void> _loadChats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? chatsEncoded = prefs.getStringList('chats');
    if (chatsEncoded != null) {
      setState(() {
        chats.clear();
        chats.addAll(chatsEncoded
            .map((chatStr) => Content.fromJson(jsonDecode(chatStr))));
      });
    }
  }

    Future<void> _clearChats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('chats');
    setState(() {
      chats.clear();
    });
  }

@override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: chats.isNotEmpty
              ? Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    reverse: true,
                    child: ListView.builder(
                      itemBuilder: chatItem,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: chats.length,
                      reverse: false,
                    ),
                  ),
                )
              : const Center(child: Text('Search something!')),
        ),
        if (loading) const CircularProgressIndicator(),
        if (images != null)
          Container(
            height: 120,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            child: Card(
              child: ListView.builder(
                itemBuilder: (context, index) => ItemImageView(
                  bytes: images!.elementAt(index),
                ),
                itemCount: images!.length,
                scrollDirection: Axis.horizontal,
              ),
            ),
          ),
        ElevatedButton(
          onPressed: _clearChats,
          child: const Text('Clear Chats'),
        ),
        ChatInputBox(
          controller: controller,
          onClickCamera: () {
            picker.pickMultiImage().then((value) async {
              final imagesBytes = <Uint8List>[];
              for (final file in value) {
                imagesBytes.add(await file.readAsBytes());
              }

              if (imagesBytes.isNotEmpty) {
                setState(() {
                  images = imagesBytes;
                });
              }
            });
          },
          isListening: _isListening,
          onSend: () {
            if (controller.text.isNotEmpty) {
              final searchedText = controller.text;

              final promptWithLanguageHint = widget.language == 'Español'
                  ? "$searchedText. Responde en español por favor."
                  : "$searchedText. Please respond in English.";

              chats.add(
                Content(role: 'user', parts: [Parts(text: searchedText)]),
              );
              controller.clear();
              loading = true;

              if (images != null) {
                gemini
                    .streamGenerateContent(
                  promptWithLanguageHint,
                  images: images,
                )
                    .listen((value) {
                  loading = false;
                  setState(() {
                    if (chats.isNotEmpty &&
                        chats.last.role == value.content?.role) {
                      chats.last.parts!.last.text =
                          '${chats.last.parts!.last.text}${value.output}';
                    } else {
                      chats.add(Content(
                          role: 'model', parts: [Parts(text: value.output)]));
                    }
                  });
                  _saveChats();
                  setState(() {
                    images = null;
                  });
                });
              } else {
                final recentChats = chats.length > maxChatHistoryLength
                    ? chats.sublist(chats.length - maxChatHistoryLength)
                    : chats;

                gemini.streamChat(recentChats).listen((value) {
                  loading = false;
                  setState(() {
                    if (chats.isNotEmpty &&
                        chats.last.role == value.content?.role) {
                      chats.last.parts!.last.text =
                          '${chats.last.parts!.last.text}${value.output}';
                    } else {
                      chats.add(Content(
                          role: 'model', parts: [Parts(text: value.output)]));
                    }
                  });
                  _saveChats();
                });
              }
            }
          },
          language: widget.language,
          onListeningChanged: (isListening) {
            setState(() {
              _isListening = isListening;
            });
          },
        ),
      ],
    );
  }

  Widget chatItem(BuildContext context, int index) {
    final Content content = chats[index];

    return Card(
      elevation: 0,
      color:
          content.role == 'model' ? Colors.blue.shade800 : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content.role ?? 'role'),
            Markdown(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                data:
                    content.parts?.lastOrNull?.text ?? 'cannot generate data!'),
          ],
        ),
      ),
    );
  }
}
