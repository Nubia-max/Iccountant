// lib/auth/repository/auth_repository.dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Pass your API base (e.g. http://127.0.0.1:8000) and your
/// Google OAuth **Web** client ID (the one you created in Google Cloud Console).
class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    GoogleSignIn? mobileGoogleSignIn,
    required String apiBase,
    required String serverClientId, // Web OAuth client ID for server exchange
  }) : _auth = auth ?? FirebaseAuth.instance,
       _apiBase = apiBase,
       _serverClientId = serverClientId,
       _mobileGSI =
           kIsWeb
               ? null
               : (mobileGoogleSignIn ??
                   GoogleSignIn(
                     // Use serverClientId to obtain a serverAuthCode we can exchange on the backend.
                     serverClientId: serverClientId,
                     scopes: const [
                       'email',
                       'https://www.googleapis.com/auth/spreadsheets',
                       'https://www.googleapis.com/auth/drive.file',
                     ],
                   ));

  final FirebaseAuth _auth;
  final GoogleSignIn? _mobileGSI; // null on Web
  final String _apiBase;
  final String _serverClientId;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with Google.
  /// - Web: popup/redirect via Firebase.
  /// - Mobile: google_sign_in → Firebase credential + send serverAuthCode to backend.
  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider =
          GoogleAuthProvider()
            ..addScope('email')
            ..addScope('https://www.googleapis.com/auth/spreadsheets')
            ..addScope('https://www.googleapis.com/auth/drive.file')
            ..setCustomParameters({'prompt': 'select_account'});

      try {
        return await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-blocked' ||
            e.code == 'cancelled-popup-request' ||
            e.code == 'popup-closed-by-user') {
          await _auth.signInWithRedirect(provider);
          return await _auth.getRedirectResult();
        }
        rethrow;
      }
    } else {
      final account = await _mobileGSI!.signIn();
      if (account == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Sign-in cancelled by user',
        );
      }

      final tokens = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );
      final userCred = await _auth.signInWithCredential(cred);

      // Exchange server auth code once so backend stores refresh token.
      final code = account.serverAuthCode;
      if (code != null && code.isNotEmpty) {
        await _exchangeServerAuthCodeWithBackend(code);
      } else {
        // Try requesting scopes explicitly, then re-fetch:
        final ok = await _mobileGSI!.requestScopes(<String>[
          'https://www.googleapis.com/auth/spreadsheets',
          'https://www.googleapis.com/auth/drive.file',
        ]);
        if (ok) {
          final again = await _mobileGSI!.signInSilently();
          final code2 = again?.serverAuthCode;
          if (code2 != null && code2.isNotEmpty) {
            await _exchangeServerAuthCodeWithBackend(code2);
          }
        }
      }

      return userCred;
    }
  }

  /// Your AuthController calls this when linkToExisting=true.
  /// Implements Web (popup/redirect) + Mobile linking AND exchanges serverAuthCode on mobile.
  Future<UserCredential> linkGoogleToCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'There is no signed-in user to link.',
      );
    }

    if (kIsWeb) {
      final provider =
          GoogleAuthProvider()
            ..addScope('email')
            ..addScope('https://www.googleapis.com/auth/spreadsheets')
            ..addScope('https://www.googleapis.com/auth/drive.file')
            ..setCustomParameters({'prompt': 'select_account'});
      try {
        return await user.linkWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-blocked' ||
            e.code == 'cancelled-popup-request' ||
            e.code == 'popup-closed-by-user') {
          await user.linkWithRedirect(provider);
          return await _auth.getRedirectResult();
        }
        rethrow;
      }
    } else {
      final account = await _mobileGSI!.signIn();
      if (account == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Link cancelled by user',
        );
      }
      final tokens = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );
      final res = await user.linkWithCredential(cred);

      // As with sign-in, exchange server auth code once.
      final code = account.serverAuthCode;
      if (code != null && code.isNotEmpty) {
        await _exchangeServerAuthCodeWithBackend(code);
      }
      return res;
    }
  }

  /// Send server auth code to backend -> backend exchanges for access+refresh and stores them.
  Future<void> _exchangeServerAuthCodeWithBackend(String code) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final idToken = await u.getIdToken(true);
    final r = await http.post(
      Uri.parse('$_apiBase/oauth/google/exchange'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'code': code}),
    );
    // You can log r.statusCode/r.body if needed; failure here shouldn't break login.
  }

  Future<void> logOut() async {
    try {
      if (!kIsWeb) {
        await _mobileGSI?.signOut().catchError((_) {});
      }
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }
    await user.delete();
  }

  /// Fresh Firebase ID token (for your FastAPI Authorization: Bearer).
  Future<String?> getFreshIdToken() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    return u.getIdToken(true);
  }

  /// (Mobile only) Google OAuth access token for direct Google REST calls (optional).
  Future<String?> googleAccessTokenMobile() async {
    if (kIsWeb) return null;
    final acct =
        await (_mobileGSI?.signInSilently() ?? Future.value(null)) ??
        await _mobileGSI?.signIn();
    if (acct == null) return null;
    final tokens = await acct.authentication;
    return tokens.accessToken;
  }
}
