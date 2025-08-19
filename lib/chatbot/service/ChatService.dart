import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ChatService: talks to FastAPI with Firebase auth.
/// - Uses Firebase ID token in Authorization header
/// - Keeps a simple "default" conversation id locally
/// - Exposes helpers for chat, messages, journals, statements, trial balance
class ChatService {
  ChatService({String? apiBase, String? openAiKey})
    : _apiBase =
          (apiBase == null || apiBase.isEmpty)
              ? const String.fromEnvironment(
                'API_BASE',
                defaultValue: 'http://127.0.0.1:8000',
              )
              : apiBase,
      _key = openAiKey;

  final String _apiBase;
  final String? _key;

  // Endpoints
  static const _chat2 = '/chat2';
  static const _messagesPath = '/messages';
  static const _journalsPath = '/journals';
  static const _tbSummaryPath = '/trial_balance/summary';
  static const _statementsPath = '/statements';

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
  Future<String> handlePrompt(
    List<Map<String, dynamic>> _,
    String input,
  ) async {
    final convId = await ensureActiveConversation();
    final uri = Uri.parse('$_apiBase$_chat2');
    try {
      final res = await http.post(
        uri,
        headers: await _authHeaders(
          base: const {'Content-Type': 'application/json'},
        ),
        body: jsonEncode({'conversation_id': convId, 'message': input}),
      );
      if (res.statusCode == 200) {
        final body = _safeJson(res.body);
        final msg =
            (body['assistant_message'] ?? body['message'] ?? '').toString();
        return msg.isEmpty ? 'Done.' : msg;
      }
      if (res.statusCode == 400) {
        final body = _safeJson(res.body);
        return (body['error'] ?? body['message'] ?? 'I need a bit more info.')
            .toString();
      }
      if (res.statusCode == 401) {
        return 'You are not signed in. Please sign in again.';
      }
      return 'Backend error ${res.statusCode}';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    final uri = Uri.parse(
      '$_apiBase$_messagesPath?conversation_id=$conversationId',
    );
    try {
      final res = await http.get(uri, headers: await _authHeaders());
      if (res.statusCode == 200) {
        final v = jsonDecode(res.body);
        if (v is List) {
          return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  // ---------------- Drawer data ----------------
  /// Returns: { rows: [ {account,debit,credit}... ], totals:{debit,credit} }
  Future<Map<String, dynamic>> trialBalance() async {
    final uri = Uri.parse('$_apiBase$_tbSummaryPath');
    final res = await http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 200) {
      return _safeJson(res.body);
    }
    if (res.statusCode == 401) {
      return {'error': 'unauthorized'};
    }
    return {'error': 'status_${res.statusCode}'};
  }

  Future<List<Map<String, dynamic>>> listJournals({
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$_apiBase$_journalsPath?limit=$limit&offset=$offset',
    );
    final res = await http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 200) {
      final v = jsonDecode(res.body);
      if (v is List) {
        return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listStatements({
    int limit = 50,
    String? name,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    if (name != null && name.isNotEmpty) qp['name'] = name;
    final uri = Uri.parse(
      '$_apiBase$_statementsPath',
    ).replace(queryParameters: qp);
    final res = await http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 200) {
      final v = jsonDecode(res.body);
      if (v is List) {
        return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return [];
  }

  // ---------------- Optional images (safe stub) ----------------
  Future<List<String>> generateImages(String prompt) async {
    if (_key == null || _key!.isEmpty) return <String>[];
    try {
      final res = await http.post(
        Uri.parse('https://api.openai.com/v1/images/generations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_key',
        },
        body: jsonEncode({"model": "dall-e-3", "prompt": prompt, "n": 1}),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = (body['data'] as List?) ?? const [];
        return data.map((e) => (e as Map)['url'] as String).toList();
      }
    } catch (_) {}
    return <String>[];
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
