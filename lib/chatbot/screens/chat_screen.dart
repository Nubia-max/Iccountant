// lib/chatbot/screens/chat_screen.dart
// Chat UI + dynamic Iccountant drawer.
// Flow: user sends → if /chat2 implies recording, show ephemeral "Recording…"
//       → auto-open suggested Google Sheet books → then show assistant's reply.

import 'dart:io';
import 'dart:async';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:unicons/unicons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:taxpal/services/google_connect_service.dart';
import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/widgets/iccountant_drawer.dart';

/// Same env var used elsewhere (main.dart, services, etc.)
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Services
  final ChatService _svc = ChatService(apiBase: API_BASE);

  // Chat state
  final List<ChatMessage> messages = [];
  final ChatUser user = ChatUser(id: 'u', firstName: 'You');
  final ChatUser bot = ChatUser(id: 'b', firstName: 'Iccountant');

  // UI & voice
  final TextEditingController inputCon = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  bool isListening = false;

  // Pending images (local preview only)
  final List<XFile> _pendingImages = [];

  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _autoConnectGoogleOnWeb();
    _initSpeech();
    _loadHistory();
  }

  Future<void> _autoConnectGoogleOnWeb() async {
    if (!kIsWeb) return;
    const apiBase = API_BASE; // reuse your const
    final svc = GoogleConnectService(baseUrl: apiBase);

    // If not connected yet, kick off the OAuth popup once.
    final connected = await svc.status();
    if (!mounted || connected) return;

    // Delay a tick to avoid layout jank, then start.
    await Future.delayed(const Duration(milliseconds: 250));
    // Fire and forget; it will show a tiny popup once.
    // After success, your /chat2 will be able to create Sheets.
    unawaited(svc.connect(context));
  }

  Future<void> _initSpeech() async {
    await _speechToText.initialize(
      onStatus: (s) {
        if (s == "done" || s == "notListening") {
          setState(() => isListening = false);
        }
      },
      onError: (_) => setState(() => isListening = false),
    );
  }

  // ------- Load chat history (newest first for DashChat)
  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final convId = await _svc.ensureActiveConversation();
      final items = await _svc.fetchMessages(convId);
      final converted =
          items.map((m) {
            final who = (m['role'] == 'user') ? user : bot;
            final createdAt = DateTime.tryParse(
              m['created_at']?.toString() ?? '',
            );
            return ChatMessage(
              text: (m['content'] ?? '').toString(),
              createdAt: createdAt ?? DateTime.now(),
              user: who,
            );
          }).toList();
      setState(() {
        messages
          ..clear()
          ..addAll(converted.reversed);
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ------- Chat send flow
  Future<void> _handleSubmit() async {
    final prompt = inputCon.text.trim();
    final hasImages = _pendingImages.isNotEmpty; // reserved for future
    final hasText = prompt.isNotEmpty;
    if (!hasImages && !hasText) return;

    // Show the user message immediately
    final userMsg = ChatMessage(
      text: prompt,
      createdAt: DateTime.now(),
      user: user,
    );
    messages.insert(0, userMsg);
    setState(() {});
    inputCon.clear();
    _pendingImages.clear();

    try {
      final out = await _svc.chat2(prompt);
      // after: final out = await _svc.chat2(prompt);
      if (out.warnings.isNotEmpty) {
        messages.insert(
          0,
          ChatMessage(
            text: '⚠️ ${out.warnings.join('\n')}',
            createdAt: DateTime.now(),
            user: bot,
          ),
        );
      }

      if (out.warnings.isNotEmpty) {
        debugPrint('Backend warnings: ${out.warnings}');
        messages.insert(
          0,
          ChatMessage(
            text: '⚠️ ${out.warnings.join('\n')}',
            createdAt: DateTime.now(),
            user: bot,
          ),
        );
      }
      debugPrint('posted_actions=${out.postedActions}');
      debugPrint('open_books=${out.openBooks.map((b) => b.sheetUrl).toList()}');

      final shouldShowRecording =
          out.openBooks.isNotEmpty || out.postedActions.isNotEmpty;

      if (shouldShowRecording) {
        // 1) Show ephemeral "Recording…" (or server-provided text)
        final temp = ChatMessage(
          text:
              out.ephemeralMessage?.isNotEmpty == true
                  ? out.ephemeralMessage!
                  : "Recording…",
          createdAt: DateTime.now(),
          user: bot,
        );
        messages.insert(0, temp);
        setState(() {});

        // 2) Open the suggested books sequentially as Sheets
        await IccountantDrawer.openFromChat2(out);

        // 3) Remove the ephemeral message if it's still visible
        final idx = messages.indexOf(temp);
        if (idx >= 0) {
          messages.removeAt(idx);
        }

        // 4) Now show the assistant's normal reply
        final reply = ChatMessage(
          text:
              out.assistantMessage.isNotEmpty ? out.assistantMessage : "Done.",
          createdAt: DateTime.now(),
          user: bot,
        );
        messages.insert(0, reply);
        if (mounted) setState(() {});
      } else {
        // No recording; just show the normal reply immediately
        final reply = ChatMessage(
          text:
              out.assistantMessage.isNotEmpty ? out.assistantMessage : "Done.",
          createdAt: DateTime.now(),
          user: bot,
        );
        messages.insert(0, reply);
        setState(() {});
      }
    } catch (e) {
      messages.insert(
        0,
        ChatMessage(
          text: "Network error: $e",
          createdAt: DateTime.now(),
          user: bot,
        ),
      );
      setState(() {});
    }
  }

  // ------- Voice
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

  // ------- Attachments preview row (images only, local)
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
                  onTap: () {
                    _pendingImages.removeAt(i);
                    setState(() {});
                  },
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

  // ------- Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Dynamic, Google-Sheets-powered drawer
          IccountantDrawer(key: IccountantDrawer.globalKey),
          Expanded(
            child:
                _loadingHistory
                    ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : DashChat(
                      currentUser: user,
                      onSend: (_) {},
                      readOnly: true,
                      messages: messages,
                    ),
          ),
          _buildPendingPreviewRow(),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final canSend =
        inputCon.text.trim().isNotEmpty || _pendingImages.isNotEmpty;
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
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                );
                if (result != null && result.files.isNotEmpty) {
                  // Keep local preview simple for now
                  setState(() {});
                }
              },
            ),
            Expanded(
              child: TextField(
                controller: inputCon,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      'Type here… e.g., “Sold goods ₦5,000 on credit to Tunde”',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
            IconButton(
              icon: Icon(
                isListening ? UniconsLine.stop_circle : UniconsLine.microphone,
                color: isListening ? Colors.red : Colors.black54,
              ),
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
