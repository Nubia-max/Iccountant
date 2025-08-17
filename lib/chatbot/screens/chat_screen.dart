// lib/chat_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:unicons/unicons.dart';

import 'package:taxpal/ChatService.dart';
import 'package:taxpal/ImageScreen.dart';

// NEW: accounting screens opened from the Iccountant drawer
import 'package:taxpal/screens/trial_balance_screen.dart';
import 'package:taxpal/screens/journals_screen.dart';
import 'package:taxpal/screens/accounts_screen.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? toggleDrawer;
  const ChatScreen({super.key, this.toggleDrawer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool isDrawerOpen = false;

  // Chat state
  final List<ChatMessage> messages = [];
  final ChatUser user = ChatUser(id: '1', firstName: 'You');
  final ChatUser bot = ChatUser(id: '2', firstName: 'Iccountant');

  /// System prompt (kept simple; your backend does the accounting smarts)
  final List<Map<String, dynamic>> chatHistory = <Map<String, dynamic>>[
    {
      "role": "system",
      "content":
          "You are a concise assistant. When users ask general questions, answer helpfully and briefly.",
    },
  ];

  // Services / controllers
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController inputCon = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  ChatService? chatService;

  bool isListening = false;
  bool isTTS = false;
  bool _ready = false;

  // Pending images before sending (display only; backend doesn’t use yet)
  final List<XFile> _pendingImages = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // TIP: don’t pass an OpenAI key while you debug backend connectivity.
    // If you *do* store one, ChatService will fallback to generic chat when
    // the backend is unreachable, which can hide network/CORS issues.
    // await _storage.write(key: "id1", value: "<YOUR_OPENAI_KEY>");
    // final k = await _storage.read(key: "id1");
    const String? k = null; // disable fallback chat during dev
    chatService = ChatService(k);

    await _initSpeech();
    await _ttsSettings();
    setState(() => _ready = true);
  }

  Future<void> _initSpeech() async {
    await _speechToText.initialize(
      onStatus: (s) {
        if (s == "done" || s == "notListening") {
          setState(() => isListening = false);
        }
      },
      onError: (e) {
        debugPrint("Speech error: $e");
        setState(() => isListening = false);
      },
    );
  }

  Future<void> _ttsSettings() async {
    if (await flutterTts.isLanguageAvailable("en-US")) {
      await flutterTts.setLanguage("en-US");
      await flutterTts.setVoice({
        "name": "en-us-x-tpd-local",
        "locale": "en-US",
      });
    }
  }

  // ===== Speech handlers
  Future<void> _startListening() async {
    if (isListening) {
      await _speechToText.stop();
      setState(() => isListening = false);
      return;
    }
    final available = await _speechToText.initialize();
    if (!available) return;
    setState(() => isListening = true);
    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenMode: ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
    );
  }

  void _onSpeechResult(SpeechRecognitionResult r) {
    setState(() {
      inputCon.text = r.recognizedWords;
    });
    if (r.finalResult) {
      _speechToText.stop();
      setState(() => isListening = false);
    }
  }

  // ===== Attachments
  Future<void> _pickImagesFromGallery() async {
    final picks = await _picker.pickMultiImage();
    if (picks.isEmpty) return;
    _pendingImages.addAll(picks);
    setState(() {});
  }

  Future<void> _captureImageCamera() async {
    final shot = await _picker.pickImage(source: ImageSource.camera);
    if (shot == null) return;
    _pendingImages.add(shot);
    setState(() {});
  }

  void _removePendingImage(int i) {
    if (i < 0 || i >= _pendingImages.length) return;
    _pendingImages.removeAt(i);
    setState(() {});
  }

  Widget _buildPendingPreviewRow() {
    if (_pendingImages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 90,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final img = _pendingImages[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(img.path),
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removePendingImage(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== Chat send flow
  Future<void> _handleSubmit() async {
    if (!_ready || chatService == null) return;

    final prompt = inputCon.text.trim();
    final hasImages = _pendingImages.isNotEmpty;
    final hasText = prompt.isNotEmpty;
    if (!hasImages && !hasText) return;

    // 1) Show user message
    List<ChatMedia>? medias;
    if (hasImages) {
      medias =
          _pendingImages
              .map(
                (x) => ChatMedia(
                  url: x.path,
                  fileName: x.name,
                  type: MediaType.image,
                ),
              )
              .toList();
    }
    final userMsg = ChatMessage(
      text: prompt,
      createdAt: DateTime.now(),
      user: user,
      medias: medias,
    );
    messages.insert(0, userMsg);
    await _saveChatMessage(prompt, medias);

    setState(() {});
    inputCon.clear();
    _pendingImages.clear();

    // 2) Ask service (hits FastAPI /prompt). If unclear, it returns a clarifying message.
    String reply;
    try {
      reply = await chatService!.handlePrompt(chatHistory, prompt);
    } catch (e) {
      reply = "There was a problem: $e";
    }

    // 3) Show bot message
    final botMsg = ChatMessage(
      text: reply,
      createdAt: DateTime.now(),
      user: bot,
    );
    messages.insert(0, botMsg);
    setState(() {});

    // Optional TTS
    if (isTTS && reply.isNotEmpty) {
      await flutterTts.speak(reply);
    }
  }

  // ===== Persist chat list locally (simple log)
  Future<void> _saveChatMessage(String message, List<ChatMedia>? medias) async {
    final chatMessage = {
      'text': message,
      'createdAt': DateTime.now().toString(),
      'user': 'user',
      'media': medias?.map((e) => e.url).toList(),
    };

    final prefs = await SharedPreferences.getInstance();
    final messagesList = prefs.getStringList('chatHistory') ?? [];
    messagesList.add(jsonEncode(chatMessage));
    await prefs.setStringList('chatHistory', messagesList);
  }

  // ===== Image generation (optional)
  Future<void> _generateImages() async {
    if (chatService == null) return;
    final String prompt = inputCon.text.trim();
    if (prompt.isEmpty) return;

    messages.insert(
      0,
      ChatMessage(text: prompt, createdAt: DateTime.now(), user: user),
    );
    setState(() {});
    inputCon.clear();

    final urls = await chatService!.generateImages(prompt);
    final medias =
        urls
            .map(
              (u) =>
                  ChatMedia(url: u, fileName: "image", type: MediaType.image),
            )
            .toList();

    messages.insert(
      0,
      ChatMessage(createdAt: DateTime.now(), user: bot, medias: medias),
    );
    setState(() {});
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Select images from gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImagesFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _captureImageCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: const Text('Attach file'),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await FilePicker.platform.pickFiles(
                      allowMultiple: false,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      messages.insert(
                        0,
                        ChatMessage(
                          createdAt: DateTime.now(),
                          user: user,
                          medias: [
                            ChatMedia(
                              url: result.files.first.path!,
                              fileName: result.files.first.name,
                              type: MediaType.file,
                            ),
                          ],
                        ),
                      );
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  // ===== UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Top Iccountant drawer (collapsible)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isDrawerOpen ? 600 : 60,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => setState(() => isDrawerOpen = !isDrawerOpen),
                  child: ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Iccountant',
                          style: TextStyle(color: Colors.black, fontSize: 18),
                        ),
                        Icon(
                          isDrawerOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isDrawerOpen)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Text(
                            'Iccountant • Accounts & Reports',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Card(
                          elevation: 0,
                          color: Colors.grey.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.balance),
                                title: const Text('Trial Balance'),
                                subtitle: const Text(
                                  'Debits & Credits by account',
                                ),
                                onTap: () {
                                  setState(() => isDrawerOpen = false);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const TrialBalanceScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.list_alt),
                                title: const Text('Journals'),
                                subtitle: const Text('Posted entries & lines'),
                                onTap: () {
                                  setState(() => isDrawerOpen = false);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const JournalsScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.account_tree),
                                title: const Text('Chart of Accounts'),
                                subtitle: const Text(
                                  'All accounts in your CoA',
                                ),
                                onTap: () {
                                  setState(() => isDrawerOpen = false);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const AccountsScreen(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Chat list
          Expanded(
            child: DashChat(
              currentUser: user,
              onSend: (_) {},
              readOnly: true,
              messages: messages,
              messageOptions: MessageOptions(
                onTapMedia: (item) {
                  if (item.type == MediaType.image) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ImageScreen(item.url),
                      ),
                    );
                  }
                },
              ),
            ),
          ),

          // Pending attachments preview
          _buildPendingPreviewRow(),

          // Input Bar
          _buildInputCard(),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    final canSend =
        _ready &&
        (inputCon.text.trim().isNotEmpty || _pendingImages.isNotEmpty);
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_sharp, color: Colors.black),
              onPressed: _showAttachSheet,
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    reverse: true,
                    child: TextField(
                      controller: inputCon,
                      maxLines: null,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Type here… e.g., “Paid ₦50,000 rent via GTBank” or “Sold goods ₦600,000, VAT 7.5%”',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _handleSubmit(),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                isListening ? UniconsLine.stop_circle : UniconsLine.microphone,
                color: isListening ? Colors.red : Colors.black54,
              ),
              iconSize: 20,
              onPressed: _startListening,
            ),
            IconButton(
              icon: Container(
                decoration: BoxDecoration(
                  color: canSend ? Colors.black : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(
                  UniconsLine.arrow_up,
                  color: canSend ? Colors.white : Colors.grey,
                  size: 25,
                ),
              ),
              onPressed: canSend ? _handleSubmit : null,
            ),
          ],
        ),
      ),
    );
  }
}
