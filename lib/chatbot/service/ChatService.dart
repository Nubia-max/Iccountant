// lib/chatbot/service/ChatService.dart
// Chat + Books service with WebSocket streaming (primary) and SSE (fallback).
// - streamChat(): tries WS → SSE → one-shot HTTP
// - SSE parsing fixed: only the top-level async* uses `yield`.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String _API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

class BookRef {
  final String name;
  final String sheetUrl; // full Google Sheets URL
  final String sheetId; // Drive fileId
  final String? kind; // "journal", "ledger", "sofp", "sopl", etc.
  final DateTime? updatedAt;

  BookRef({
    required this.name,
    required this.sheetUrl,
    required this.sheetId,
    this.kind,
    this.updatedAt,
  });

  factory BookRef.fromJson(Map<String, dynamic> m) {
    DateTime? _parseDt(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    return BookRef(
      name: (m['name'] ?? 'Sheet').toString(),
      sheetUrl: (m['sheet_url'] ?? '').toString(),
      sheetId: (m['sheet_id'] ?? '').toString(),
      kind:
          (() {
            final k = (m['kind'] ?? '').toString().trim();
            return k.isEmpty ? null : k;
          })(),
      updatedAt: _parseDt(m['updated_at']),
    );
  }

  /// UI-friendly label when Drive name is "grid" or empty
  String get displayName {
    final raw = (name).trim().toLowerCase();
    if (raw.isEmpty || raw == 'grid') {
      final k = (kind ?? '').toLowerCase();
      if (k.contains('sofp')) return 'Statement of Financial Position';
      if (k.contains('sopl') || k.contains('p&l') || k.contains('pl')) {
        return 'Profit & Loss';
      }
      if (k.contains('ledger') || k.contains('journal')) return 'Ledger';
      return 'Sheet';
    }
    return name;
  }
}

class Chat2Response {
  final String assistantMessage;
  final List<String> postedActions;
  final List<String> warnings;
  final List<int> createdStatementIds;
  final List<int> appendedJournalIds;
  final String? ephemeralMessage;
  final List<BookRef> openBooks;

  Chat2Response({
    required this.assistantMessage,
    required this.postedActions,
    required this.warnings,
    required this.createdStatementIds,
    required this.appendedJournalIds,
    required this.ephemeralMessage,
    required this.openBooks,
  });

  factory Chat2Response.fromJson(Map<String, dynamic> m) {
    List<T> _list<T>(dynamic v, T Function(dynamic) map) {
      if (v is List) return v.map(map).toList();
      return <T>[];
    }

    final openBooks = _list<BookRef>(m['open_books'], (e) {
      return BookRef.fromJson(Map<String, dynamic>.from(e as Map));
    });

    return Chat2Response(
      assistantMessage:
          (m['assistant_message'] ?? m['message'] ?? 'Done.').toString(),
      postedActions: _list<String>(
        m['posted_actions'],
        (e) => e?.toString() ?? '',
      ),
      warnings: _list<String>(m['warnings'], (e) => e?.toString() ?? ''),
      createdStatementIds: _list<int>(
        m['created_statement_ids'],
        (e) => e as int? ?? 0,
      ),
      appendedJournalIds: _list<int>(
        m['appended_journal_ids'],
        (e) => e as int? ?? 0,
      ),
      ephemeralMessage: (m['ephemeral_message'] ?? m['ephemeral'])?.toString(),
      openBooks: openBooks,
    );
  }
}

/// Streaming event for WS/SSE
class ChatStreamEvent {
  final String? delta; // incremental text
  final Chat2Response? finalResponse; // final payload
  final bool done; // stream done

  ChatStreamEvent.delta(this.delta) : finalResponse = null, done = false;
  ChatStreamEvent.finalized(this.finalResponse) : delta = null, done = true;
  ChatStreamEvent.done() : delta = null, finalResponse = null, done = true;
}

class ChatService {
  ChatService({String? apiBase})
    : _apiBase = (apiBase == null || apiBase.isEmpty) ? _API_BASE : apiBase;

  final String _apiBase;

  // Endpoints
  static const _chat2 = '/chat2';
  static const _chat2Sse = '/chat2/stream';
  static const _chat2Ws = '/chat2/ws';
  static const _messagesPath = '/messages';
  static const _booksPath = '/books';

  // ---------------- Auth helpers ----------------
  Future<String?> _freshIdToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  Future<Map<String, String>> _authHeaders({Map<String, String>? base}) async {
    final tok = await _freshIdToken();
    final h = <String, String>{};
    if (base != null) h.addAll(base);
    h['Accept'] = 'application/json';
    if (tok != null && tok.isNotEmpty) {
      h['Authorization'] = 'Bearer $tok';
    }
    return h;
  }

  Future<Map<String, String>> _authHeadersSse() async {
    final tok = await _freshIdToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (tok != null && tok.isNotEmpty) 'Authorization': 'Bearer $tok',
    };
  }

  // ---------------- Conversation id ----------------
  Future<String> ensureActiveConversation() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('conversation_id');
    id ??= 'default';
    await prefs.setString('conversation_id', id);
    return id;
  }

  // ---------------- Chat (non-streaming) ----------------
  Future<Chat2Response> chat2(String input) async {
    final convId = await ensureActiveConversation();
    final uri = Uri.parse('$_apiBase$_chat2');
    final res = await http.post(
      uri,
      headers: await _authHeaders(
        base: const {'Content-Type': 'application/json'},
      ),
      body: jsonEncode({'conversation_id': convId, 'message': input}),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Chat2Response.fromJson(_safeJson(res.body));
    }

    if (res.statusCode == 401) {
      return Chat2Response(
        assistantMessage: 'You are not signed in. Please login again.',
        postedActions: const [],
        warnings: const [],
        createdStatementIds: const [],
        appendedJournalIds: const [],
        ephemeralMessage: null,
        openBooks: const [],
      );
    }
    if (res.statusCode == 400) {
      final m = _safeJson(res.body);
      return Chat2Response(
        assistantMessage:
            (m['error'] ?? m['message'] ?? 'I need a bit more info.')
                .toString(),
        postedActions: const [],
        warnings: const [],
        createdStatementIds: const [],
        appendedJournalIds: const [],
        ephemeralMessage: null,
        openBooks: const [],
      );
    }
    return Chat2Response(
      assistantMessage: 'Backend error ${res.statusCode}',
      postedActions: const [],
      warnings: const [],
      createdStatementIds: const [],
      appendedJournalIds: const [],
      ephemeralMessage: null,
      openBooks: const [],
    );
  }

  // ---------------- Chat (WebSocket preferred) ----------------
  /// High-level convenience: tries WS → SSE → one-shot HTTP
  Stream<ChatStreamEvent> streamChat(String input) async* {
    // 1) Try WebSocket
    try {
      yield* _streamChatWebSocket(input);
      return;
    } catch (_) {
      // ignore, fallback to SSE
    }
    // 2) Try SSE
    try {
      yield* _streamChatSse(input);
      return;
    } catch (_) {
      // ignore, fallback to one-shot
    }
    // 3) One-shot
    final once = await chat2(input);
    yield ChatStreamEvent.finalized(once);
  }

  Uri _toWsUri(String path, Map<String, String> query) {
    final base = Uri.parse(_apiBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final full = base.replace(
      scheme: scheme,
      path: path,
      queryParameters: query,
    );
    return full;
  }

  Stream<ChatStreamEvent> _streamChatWebSocket(String input) async* {
    final convId = await ensureActiveConversation();
    final tok = await _freshIdToken();

    // On web, you can't send custom headers — so pass token in query params.
    final wsUri = _toWsUri(_chat2Ws, {
      'conversation_id': convId,
      if (tok != null && tok.isNotEmpty) 'token': tok,
      'stream': 'true',
    });

    final channel = WebSocketChannel.connect(wsUri);

    // Send initial payload too (some servers rely on message body)
    channel.sink.add(
      jsonEncode({
        'conversation_id': convId,
        'message': input,
        'stream': true,
        if (tok != null && tok.isNotEmpty) 'token': tok,
      }),
    );

    try {
      await for (final msg in channel.stream) {
        if (msg == null) continue;
        Map<String, dynamic>? j;
        try {
          j = jsonDecode(msg as String) as Map<String, dynamic>;
        } catch (_) {
          // treat as plain delta
          if (msg is String && msg.isNotEmpty) {
            yield ChatStreamEvent.delta(msg);
          }
          continue;
        }

        final ev = (j['event'] ?? j['type'] ?? '').toString().toLowerCase();
        if (ev == 'delta') {
          final d = j['delta']?.toString() ?? '';
          if (d.isNotEmpty) yield ChatStreamEvent.delta(d);
          continue;
        }
        if (ev == 'final' ||
            j.containsKey('assistant_message') ||
            j.containsKey('open_books')) {
          yield ChatStreamEvent.finalized(Chat2Response.fromJson(j));
          continue;
        }
        if (ev == 'done') {
          yield ChatStreamEvent.done();
          break;
        }

        // Unknown -> try delta
        final d = j['delta']?.toString();
        if (d != null && d.isNotEmpty) {
          yield ChatStreamEvent.delta(d);
        }
      }
    } finally {
      await channel.sink.close();
    }
  }

  // ---------------- Chat (SSE fallback) ----------------
  Stream<ChatStreamEvent> _streamChatSse(String input) async* {
    final convId = await ensureActiveConversation();
    final uri = Uri.parse('$_apiBase$_chat2Sse');

    final client = http.Client();
    late http.StreamedResponse streamed;
    try {
      final req = http.Request('POST', uri);
      req.headers.addAll(await _authHeadersSse());
      req.body = jsonEncode({
        'conversation_id': convId,
        'message': input,
        'stream': true,
      });

      streamed = await client.send(req);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final fallback = await chat2(input);
        yield ChatStreamEvent.finalized(fallback);
        return;
      }

      final utf8Stream = streamed.stream.transform(utf8.decoder);
      final lines = utf8Stream.transform(const LineSplitter());

      String? eventName;
      final dataBuf = StringBuffer();

      List<ChatStreamEvent> _buildEvents(String? evName, String data) {
        final List<ChatStreamEvent> out = [];
        final ev = (evName ?? 'message').trim();
        if (data.isEmpty) return out;

        Map<String, dynamic>? jsonData;
        try {
          jsonData = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          jsonData = null;
        }

        if (ev == 'delta') {
          final text =
              jsonData == null ? data : (jsonData['delta']?.toString() ?? '');
          if (text.isNotEmpty) out.add(ChatStreamEvent.delta(text));
          return out;
        }
        if (ev == 'final') {
          if (jsonData != null) {
            out.add(
              ChatStreamEvent.finalized(Chat2Response.fromJson(jsonData)),
            );
          } else {
            out.add(
              ChatStreamEvent.finalized(
                Chat2Response(
                  assistantMessage: data,
                  postedActions: const [],
                  warnings: const [],
                  createdStatementIds: const [],
                  appendedJournalIds: const [],
                  ephemeralMessage: null,
                  openBooks: const [],
                ),
              ),
            );
          }
          return out;
        }
        if (ev == 'done') {
          out.add(ChatStreamEvent.done());
          return out;
        }

        // Heuristics if event name not provided
        if (jsonData != null) {
          if (jsonData.containsKey('assistant_message') ||
              jsonData.containsKey('open_books')) {
            out.add(
              ChatStreamEvent.finalized(Chat2Response.fromJson(jsonData)),
            );
          } else {
            final d = jsonData['delta']?.toString();
            if (d != null && d.isNotEmpty) out.add(ChatStreamEvent.delta(d));
          }
        } else if (data.isNotEmpty) {
          out.add(ChatStreamEvent.delta(data));
        }
        return out;
      }

      List<ChatStreamEvent> _drainBuffer() {
        final data = dataBuf.toString().trim();
        dataBuf.clear();
        final events = _buildEvents(eventName, data);
        eventName = null;
        return events;
      }

      await for (final line in lines) {
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataBuf.writeln(line.substring(5));
        } else if (line.trim().isEmpty) {
          final evs = _drainBuffer();
          for (final e in evs) {
            yield e; // <— top-level yield (legal)
          }
        }
      }
      // flush tail if any
      final tail = _drainBuffer();
      for (final e in tail) {
        yield e; // <— top-level yield (legal)
      }
    } finally {
      client.close();
    }
  }

  // ---------------- Messages history ----------------
  Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    final uri = Uri.parse(
      '$_apiBase$_messagesPath?conversation_id=$conversationId',
    );
    try {
      final res = await http.get(uri, headers: await _authHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final v = jsonDecode(res.body);
        if (v is List) {
          return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  // ---------------- Books ----------------
  Future<List<BookRef>> listBooks({int limit = 50, bool recent = true}) async {
    final qp = <String, String>{'limit': '$limit'};
    if (recent) qp['recent'] = 'true';
    final uri = Uri.parse('$_apiBase$_booksPath').replace(queryParameters: qp);
    final res = await http.get(uri, headers: await _authHeaders());
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final v = jsonDecode(res.body);
      if (v is List) {
        return v
            .cast<Map>()
            .map((e) => BookRef.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    }
    return const <BookRef>[];
  }

  Future<List<BookRef>> booksToAutoOpen(Chat2Response out) async {
    if (out.openBooks.isNotEmpty) {
      return out.openBooks.where((b) => b.sheetUrl.isNotEmpty).toList();
    }
    final recent = await listBooks(limit: 2, recent: true);
    return recent.where((b) => b.sheetUrl.isNotEmpty).toList();
  }

  // ---------------- Previews ----------------
  Future<Uint8List?> fetchBookThumbnail(
    String sheetId, {
    int width = 640,
  }) async {
    final uri = Uri.parse('$_apiBase$_booksPath/$sheetId/thumbnail?w=$width');
    try {
      final res = await http.get(uri, headers: await _authHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Uint8List.fromList(res.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  Future<List<List<String>>> fetchBookValues(
    String sheetId, {
    String range = 'A1:F12',
  }) async {
    final uri = Uri.parse(
      '$_apiBase$_booksPath/$sheetId/values',
    ).replace(queryParameters: {'rng': range});
    try {
      final res = await http.get(uri, headers: await _authHeaders());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m = jsonDecode(res.body);
        final vals = (m['values'] as List?) ?? const [];
        return vals
            .map<List<String>>(
              (row) => (row as List).map((c) => c?.toString() ?? '').toList(),
            )
            .toList();
      }
    } catch (_) {}
    return const <List<String>>[];
  }

  // ---------------- Helpers ----------------
  Map<String, dynamic> _safeJson(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      return {"_": v};
    } catch (_) {
      return {"_raw": body};
    }
  }
}
