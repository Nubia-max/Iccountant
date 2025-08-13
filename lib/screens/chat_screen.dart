import 'dart:convert';
import 'dart:io';
import 'package:unicons/unicons.dart';
import 'package:taxpal/ChatService.dart';
import 'package:taxpal/ImageScreen.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? toggleDrawer;
  const ChatScreen({super.key, this.toggleDrawer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool isDrawerOpen = false; // Track the drawer state
  // ----------------------------------
  // State / Models
  // ----------------------------------
  var resultText = 'Results to be shown here...';
  final List<ChatMessage> messages = [];

  final ChatUser user = ChatUser(id: '1', firstName: 'Hamza', lastName: 'Asif');
  final ChatUser openAIUser = ChatUser(
    id: '2',
    firstName: 'Tax',
    lastName: 'Pal',
  );

  /// OpenAI-style rolling history
  final List<Map<String, Object>> chatHistory = [
    {
      "role": "system",
      "content": """
You are a certified Nigerian tax consultant trained in line with the Institute of Chartered Accountants of Nigeria (ICAN) guidelines. Always give practical, compliant Nigerian tax guidance in clear English (or Nigerian Pidgin if asked).""",
    },
  ];

  // ----------------------------------
  // Services / Controllers
  // ----------------------------------
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController inputCon = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late ChatService chatService;

  // ----------------------------------
  // Feature Flags
  // ----------------------------------
  bool isTTS = false;

  // ----------------------------------
  // Pending attachments (pre-send)
  // ----------------------------------
  /// All selected (but not yet sent) images.
  /// We support adding from gallery (multi) and camera (single add).
  final List<XFile> _pendingImages = [];

  // ----------------------------------
  // Lifecycle
  // ----------------------------------
  @override
  void initState() {
    super.initState();
    _secureKey();
    _ttsSettings();
    _initSpeech();
  }

  // ----------------------------------
  // Secure Key bootstrap (replace "" w/ real key)
  // ----------------------------------
  Future<void> _secureKey() async {
    await _storage.write(key: "id1", value: ""); // <-- put your API key here
    _loadKey();
  }

  Future<void> _loadKey() async {
    final String? value = await _storage.read(key: "id1");
    if (value != null) {
      chatService = ChatService(value);
    }
  }

  // ----------------------------------
  // Speech
  // ----------------------------------
  Future<void> _initSpeech() async {
    await _speechToText.initialize();
    setState(() {}); // reflect availability if you want to show UI state
  }

  bool isListening = false;
  Future<void> _startListening() async {
    if (isListening) {
      await _speechToText.stop();
      setState(() => isListening = false);
      return;
    }

    final bool available = await _speechToText.initialize(
      onStatus: (status) {
        if (status == "done" || status == "notListening") {
          setState(() => isListening = false);
        }
      },
      onError: (error) {
        debugPrint("Speech error: $error");
        setState(() => isListening = false);
      },
    );

    if (available) {
      setState(() => isListening = true);
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      );
    } else {
      debugPrint("Speech not available");
    }
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      inputCon.text = result.recognizedWords;
    });

    if (result.finalResult) {
      _speechToText.stop();
      setState(() => isListening = false);
    }
  }

  // ----------------------------------
  // TTS
  // ----------------------------------
  Future<void> _ttsSettings() async {
    if (await flutterTts.isLanguageAvailable("en-US")) {
      await flutterTts.setLanguage("en-US");
      await flutterTts.setVoice({
        "name": "en-us-x-tpd-local",
        "locale": "en-US",
      });
    }
  }

  // ----------------------------------
  // Attachments: Image Selection
  // ----------------------------------
  /// Pick *multiple* from gallery.
  Future<void> _pickImagesFromGallery() async {
    final List<XFile> picks = await _picker.pickMultiImage();
    if (picks.isEmpty) return;
    _pendingImages.addAll(picks);
    setState(() {});
  }

  /// Capture single image, append to pending list.
  Future<void> _captureImageCamera() async {
    final XFile? shot = await _picker.pickImage(source: ImageSource.camera);
    if (shot == null) return;
    _pendingImages.add(shot);
    setState(() {});
  }

  /// Remove image at index from pending list.
  void _removePendingImage(int idx) {
    if (idx < 0 || idx >= _pendingImages.length) return;
    _pendingImages.removeAt(idx);
    setState(() {});
  }

  /// Build horizontal preview row (ChatGPT-style).
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

  // ----------------------------------
  // Audio Attach (unchanged)
  // ----------------------------------
  Future<void> _selectAudio() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result == null) return;

    // Show user audio file message
    messages.insert(
      0,
      ChatMessage(
        text: "",
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

    // Convert to text (server side)
    resultText = await chatService.audioToText(result.files.first.path!);

    // Show AI transcription
    messages.insert(
      0,
      ChatMessage(
        text: resultText,
        createdAt: DateTime.now(),
        user: openAIUser,
      ),
    );
    setState(() {});
  }

  // ----------------------------------
  // Send to AI
  // ----------------------------------
  Future<void> _askChatGPT() async {
    final String prompt = inputCon.text.trim();
    final bool hasImages = _pendingImages.isNotEmpty;
    final bool hasText = prompt.isNotEmpty;

    if (!hasImages && !hasText) return;

    // 1. Show user message in chat (text + medias)
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
    messages.insert(
      0,
      ChatMessage(
        text: prompt, // may be ""
        createdAt: DateTime.now(),
        user: user,
        medias: medias,
      ),
    );
    setState(() {});

    // 2. Push into chatHistory (OpenAI input format)
    if (hasImages) {
      // Build content array of image objects + optional text
      final List<Object> contentBlocks =
          _pendingImages
              .map(
                (x) => {
                  "type": "image_url",
                  "image_url": {
                    "url":
                        "data:image/jpeg;base64,${base64Encode(File(x.path).readAsBytesSync())}",
                  },
                },
              )
              .toList();

      if (hasText) {
        contentBlocks.add({"type": "text", "text": prompt});
      }

      chatHistory.add({"role": "user", "content": contentBlocks});
    } else if (hasText) {
      chatHistory.add({"role": "user", "content": prompt});
    }

    // 3. Clear user input + previews
    inputCon.clear();
    _pendingImages.clear();
    setState(() {});

    // 4. Call model
    resultText = await chatService.askChatGPT(chatHistory);

    // 5. TTS (optional)
    if (isTTS) await flutterTts.speak(resultText);

    // 6. Append assistant in history & chat
    chatHistory.add({"role": "assistant", "content": resultText});
    messages.insert(
      0,
      ChatMessage(
        text: resultText,
        createdAt: DateTime.now(),
        user: openAIUser,
      ),
    );
    setState(() {});
  }

  // ----------------------------------
  // Generate Images (prompt → DALL·E / etc.)
  // ----------------------------------
  Future<void> _generateImages() async {
    final String prompt = inputCon.text;
    if (prompt.trim().isEmpty) return;

    messages.insert(
      0,
      ChatMessage(text: prompt, createdAt: DateTime.now(), user: user),
    );
    setState(() {});

    inputCon.clear();

    final List<String> imageUrls = await chatService.generateImages(prompt);
    final List<ChatMedia> genImages =
        imageUrls
            .map(
              (item) => ChatMedia(
                url: item,
                fileName: "image",
                type: MediaType.image,
              ),
            )
            .toList();

    messages.insert(
      0,
      ChatMessage(
        createdAt: DateTime.now(),
        user: openAIUser,
        medias: genImages,
      ),
    );
    setState(() {});
  }

  // ----------------------------------
  // Bottom sheet: choose source (like ChatGPT)
  // ----------------------------------
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

  // ----------------------------------
  // Build
  // ----------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Drawer (Top Drawer)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height:
                isDrawerOpen ? 600 : 60, // Height changes based on drawer state
            decoration: BoxDecoration(
              color: Colors.white, // Use color inside BoxDecoration
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(0.3), // Light grey border
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isDrawerOpen = !isDrawerOpen;
                    });
                  },
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
                if (isDrawerOpen) ...[
                  // Content of the drawer when open
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    child: const Text(
                      'Drawer Content Here',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
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

          // Pending attachments row
          _buildPendingPreviewRow(),

          // Input Bar
          _buildInputCard(),
        ],
      ),
    );
  }

  // ----------------------------------
  // Input Card Widget
  // ----------------------------------
  Widget _buildInputCard() {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.center, // Align icons on the same line
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_sharp, color: Colors.black),
              onPressed: _showAttachSheet,
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 120, // roughly 5 lines
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    reverse: true,
                    child: TextField(
                      controller: inputCon,
                      maxLines: null, // expands vertically
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Type here...',
                      ),
                      onChanged: (text) {
                        setState(() {
                          // Trigger rebuild to check if text is entered
                        });
                      },
                      onSubmitted: (_) => _handleSubmit(),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                isListening
                    ? UniconsLine
                        .stop_circle // UniIcon for stop circle
                    : UniconsLine.microphone, // UniIcon for microphone
                color: isListening ? Colors.red : Colors.black54,
              ),
              iconSize:
                  20, // Set the icon size (default is 24, adjust as needed)
              onPressed: _startListening,
            ),

            // Replace the arrow icon with UniIcon and make it unclickable when no text or image
            IconButton(
              icon: Container(
                decoration: BoxDecoration(
                  color:
                      inputCon.text.isEmpty
                          ? Colors.grey[300]
                          : Colors
                              .black, // Light grey when empty, black when text is present
                  shape: BoxShape.circle, // Makes the container a circle
                ),
                padding: const EdgeInsets.all(
                  8,
                ), // Padding to make the circle size bigger
                child: Icon(
                  UniconsLine
                      .arrow_up, // Correct UniconsLine icon for "up" arrow
                  color:
                      inputCon.text.isEmpty
                          ? Colors.grey
                          : Colors
                              .white, // Dim color when empty, white when active
                  size: 25, // Increase the icon size
                ),
              ),
              onPressed:
                  inputCon.text.isEmpty
                      ? null
                      : _handleSubmit, // Disable if empty
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------
  // Unified submit dispatcher
  // ----------------------------------
  void _handleSubmit() {
    final txt = inputCon.text.toLowerCase();
    if (txt.startsWith("generate image")) {
      _generateImages();
    } else {
      _askChatGPT();
    }
  }
}
