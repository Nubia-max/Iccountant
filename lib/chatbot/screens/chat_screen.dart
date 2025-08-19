// lib/chatbot/screens/chat_screen.dart
// Chat + "Iccountant" drawer with mini-worksheets + full-screen viewers.

import 'dart:convert';
import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:unicons/unicons.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Same env var used in other files (main.dart, services, etc.)
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
  // Drawer
  bool isDrawerOpen = false;

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

  // Drawer data (mini-worksheets)
  List<Map<String, dynamic>> _tbRows = [];
  Map<String, num> _tbTotals = const {'debit': 0, 'credit': 0};
  List<Map<String, dynamic>> _journalEntries = [];
  List<Map<String, dynamic>> _statements = [];

  bool _loadingDrawer = false;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadHistory();
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

  Future<Map<String, String>> _authHeaders() async {
    // Force refresh to avoid expired/empty token issues right after sign up
    final tok = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    return {
      'Accept': 'application/json',
      if (tok != null) 'Authorization': 'Bearer $tok',
    };
  }

  // ------- Load chat history (newest first for DashChat)
  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final h = await _authHeaders();
      final uri = Uri.parse('$API_BASE/messages?conversation_id=default');
      final res = await http.get(uri, headers: h);
      if (res.statusCode == 200) {
        final List body = jsonDecode(res.body) as List;
        final items = body.map((e) => e as Map<String, dynamic>).toList();
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
      }
    } catch (_) {
      /* ignore for now */
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ------- Drawer fetch
  Future<void> _loadDrawer() async {
    setState(() => _loadingDrawer = true);
    try {
      final h = await _authHeaders();

      // Trial balance rows
      final tbRes = await http.get(
        Uri.parse('$API_BASE/trial_balance'),
        headers: h,
      );
      if (tbRes.statusCode == 200) {
        final tb = jsonDecode(tbRes.body) as Map<String, dynamic>;
        _tbRows =
            (tb['rows'] as List? ?? const [])
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
        _tbTotals =
            (tb['totals'] as Map?)?.cast<String, num>() ??
            const {'debit': 0, 'credit': 0};
      } else {
        _tbRows = [];
        _tbTotals = const {'debit': 0, 'credit': 0};
      }

      // Journals (each item has "lines")
      final jRes = await http.get(
        Uri.parse('$API_BASE/journals?limit=20'),
        headers: h,
      );
      _journalEntries =
          (jRes.statusCode == 200)
              ? (jsonDecode(jRes.body) as List)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList()
              : <Map<String, dynamic>>[];

      // Statements list (id, name, period)
      final sRes = await http.get(
        Uri.parse('$API_BASE/statements?limit=50'),
        headers: h,
      );
      _statements =
          (sRes.statusCode == 200)
              ? (jsonDecode(sRes.body) as List)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList()
              : <Map<String, dynamic>>[];

      if (mounted) setState(() {});
    } catch (_) {
      // ignore for now
    } finally {
      if (mounted) setState(() => _loadingDrawer = false);
    }
  }

  // ------- Chat send flow (calls /chat2 directly with Firebase token)
  Future<void> _handleSubmit() async {
    final prompt = inputCon.text.trim();
    final hasImages = _pendingImages.isNotEmpty;
    final hasText = prompt.isNotEmpty;
    if (!hasImages && !hasText) return;

    // Show user message
    messages.insert(
      0,
      ChatMessage(text: prompt, createdAt: DateTime.now(), user: user),
    );
    setState(() {});
    inputCon.clear();
    _pendingImages.clear();

    String reply = "…";
    try {
      final h = await _authHeaders();
      final uri = Uri.parse('$API_BASE/chat2');
      final res = await http.post(
        uri,
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'conversation_id': 'default', 'message': prompt}),
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        reply =
            (body['assistant_message'] ?? body['message'] ?? 'Done.')
                .toString();
        // Optional: if actions posted statements, refresh drawer
        await _loadDrawer();
      } else if (res.statusCode == 401) {
        reply = "You’re not signed in (401). Please login again.";
      } else if (res.statusCode == 400) {
        final body = jsonDecode(res.body);
        reply =
            (body['error'] ?? body['message'] ?? 'I need a bit more info.')
                .toString();
      } else {
        reply = "Backend error ${res.statusCode}";
      }
    } catch (e) {
      reply = "Network error: $e";
    }

    messages.insert(
      0,
      ChatMessage(text: reply, createdAt: DateTime.now(), user: bot),
    );
    setState(() {});
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

  // ------- Drawer UI (mini-worksheets grid)
  Widget _drawer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isDrawerOpen ? 420 : 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.3), width: 1),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () async {
              setState(() => isDrawerOpen = !isDrawerOpen);
              if (!isDrawerOpen) return;
              await _loadDrawer();
            },
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Iccountant', style: TextStyle(fontSize: 18)),
                Icon(
                  isDrawerOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ],
            ),
          ),
          if (isDrawerOpen)
            Expanded(
              child:
                  _loadingDrawer
                      ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: GridView(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.35,
                              ),
                          children: [
                            _miniSheetCard(
                              title: 'Trial Balance',
                              child: _miniTable(
                                headers: const ['Account', 'Debit', 'Credit'],
                                rows:
                                    _tbRows
                                        .take(10)
                                        .map(
                                          (r) => [
                                            r['account']?.toString() ?? '',
                                            (r['debit'] ?? 0).toString(),
                                            (r['credit'] ?? 0).toString(),
                                          ],
                                        )
                                        .toList(),
                              ),
                              onOpen: _openTrialBalanceFull,
                            ),
                            _miniSheetCard(
                              title: 'Journals',
                              child: _miniTable(
                                headers: const [
                                  'Date',
                                  'Narration',
                                  'Dr Acct',
                                  'Dr',
                                  'Cr Acct',
                                  'Cr',
                                ],
                                rows:
                                    _journalEntries
                                        .take(10)
                                        .map(_flattenJournalRow)
                                        .toList(),
                              ),
                              onOpen: _openJournalsFull,
                            ),
                            _miniSheetCard(
                              title: 'Statements',
                              child: _miniStatementsList(),
                              onOpen: _openStatementsListFull,
                            ),
                          ],
                        ),
                      ),
            ),
        ],
      ),
    );
  }

  // Build one-row snapshot from a journal entry (first DR & first CR line)
  List<String> _flattenJournalRow(Map<String, dynamic> e) {
    String drAcct = '', crAcct = '';
    num dr = 0, cr = 0;
    final lines = (e['lines'] as List? ?? const []).cast<Map>();
    for (final ln in lines) {
      final debit = (ln['debit'] ?? 0) as num;
      final credit = (ln['credit'] ?? 0) as num;
      if (debit > 0 && dr == 0) {
        dr = debit;
        drAcct = (ln['account'] ?? '').toString();
      }
      if (credit > 0 && cr == 0) {
        cr = credit;
        crAcct = (ln['account'] ?? '').toString();
      }
      if (dr > 0 && cr > 0) break;
    }
    return [
      (e['date'] ?? '').toString(),
      (e['narration'] ?? '').toString(),
      drAcct,
      dr.toString(),
      crAcct,
      cr.toString(),
    ];
  }

  Widget _miniSheetCard({
    required String title,
    required Widget child,
    required VoidCallback onOpen,
  }) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.open_in_new, size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 420),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: DataTable(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                dataTextStyle: const TextStyle(fontSize: 12),
                columns:
                    headers.map((h) => DataColumn(label: Text(h))).toList(),
                rows:
                    rows
                        .map(
                          (r) => DataRow(
                            cells: r.map((c) => DataCell(Text(c))).toList(),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStatementsList() {
    if (_statements.isEmpty) {
      return const Center(
        child: Text('No statements yet', style: TextStyle(fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: _statements.length.clamp(0, 6),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = _statements[i];
        final name = (s['name'] ?? '').toString();
        final ps = (s['period_start'] ?? '').toString();
        final pe = (s['period_end'] ?? '').toString();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([ps, pe].where((x) => x.isNotEmpty).join(' → ')),
          trailing: const Icon(Icons.chevron_right, size: 16),
          onTap: () => _openStatementDetail(s['id']),
        );
      },
    );
  }

  // ------- Full screens
  void _openTrialBalanceFull() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => _FullTableScreen(
              title: 'Trial Balance',
              headers: const ['Account', 'Debit', 'Credit'],
              rows:
                  _tbRows
                      .map(
                        (r) => [
                          r['account']?.toString() ?? '',
                          (r['debit'] ?? 0).toString(),
                          (r['credit'] ?? 0).toString(),
                        ],
                      )
                      .toList(),
            ),
      ),
    );
  }

  void _openJournalsFull() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => _FullTableScreen(
              title: 'Journals',
              headers: const [
                'Date',
                'Narration',
                'Dr Acct',
                'Dr',
                'Cr Acct',
                'Cr',
              ],
              rows: _journalEntries.map(_flattenJournalRow).toList(),
            ),
      ),
    );
  }

  void _openStatementsListFull() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _StatementsListScreen()),
    );
  }

  Future<void> _openStatementDetail(dynamic id) async {
    final h = await _authHeaders();
    final res = await http.get(
      Uri.parse('$API_BASE/statements/$id'),
      headers: h,
    );
    if (res.statusCode != 200) return;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StatementDetailScreen(statement: body),
      ),
    );
  }

  // ------- Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _drawer(),
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

// ===== Full-table viewer =====
class _FullTableScreen extends StatelessWidget {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  const _FullTableScreen({
    required this.title,
    required this.headers,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 700),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: DataTable(
                  columns:
                      headers.map((h) => DataColumn(label: Text(h))).toList(),
                  rows:
                      rows
                          .map(
                            (r) => DataRow(
                              cells: r.map((c) => DataCell(Text(c))).toList(),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Statements list (full) =====
class _StatementsListScreen extends StatefulWidget {
  const _StatementsListScreen();

  @override
  State<_StatementsListScreen> createState() => _StatementsListScreenState();
}

class _StatementsListScreenState extends State<_StatementsListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tok = await FirebaseAuth.instance.currentUser?.getIdToken();
      final res = await http.get(
        Uri.parse('$API_BASE/statements?limit=200'),
        headers: {
          'Accept': 'application/json',
          if (tok != null) 'Authorization': 'Bearer $tok',
        },
      );
      if (res.statusCode == 200) {
        final List body = jsonDecode(res.body) as List;
        setState(() {
          _items = body.map((e) => (e as Map).cast<String, dynamic>()).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statements')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = _items[i];
                  final name = (s['name'] ?? '').toString();
                  final ps = (s['period_start'] ?? '').toString();
                  final pe = (s['period_end'] ?? '').toString();
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(
                      [ps, pe].where((x) => x.isNotEmpty).join(' → '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final tok =
                          await FirebaseAuth.instance.currentUser?.getIdToken();
                      final res = await http.get(
                        Uri.parse('$API_BASE/statements/${s['id']}'),
                        headers: {
                          'Accept': 'application/json',
                          if (tok != null) 'Authorization': 'Bearer $tok',
                        },
                      );
                      if (res.statusCode == 200 && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => _StatementDetailScreen(
                                  statement:
                                      jsonDecode(res.body)
                                          as Map<String, dynamic>,
                                ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
    );
  }
}

// ===== Statement detail (generic renderer) =====
class _StatementDetailScreen extends StatelessWidget {
  final Map<String, dynamic> statement;
  const _StatementDetailScreen({required this.statement});

  Widget _renderContent(dynamic content) {
    if (content is Map<String, dynamic>) {
      final entries = content.entries.toList();
      return ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final k = entries[i].key.toString();
          final v = entries[i].value;
          return ListTile(
            title: Text(k),
            trailing: Text(v is num ? v.toStringAsFixed(2) : v.toString()),
          );
        },
      );
    }
    if (content is List) {
      return ListView.separated(
        itemCount: content.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => ListTile(title: Text(content[i].toString())),
      );
    }
    return Center(child: Text(content?.toString() ?? 'No content'));
  }

  @override
  Widget build(BuildContext context) {
    final name = (statement['name'] ?? 'Statement').toString();
    final content = statement['content'];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _renderContent(content),
    );
  }
}
