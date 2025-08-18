// lib/auth_repository.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

class AuthRepository {
  final _storage = const FlutterSecureStorage();
  static const _kToken = 'access_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _kToken, value: token);
  }

  Future<String?> getToken() => _storage.read(key: _kToken);

  Future<void> clearToken() => _storage.delete(key: _kToken);

  Future<void> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await http.post(
      Uri.parse('$API_BASE/auth/register'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'full_name': (fullName ?? '').trim().isEmpty ? null : fullName!.trim(),
      }),
    );
    if (res.statusCode == 409) {
      throw Exception('Email already registered');
    }
    if (res.statusCode >= 400) {
      throw Exception('Register failed: ${res.statusCode} ${res.body}');
    }
    // no token on register; user should login
  }

  Future<void> login({required String email, required String password}) async {
    final res = await http.post(
      Uri.parse('$API_BASE/auth/login'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode == 401) {
      throw Exception('Invalid credentials');
    }
    if (res.statusCode >= 400) {
      throw Exception('Login failed: ${res.statusCode} ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = (body['access_token'] ?? '').toString();
    if (token.isEmpty) throw Exception('No token returned');
    await saveToken(token);
  }

  /// Helper used by other services to add Authorization header.
  Future<Map<String, String>> authHeaders({Map<String, String>? base}) async {
    final token = await getToken();
    final h = <String, String>{};
    if (base != null) h.addAll(base);
    h['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }
}
