// lib/chatbot/screens/chat_screen.dart
// World-class chat experience with “on-screen” AI replies (overlay card),
// and a responsive Iccountant drawer that becomes a sidebar on large screens.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter; // for BackdropFilter blur
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:unicons/unicons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:taxpal/services/google_connect_service.dart';
import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/widgets/iccountant_drawer.dart';

// Same env var used elsewhere
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  // Services
  final ChatService _svc = ChatService(apiBase: API_BASE);

  // Voice & images (kept for future expansion)
  final SpeechToText _speechToText = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController inputCon = TextEditingController();

  bool isListening = false;
  bool _loadingHistory = false;
  final List<XFile> _pendingImages = [];

  // “On-screen” reply overlay
  String? _overlayText;
  bool _overlayBusy = false; // for “Recording…” or ephemeral
  late final AnimationController _overlayAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  // Minimal transcript chips (optional, light history)
  final List<_ChipMsg> _chips = <_ChipMsg>[];

  @override
  void initState() {
    super.initState();
    _autoConnectGoogleOnWeb();
    _initSpeech();
    _loadHistory();
  }

  @override
  void dispose() {
    _overlayAnim.dispose();
    super.dispose();
  }

  Future<void> _autoConnectGoogleOnWeb() async {
    if (!kIsWeb) return;
    final svc = GoogleConnectService(baseUrl: API_BASE);
    final connected = await svc.status();
    if (!mounted || connected) return;
    // Nudge once after a tiny delay
    await Future.delayed(const Duration(milliseconds: 250));
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

  Future<void> _loadHistory() async {
    // We keep history as tiny chips, not bubble UI
    setState(() => _loadingHistory = true);
    try {
      final convId = await _svc.ensureActiveConversation();
      final items = await _svc.fetchMessages(convId);
      final chips =
          items.map((m) {
            final role = (m['role'] ?? '').toString();
            final text = (m['content'] ?? '').toString();
            return _ChipMsg(
              text: text,
              fromUser: role == 'user',
              when:
                  DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                  DateTime.now(),
            );
          }).toList();
      setState(() {
        _chips
          ..clear()
          ..addAll(chips.take(12).toList().reversed); // keep it light
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
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

  // ------- Send flow
  Future<void> _handleSubmit() async {
    final prompt = inputCon.text.trim();
    final hasImages = _pendingImages.isNotEmpty; // reserved
    if (prompt.isEmpty && !hasImages) return;

    // Add tiny chip for the user's command (keeps the “no chatbox” vibe)
    setState(() {
      _chips.insert(
        0,
        _ChipMsg(text: prompt, fromUser: true, when: DateTime.now()),
      );
    });
    inputCon.clear();
    _pendingImages.clear();

    try {
      final out = await _svc.chat2(prompt);

      // Show “Recording…” overlay while we open Sheets and do actions
      final shouldShowRecording =
          out.openBooks.isNotEmpty || out.postedActions.isNotEmpty;
      if (shouldShowRecording) {
        setState(() {
          _overlayBusy = true;
          _overlayText =
              out.ephemeralMessage?.isNotEmpty == true
                  ? out.ephemeralMessage
                  : 'Recording…';
        });
        _overlayAnim.forward(from: 0);
      }

      // Open suggested books (thumbnails/values render in the drawer)
      await IccountantDrawer.openFromChat2(out);

      // Now show the final assistant reply as a large on-screen card
      setState(() {
        _overlayBusy = false;
        _overlayText =
            (out.assistantMessage.isNotEmpty ? out.assistantMessage : 'Done.');
      });
      _overlayAnim.forward(from: 0);

      // Keep a tiny transcript chip for the bot too
      setState(() {
        _chips.insert(
          0,
          _ChipMsg(text: _overlayText!, fromUser: false, when: DateTime.now()),
        );
      });

      // Auto-hide overlay after a few seconds (but leave chip transcript)
      Future.delayed(const Duration(seconds: 8), () {
        if (!mounted) return;
        if (!_overlayBusy) {
          setState(() => _overlayText = null);
        }
      });

      // Warnings (if any) appear as a subtle footer chip
      if (out.warnings.isNotEmpty) {
        setState(() {
          _chips.insert(
            0,
            _ChipMsg(
              text: '⚠️ ${out.warnings.join('\n')}',
              fromUser: false,
              when: DateTime.now(),
              toneWarning: true,
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _overlayBusy = false;
        _overlayText = 'Network error: $e';
      });
      _overlayAnim.forward(from: 0);
      Future.delayed(const Duration(seconds: 6), () {
        if (!mounted) return;
        if (!_overlayBusy) setState(() => _overlayText = null);
      });
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
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<Uint8List>(
                  future: img.readAsBytes(), // works on mobile & web
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return Container(
                        width: 76,
                        height: 76,
                        color: Colors.grey.shade300,
                      );
                    }
                    return Image.memory(
                      snap.data!,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                    );
                  },
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

  // ------- Command bar (no “chatbox”, a modern command palette)
  Widget _commandBar() {
    final canSend =
        inputCon.text.trim().isNotEmpty || _pendingImages.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Material(
          // Give TextField/Buttons a proper Material ancestor
          color: Colors.white.withOpacity(0.85),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x1A000000)), // subtle border
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            // keep the soft shadow/aesthetic
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach',
                  icon: const Icon(Icons.attach_file_outlined),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      allowMultiple: false,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      setState(() {}); // preview handling stays the same
                    }
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: inputCon,
                    maxLines: 4,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          'Ask anything… e.g. “Post ₦5,000 sales on credit to Tunde”',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                ),
                IconButton(
                  tooltip: isListening ? 'Stop' : 'Voice',
                  icon: Icon(
                    isListening
                        ? UniconsLine.stop_circle
                        : UniconsLine.microphone,
                  ),
                  color: isListening ? Colors.red : Colors.black54,
                  onPressed: _startListening,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor:
                          canSend ? Colors.black : Colors.grey[300],
                      foregroundColor: canSend ? Colors.white : Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onPressed: canSend ? _handleSubmit : null,
                    icon: const Icon(UniconsLine.arrow_up),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayCard(String text, {bool busy = false}) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _overlayAnim, curve: Curves.easeOut),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x16000000),
                        blurRadius: 18,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(right: 12, top: 2),
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 16.5, height: 1.42),
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(left: 12, top: 4),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipsTranscript() {
    if (_chips.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children:
            _chips.take(10).map((c) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(
                    c.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor:
                      c.toneWarning
                          ? const Color(0xFFFFF3CD)
                          : (c.fromUser
                              ? const Color(0xFFE8F0FE)
                              : const Color(0xFFF6F6F6)),
                  side: BorderSide(color: Colors.black12.withOpacity(0.6)),
                ),
              );
            }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // <-- Provides the needed Material ancestor
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth >= 1100; // responsive switch

          final content = Material(
            color: Colors.transparent, // let gradient show
            child: Stack(
              children: [
                // Soft gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF9FBFF), Color(0xFFFDFDFD)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Transcript chips row
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _chipsTranscript(),
                ),
                // Optional image preview row
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 82 + MediaQuery.of(context).padding.bottom,
                  child: _buildPendingPreviewRow(),
                ),
                // On-screen AI reply
                if (_overlayText != null)
                  _overlayCard(_overlayText!, busy: _overlayBusy),
                // Command bar
                Positioned(left: 0, right: 0, bottom: 0, child: _commandBar()),
              ],
            ),
          );

          if (isWide) {
            // Sidebar mode
            return Row(
              children: [
                SizedBox(
                  width: 320,
                  child: IccountantDrawer(
                    key: IccountantDrawer.globalKey,
                    placement: DrawerPlacement.side,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }

          // Top drawer mode (mobile / narrow)
          return Column(
            children: [
              IccountantDrawer(
                key: IccountantDrawer.globalKey,
                placement: DrawerPlacement.top,
              ),
              const Divider(height: 1),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _ChipMsg {
  final String text;
  final bool fromUser;
  final DateTime when;
  final bool toneWarning;
  _ChipMsg({
    required this.text,
    required this.fromUser,
    required this.when,
    this.toneWarning = false,
  });
}
