import 'package:firebase_auth/firebase_auth.dart';

/// Base URL for your API if you need to call it from here (not required for pure auth).
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Firebase-backed auth repository.
/// - Handles register/login/logout via Firebase Auth
/// - Exposes ID token for backend Authorization header
class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns current Firebase ID token (fresh), or null if signed out.
  Future<String?> getToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await user.getIdToken(true);
  }

  /// Not needed with Firebase (session is persisted by SDK), but we keep method for compatibility.
  Future<void> saveToken(String token) async {
    // no-op: Firebase handles persistence.
  }

  /// Clears session (signs out).
  Future<void> clearToken() async {
    await _auth.signOut();
  }

  /// Create account with email/password and optional full name.
  Future<void> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (fullName != null && fullName.trim().isNotEmpty) {
      await cred.user?.updateDisplayName(fullName.trim());
    }
  }

  /// Sign in with email/password.
  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Useful to observe auth state in widgets if needed.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Headers for calling your backend (includes Firebase ID token if available).
  Future<Map<String, String>> authHeaders({Map<String, String>? base}) async {
    final token = await getToken();
    final h = <String, String>{
      'Accept': 'application/json',
      if (base != null) ...base,
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    // (Optional) During transition you can also send Firebase UID explicitly:
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      h['X-User-Id'] =
          uid; // your FastAPI can read this until JWT verification is enabled
    }
    return h;
  }
}
