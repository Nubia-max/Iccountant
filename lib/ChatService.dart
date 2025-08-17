// lib/ChatService.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// ChatService orchestrates:
/// 1) Transaction-first flow via your backend (/record_text_transaction)
/// 2) Conversational fallback via /chat (or direct OpenAI if you want)
/// 3) Optional local “books” logging (client-side)
class ChatService {
  final String? key; // Optional: only needed for direct OpenAI fallback
  ChatService(this.key);

  /// >>> UPDATE THIS to your current Cloudflare Tunnel URL <<<
  static const String _apiBase =
      'https://runtime-throws-assuming-distinct.trycloudflare.com';

  // Backend endpoints
  static const String _recordTextTxnPath = '/record_text_transaction';
  static const String _chatPath = '/chat';

  // =========================
  // PUBLIC ENTRY
  // =========================
  /// The one method your UI should call.
  /// - Always try to record via backend first.
  /// - Only if backend says "not a txn" → fall back to chat.
  Future<String> handlePrompt(
    List<Map<String, dynamic>> chatHistory,
    String input,
  ) async {
    // 1) Try backend transaction-first flow
    final recordRes = await _recordTextTransaction(input);

    // 1a) Success: recorded
    if (recordRes.kind == _BackendKind.recorded) {
      // also log locally (optional)
      if (recordRes.amount != null && recordRes.description != null) {
        await _recordTransactionLocal(
          recordRes.description!,
          recordRes.amount!,
        );
      }
      // keep it short for UX
      return recordRes.message ?? "✅ Recorded successfully.";
    }

    // 1b) Needs clarification (rare now since date defaults to today)
    if (recordRes.kind == _BackendKind.clarify) {
      return recordRes.message ?? "I need a bit more info to record this.";
    }

    // 1c) Not a transaction → conversational fallback
    chatHistory.add({"role": "user", "content": input});
    final reply = await _askChat(chatHistory);
    chatHistory.add({"role": "assistant", "content": reply});
    return reply;
  }

  // =========================
  // BACKEND CALLS
  // =========================

  /// Try to parse/record a transaction from free text.
  /// Expects your Flask app:
  ///   POST /record_text_transaction  { "text": "capital 5000" }
  ///
  /// Backend conventions (from app.py we wrote):
  /// - 200: { "message":"Recorded", "entry_id":..., "date":..., "debit":..., "credit":..., "amount":... }
  /// - 422/204: not a transaction (fallback to chat)
  /// - 400: some validation issue (we return clarify)
  Future<_RecordResult> _recordTextTransaction(String text) async {
    final uri = Uri.parse('$_apiBase$_recordTextTxnPath');

    http.Response res;
    try {
      res = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({"text": text}),
      );
    } catch (e) {
      // Network error → treat as not-a-transaction and let UI fallback to chat
      return _RecordResult.notTxn("Network error reaching backend: $e");
    }

    // Success: recorded
    if (res.statusCode == 200) {
      final body = _safeJson(res.body);
      final msg = body['message']?.toString() ?? "Recorded";
      final amount = _toDouble(body['amount']);
      // app.py doesn't return 'description'—that’s fine
      return _RecordResult.recorded(
        msg,
        amount: amount,
        description: body['description']?.toString(),
      );
    }

    // Needs clarification (should be rare now)
    if (res.statusCode == 400) {
      final body = _safeJson(res.body);
      final msg = (body['message'] ?? 'I need a bit more info.').toString();
      return _RecordResult.clarify(msg);
    }

    // Not a transaction → fallback
    if (res.statusCode == 204 ||
        res.statusCode == 422 ||
        res.statusCode == 404) {
      return _RecordResult.notTxn("Not a transaction.");
    }

    // Unexpected server error
    return _RecordResult.notTxn("Backend error ${res.statusCode}: ${res.body}");
  }

  /// Ask via backend /chat proxy first, then fallback to direct OpenAI if needed.
  Future<String> _askChat(List<Map<String, dynamic>> chatHistory) async {
    // 1) Try your /chat proxy
    try {
      final viaBackend = await _askViaBackend(chatHistory);
      if (viaBackend != null && viaBackend.isNotEmpty) return viaBackend;
    } catch (_) {
      /* ignore and fallback */
    }

    // 2) Fallback to direct OpenAI (only if key is available)
    if (key == null || key!.isEmpty) {
      return "I’m here. (No model key configured for general chat right now.)";
    }
    return _askOpenAIDirect(chatHistory);
  }

  Future<String?> _askViaBackend(List<Map<String, dynamic>> chatHistory) async {
    final uri = Uri.parse('$_apiBase$_chatPath');
    final res = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({"messages": chatHistory}),
    );

    if (res.statusCode == 200) {
      final body = _safeJson(res.body);
      final content = body['choices']?[0]?['message']?['content'];
      if (content is String) return content;
      return content?.toString();
    }
    return null;
  }

  // ============= OPTIONAL: Direct OpenAI fallback ===========
  Future<String> _askOpenAIDirect(
    List<Map<String, dynamic>> chatHistory,
  ) async {
    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({"model": "gpt-4o-mini", "messages": chatHistory}),
    );

    if (res.statusCode == 200) {
      final jsonData = _safeJson(res.body);
      final content = jsonData['choices']?[0]?['message']?['content'];
      if (content is String) return content;
      return "There is an error! (invalid response shape)";
    } else {
      return "There is an error!";
    }
  }

  // ============= OPENAI (Images) – optional ===========
  Future<List<String>> generateImages(String prompt) async {
    if (key == null || key!.isEmpty) {
      return ["There is an error! (missing API key)"];
    }

    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/images/generations'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({"model": "dall-e-3", "prompt": prompt, "n": 1}),
    );

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List data = (body['data'] as List?) ?? const [];
      return data.map((e) => (e as Map)['url'] as String).toList();
    } else {
      return ["There is an error! (${res.statusCode})"];
    }
  }

  // =========================
  // Optional: Local “Books”
  // =========================
  Future<void> _recordTransactionLocal(
    String description,
    double amount,
  ) async {
    final txn = LocalTransaction(
      description: description,
      amount: amount,
      date: DateTime.now(),
    );

    subsidiaryBook.transactions.add(txn);
    principalBook.transactions.add(txn);

    await _saveTransaction(principalBook, txn);
    await _saveTransaction(subsidiaryBook, txn);
  }

  Future<void> _saveTransaction(LocalBook book, LocalTransaction txn) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = 'book:${book.name}';
    final saved = prefs.getStringList(storageKey) ?? <String>[];
    saved.add(jsonEncode(txn.toJson()));
    await prefs.setStringList(storageKey, saved);
  }

  // =========================
  // Helpers
  // =========================
  Map<String, dynamic> _safeJson(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      return {"_": v};
    } catch (_) {
      return {"_raw": body};
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', ''));
    return null;
  }
}

/// Simple result envelope for /record_text_transaction
enum _BackendKind { recorded, clarify, notTxn }

class _RecordResult {
  final _BackendKind kind;
  final String? message;
  final double? amount;
  final String? description;

  _RecordResult._(this.kind, {this.message, this.amount, this.description});

  factory _RecordResult.recorded(
    String? msg, {
    double? amount,
    String? description,
  }) => _RecordResult._(
    _BackendKind.recorded,
    message: msg,
    amount: amount,
    description: description,
  );

  factory _RecordResult.clarify(String msg) =>
      _RecordResult._(_BackendKind.clarify, message: msg);

  factory _RecordResult.notTxn(String msg) =>
      _RecordResult._(_BackendKind.notTxn, message: msg);
}

// ===== Client-side “books” models (unchanged) =====
class LocalBook {
  String name;
  List<LocalTransaction> transactions;
  LocalBook({required this.name, required this.transactions});
}

class LocalTransaction {
  String description;
  double amount;
  DateTime date;

  LocalTransaction({
    required this.description,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'description': description,
    'amount': amount,
    'date': date.toIso8601String(),
  };

  factory LocalTransaction.fromJson(Map<String, dynamic> json) =>
      LocalTransaction(
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
      );
}

final principalBook = LocalBook(name: 'Principal Book', transactions: []);
final subsidiaryBook = LocalBook(name: 'Subsidiary Book', transactions: []);
