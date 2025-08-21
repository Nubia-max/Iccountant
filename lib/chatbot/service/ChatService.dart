// lib/chatbot/service/ChatService.dart
// Dynamic service used by ChatScreen + IccountantDrawer.
// Adds:
//  - BookRef model
//  - Chat2Response.openBooks
//  - listBooks() to fetch dynamic books
//  - booksToAutoOpen() to decide which books to open after /chat2
//
// Expects backend shapes like:
//   GET /books -> [{ name, sheet_url, kind?, updated_at? }, ...]
//   POST /chat2 -> { assistant_message, ephemeral_message?, posted_actions?:[],
//                    open_books?: [{...}], ... }

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String _API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

class BookRef {
  final String name;
  final String sheetUrl; // full Google Sheets editor URL
  final String? kind; // e.g. "journal", "ledger", "trial_balance" OR custom
  final DateTime? updatedAt;

  BookRef({
    required this.name,
    required this.sheetUrl,
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
      kind:
          (m['kind'] ?? '').toString().trim().isEmpty
              ? null
              : (m['kind'] as String),
      updatedAt: _parseDt(m['updated_at']),
    );
  }
}

class Chat2Response {
  final String assistantMessage;
  final List<String> postedActions;
  final List<String> warnings;
  final List<int> createdStatementIds;
  final List<int> appendedJournalIds;
  final String? ephemeralMessage;

  /// New: dynamic books the assistant suggests opening (Google Sheets)
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

class ChatService {
  ChatService({String? apiBase})
    : _apiBase = (apiBase == null || apiBase.isEmpty) ? _API_BASE : apiBase;

  final String _apiBase;

  // Endpoints
  static const _chat2 = '/chat2';
  static const _messagesPath = '/messages';
  static const _booksPath = '/books'; // NEW

  // ---------------- Auth helpers ----------------
  Future<String?> _freshIdToken() async {
    // Force refresh to avoid stale token right after sign up
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

  // ---------------- Conversation id ----------------
  Future<String> ensureActiveConversation() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('conversation_id');
    id ??= 'default';
    await prefs.setString('conversation_id', id);
    return id;
  }

  // ---------------- Chat ----------------
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

    // Shape errors into a consistent response
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

  // ---------------- Dynamic books ----------------
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

  /// Decide which books to open after /chat2:
  /// 1) Prefer explicit `open_books` from chat2
  /// 2) Else, fallback to a couple of recent books
  Future<List<BookRef>> booksToAutoOpen(Chat2Response out) async {
    if (out.openBooks.isNotEmpty) {
      return out.openBooks.where((b) => b.sheetUrl.isNotEmpty).toList();
    }
    // Fallback: open the latest couple of books (if any)
    final recent = await listBooks(limit: 2, recent: true);
    return recent.where((b) => b.sheetUrl.isNotEmpty).toList();
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
