// lib/ChatService.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// ChatService for the name-only backend:
///   POST /prompt        -> parse & POST a journal (account titles only)
///   POST /extract_only  -> parse without posting (preview)
///
/// Public API used by your ChatScreen:
///   - handlePrompt(chatHistory, input) -> String (chat reply)
///   - previewExtractOnly(text) -> Map (optional preview)
///   - generateImages(prompt) -> List<String> (optional; needs OpenAI key)
class ChatService {
  final String? key; // Optional OpenAI key for generic chat/image fallback
  ChatService(this.key);

  /// Set this at run/build time if needed:
  /// flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
  static const String _apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const String _promptPath = '/prompt';
  static const String _extractOnlyPath = '/extract_only';

  // =========================
  // MAIN ENTRY
  // =========================
  Future<String> handlePrompt(
    List<Map<String, dynamic>> chatHistory,
    String input,
  ) async {
    final res = await _recordViaPrompt(input);

    if (res.kind == _BackendKind.recorded) {
      // Optional local log
      if (res.amount != null && res.description != null) {
        await _recordTransactionLocal(res.description!, res.amount!);
      }
      return res.message ?? "✅ Recorded.";
    }

    if (res.kind == _BackendKind.clarify) {
      return res.message ?? "I need a bit more info to record this.";
    }

    // Not a transaction → minimal fallback
    if (key == null || key!.isEmpty) {
      return "That doesn’t look like a postable transaction. Try “Sold goods ₦500 to Tunde, unpaid”.";
    }
    chatHistory.add({"role": "user", "content": input});
    final reply = await _askOpenAIDirect(chatHistory);
    chatHistory.add({"role": "assistant", "content": reply});
    return reply;
  }

  // =========================
  // BACKEND CALLS
  // =========================
  Future<_RecordResult> _recordViaPrompt(String text) async {
    final uri = Uri.parse('$_apiBase$_promptPath');

    http.Response res;
    try {
      res = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({"text": text, "mode": "auto", "post": true}),
      );
    } catch (e) {
      return _RecordResult.notTxn("Network error reaching backend: $e");
    }

    // Success
    if (res.statusCode == 200) {
      final body = _safeJson(res.body);
      final status = (body['status'] ?? '').toString();
      final explanation = (body['explanation'] ?? '').toString();
      final plan = body['plan'] as Map<String, dynamic>?;
      final amount = _sumDebits(plan);
      final narration = plan?['narration']?.toString();

      String msg;
      if (status == 'duplicate_skipped') {
        final jid = body['journal_id']?.toString() ?? 'existing';
        final synth =
            explanation.isNotEmpty ? explanation : _drCrSummaryFromPlan(plan);
        msg = "⚠️ Duplicate detected. Already posted as Journal #$jid.\n$synth";
      } else {
        final journal = body['journal'];
        if (journal is Map && journal.containsKey('journal_id')) {
          final jid = journal['journal_id']?.toString() ?? '-';
          final jdate = journal['date']?.toString() ?? '-';
          final totals = journal['totals'] ?? {};
          final dr = _fmtMoney(totals['debit']);
          final cr = _fmtMoney(totals['credit']);
          final expl =
              explanation.isNotEmpty ? explanation : _drCrSummaryFromPlan(plan);
          msg =
              "✅ Recorded • Journal #$jid on $jdate\nTotals — DR: $dr  •  CR: $cr\n$expl";
        } else {
          final expl =
              explanation.isNotEmpty ? explanation : _drCrSummaryFromPlan(plan);
          msg = "🔎 Preview only (not posted).\n$expl";
        }
      }

      return _RecordResult.recorded(
        msg,
        amount: amount,
        description: narration,
      );
    }

    // Clarification / validation errors
    if (res.statusCode == 400 || res.statusCode == 422) {
      final body = _safeJson(res.body);
      final detail =
          (body['detail'] ?? body['message'] ?? 'I need a bit more info.')
              .toString();
      return _RecordResult.clarify(detail);
    }

    // Other errors → surface so you can see them in chat
    return _RecordResult.notTxn("Backend error ${res.statusCode}: ${res.body}");
  }

  /// Optional: preview planner without posting
  Future<Map<String, dynamic>> previewExtractOnly(String text) async {
    final uri = Uri.parse('$_apiBase$_extractOnlyPath');
    final res = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({"text": text, "mode": "auto"}),
    );
    if (res.statusCode >= 400) {
      throw Exception(
        'POST /extract_only failed: ${res.statusCode} ${res.body}',
      );
    }
    return _safeJson(res.body);
  }

  // =========================
  // OPTIONAL: OpenAI fallback for chit-chat
  // =========================
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

  // =========================
  // OPTIONAL: Images (used by ChatScreen._generateImages)
  // =========================
  Future<List<String>> generateImages(String prompt) async {
    if (key == null || key!.isEmpty) {
      return ["There is an error! (missing API key)"];
    }
    // OpenAI Images API (dall-e-3). You can switch to `gpt-image-1` if preferred.
    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/images/generations'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        "model": "dall-e-3",
        "prompt": prompt,
        "n": 1,
        "size": "1024x1024",
      }),
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
  // OPTIONAL: Local “books”
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

  double? _sumDebits(Map<String, dynamic>? plan) {
    try {
      final lines = plan?['lines'] as List?;
      if (lines == null) return null;
      final total = lines.fold<num>(
        0,
        (a, l) => a + ((l as Map)['debit'] ?? 0),
      );
      return (total as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  String _drCrSummaryFromPlan(Map<String, dynamic>? plan) {
    try {
      final lines = (plan?['lines'] as List?)?.cast<Map>() ?? const <Map>[];
      String fmt(n) {
        try {
          final d = (n is num) ? n.toDouble() : double.parse(n.toString());
          return '₦' + d.toStringAsFixed(2);
        } catch (_) {
          return n.toString();
        }
      }

      final dr = <String>[];
      final cr = <String>[];
      for (final l in lines) {
        final title = (l['account_title'] ?? '').toString();
        final d = (l['debit'] ?? 0);
        final c = (l['credit'] ?? 0);
        if ((d is num && d > 0) ||
            (d is String &&
                double.tryParse(d) != null &&
                double.parse(d) > 0)) {
          dr.add('Dr $title ${fmt(d)}');
        }
        if ((c is num && c > 0) ||
            (c is String &&
                double.tryParse(c) != null &&
                double.parse(c) > 0)) {
          cr.add('Cr $title ${fmt(c)}');
        }
      }
      final parts = <String>[];
      parts.addAll(dr);
      parts.addAll(cr);
      return parts.isEmpty ? '' : parts.join(' • ');
    } catch (_) {
      return '';
    }
  }

  String _fmtMoney(dynamic v) {
    try {
      if (v == null) return '₦0.00';
      final n = (v is num) ? v.toDouble() : double.parse(v.toString());
      return '₦' + n.toStringAsFixed(2);
    } catch (_) {
      return v.toString();
    }
  }
}

/// Small result envelope so ChatScreen gets a simple String
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

// =========================
// Local "books" models (unchanged)
// =========================
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
