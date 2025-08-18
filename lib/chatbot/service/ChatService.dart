// lib/chatbot/service/ChatService.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:taxpal/auth/auth_repository.dart';

/// Client for your FastAPI backend.
/// - Persists a simple conversation id locally ("default").
/// - Calls /chat2 for dual-output AI flow (natural text + JSON actions).
/// - Lists statements, journals and TB summary for the Iccountant drawer.
class ChatService {
  final AuthRepository _authRepo = AuthRepository();

  ChatService({String? apiBase, String? key})
    : _apiBase =
          (apiBase == null || apiBase.isEmpty)
              ? const String.fromEnvironment(
                'API_BASE',
                defaultValue: 'http://127.0.0.1:8000',
              )
              : apiBase,
      _key = key;

  final String _apiBase;
  final String? _key;

  // ---- Endpoints
  static const _chat2 = '/chat2';
  static const _messagesPath = '/messages';
  static const _journalsPath = '/journals';
  static const _tbSummaryPath = '/trial_balance/summary';
  static const _statementsPath = '/statements';

  // ========== Conversation helpers ==========
  Future<String?> ensureActiveConversation() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('conversation_id');
    id ??= 'default'; // simple single-threaded conversation for now
    await prefs.setString('conversation_id', id);
    return id;
  }

  Future<http.Response> postJson(String path, Map<String, dynamic> body) async {
    final headers = await _authRepo.authHeaders(
      base: {'Content-Type': 'application/json'},
    );
    final uri = Uri.parse('$API_BASE$path');
    return http.post(uri, headers: headers, body: jsonEncode(body));
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    final uri = Uri.parse(
      '$_apiBase$_messagesPath?conversation_id=$conversationId',
    );
    try {
      final res = await http.get(uri, headers: {'Accept': 'application/json'});
      if (res.statusCode == 200) {
        final v = jsonDecode(res.body);
        if (v is List) {
          return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// Main chat entry from UI. Sends the text to /chat2 and returns the
  /// assistant's visible message (natural text). The server persists AI JSON.
  Future<String> handlePrompt(
    List<Map<String, dynamic>> _,
    String input,
  ) async {
    final convId = await ensureActiveConversation() ?? 'default';
    final uri = Uri.parse('$_apiBase$_chat2');

    try {
      final res = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
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

      return 'Backend error ${res.statusCode}';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  // ========== Drawer data ==========
  Future<Map<String, dynamic>> trialBalanceSummary() async {
    final uri = Uri.parse('$_apiBase$_tbSummaryPath');
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode == 200) {
      final v = _safeJson(res.body);
      return v;
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> listJournals({
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$_apiBase$_journalsPath?limit=$limit&offset=$offset',
    );
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
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
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode == 200) {
      final v = jsonDecode(res.body);
      if (v is List) {
        return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return [];
  }

  // ========== Optional Images (stub safe) ==========
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

  // ========== Helpers ==========
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
