// lib/auth_controller.dart
import 'package:flutter/foundation.dart';
import 'auth_repository.dart';

class AuthController with ChangeNotifier {
  AuthController(this._repo);
  final AuthRepository _repo;

  bool _loading = false;
  String? _error;
  bool _authed = false;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _authed;

  Future<void> init() async {
    final t = await _repo.getToken();
    _authed = t != null && t.isNotEmpty;
    notifyListeners();
  }

  Future<void> register(String email, String password, String? fullName) async {
    _setLoading(true);
    try {
      await _repo.register(
        email: email,
        password: password,
        fullName: fullName,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      await _repo.login(email: email, password: password);
      _authed = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _repo.clearToken();
    _authed = false;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}
