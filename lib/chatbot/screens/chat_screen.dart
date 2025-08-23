// lib/chatbot/screens/chat_screen.dart
// Streaming overlay replies (WebSocket → SSE → HTTP), sticky until you tap outside,
// thinking indicator, and AUTO-OPEN Sheets ONLY when the AI actually writes/updates a sheet.
// The “Open sheets” pill has been removed.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

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
  final ChatService _svc = ChatService(apiBase: API_BASE);

  final SpeechToText _speechToText = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController inputCon = TextEditingController();

  bool isListening = false;
  bool _loadingHistory = false;
  final List<XFile> _pendingImages = [];

  // Overlay state
  String? _overlayText;
  bool _overlayBusy = false;
  bool _overlaySticky = false;
  late final AnimationController _overlayAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // Streaming subscription
  StreamSubscription<ChatStreamEvent>? _streamSub;

  // Auto-open guard per turn
  bool _openedThisTurn = false;

  // Chips transcript
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
    _streamSub?.cancel();
    _overlayAnim.dispose();
    super.dispose();
  }

  Future<void> _autoConnectGoogleOnWeb() async {
    if (!kIsWeb) return;
    final svc = GoogleConnectService(baseUrl: API_BASE);
    final connected = await svc.status();
    if (!mounted || connected) return;
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
          ..addAll(chips.take(12).toList().reversed);
      });
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _showOverlay(String text, {bool busy = false, bool sticky = true}) {
    setState(() {
      _overlayText = text;
      _overlayBusy = busy;
      _overlaySticky = sticky;
    });
    _overlayAnim.forward(from: 0);
  }

  void _hideOverlay() {
    if (_overlayBusy) return; // don't dismiss while streaming
    setState(() {
      _overlayText = null;
      _overlaySticky = false;
    });
  }

  // Voice
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
    setState(() => inputCon.text = r.recognizedWords);
    if (r.finalResult) {
      _speechToText.stop();
      setState(() => isListening = false);
    }
  }

  // Send (streaming via WS → SSE → HTTP)
  Future<void> _handleSubmit() async {
    final prompt = inputCon.text.trim();
    final hasImages = _pendingImages.isNotEmpty;
    if (prompt.isEmpty && !hasImages) return;

    setState(() {
      _chips.insert(
        0,
        _ChipMsg(text: prompt, fromUser: true, when: DateTime.now()),
      );
    });
    inputCon.clear();
    _pendingImages.clear();

    // cancel any previous stream
    await _streamSub?.cancel();

    // reset per-turn open guard
    _openedThisTurn = false;

    // show thinking
    _showOverlay('Thinking…', busy: true, sticky: true);

    _streamSub = _svc
        .streamChat(prompt)
        .listen(
          (ev) async {
            if (!mounted) return;

            if (ev.delta != null) {
              final next =
                  (_overlayText == null || _overlayText == 'Thinking…')
                      ? ev.delta!
                      : (_overlayText! + ev.delta!);
              setState(() {
                _overlayText = next;
                _overlayBusy = true; // keep spinner during deltas
              });
              return;
            }

            if (ev.finalResponse != null) {
              final out = ev.finalResponse!;
              final reply =
                  out.assistantMessage.isNotEmpty
                      ? out.assistantMessage
                      : 'Done.';

              // UI update
              setState(() {
                if ((_overlayText ?? '').trim().isEmpty ||
                    _overlayText == 'Thinking…') {
                  _overlayText = reply;
                }
                _overlayBusy = false;
                _overlaySticky = true;

                _chips.insert(
                  0,
                  _ChipMsg(text: reply, fromUser: false, when: DateTime.now()),
                );

                if (out.warnings.isNotEmpty) {
                  _chips.insert(
                    0,
                    _ChipMsg(
                      text: '⚠️ ${out.warnings.join('\n')}',
                      fromUser: false,
                      when: DateTime.now(),
                      toneWarning: true,
                    ),
                  );
                }
              });

              // === AUTO-OPEN LOGIC ===
              // Open exactly once per turn, only if the server says there are books to open.
              if (!_openedThisTurn && out.openBooks.isNotEmpty) {
                _openedThisTurn = true;

                // Deduplicate by sheetUrl/sheetId defensively
                final dedup = <String, BookRef>{};
                for (final b in out.openBooks) {
                  final key =
                      (b.sheetId?.isNotEmpty == true ? b.sheetId! : b.sheetUrl);
                  if (key.isEmpty) continue;
                  dedup[key] = b;
                }
                final booksToOpen = dedup.values.toList();

                if (booksToOpen.isNotEmpty) {
                  final resp = Chat2Response(
                    assistantMessage: out.assistantMessage,
                    postedActions: out.postedActions,
                    warnings: out.warnings,
                    createdStatementIds: out.createdStatementIds,
                    appendedJournalIds: out.appendedJournalIds,
                    ephemeralMessage: out.ephemeralMessage,
                    openBooks: booksToOpen,
                  );
                  await IccountantDrawer.openFromChat2(resp);
                }
              }
              // === /AUTO-OPEN LOGIC ===
            }
          },
          onError: (e) {
            if (!mounted) return;
            _showOverlay('Network error: $e', busy: false, sticky: true);
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _overlayBusy = false);
          },
        );
  }

  // Attachments preview row
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
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<Uint8List>(
              future: img.readAsBytes(),
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
          );
        },
      ),
    );
  }

  // Command bar
  Widget _commandBar() {
    final canSend =
        inputCon.text.trim().isNotEmpty || _pendingImages.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Material(
          color: Colors.white.withOpacity(0.85),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x1A000000)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
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
                      setState(() {}); // local preview only
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
                      hintText: 'Ask Iccountant',
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

  // Dismissable, scrollable overlay card
  Widget _overlayCard(BuildContext context, String text, {bool busy = false}) {
    final maxH = MediaQuery.of(context).size.height * 0.65;
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
                child: Material(
                  color: Colors.white.withOpacity(0.9),
                  child: Container(
                    decoration: BoxDecoration(
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
                    padding: const EdgeInsets.all(20),
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
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxH),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                text,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  height: 1.42,
                                ),
                              ),
                            ),
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
      ),
    );
  }

  // Chips — tap to view full message
  Widget _chipsTranscript() {
    if (_chips.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children:
            _chips.take(10).map((c) {
              final bg =
                  c.toneWarning
                      ? const Color(0xFFFFF3CD)
                      : (c.fromUser
                          ? const Color(0xFFE8F0FE)
                          : const Color(0xFFF6F6F6));
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(
                    c.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: bg,
                  side: BorderSide(color: Colors.black12.withOpacity(0.6)),
                  onPressed:
                      () => _showOverlay(c.text, busy: false, sticky: true),
                ),
              );
            }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth >= 1100;

          final content = Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF9FBFF), Color(0xFFFDFDFD)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Chips
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _chipsTranscript(),
                ),
                // Pending preview
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 82 + MediaQuery.of(context).padding.bottom,
                  child: _buildPendingPreviewRow(),
                ),
                // Tap-anywhere-to-dismiss (only when sticky)
                if (_overlayText != null && _overlaySticky)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _hideOverlay,
                      child: const SizedBox.expand(),
                    ),
                  ),
                // Overlay card
                if (_overlayText != null)
                  _overlayCard(context, _overlayText!, busy: _overlayBusy),
                // Command bar
                Positioned(left: 0, right: 0, bottom: 0, child: _commandBar()),
              ],
            ),
          );

          if (isWide) {
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
