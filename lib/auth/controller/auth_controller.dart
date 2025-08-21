// GetX controller for Google/Firebase auth
// Path: lib/features/auth/controller/auth_controller.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repository/auth_repository.dart';

/// Optional: in-app EULA/version gate. If you don't use this, set both to 0.
const String kEulaVersionKey = 'eula_version';
const int kCurrentEulaVersion = 0; // set to >0 if you have a Terms screen

class AuthController extends GetxController {
  static AuthController get to => Get.find<AuthController>();

  AuthController({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  /// True while doing network ops.
  final isLoading = false.obs;

  /// Current Firebase user (null if signed out).
  final Rxn<User> firebaseUser = Rxn<User>();

  @override
  void onInit() {
    super.onInit();

    _authRepository.authStateChanges.listen((user) {
      firebaseUser.value = user;

      // Handle first-load navigation decisions on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (user == null) {
          if (Get.currentRoute != '/login') {
            Get.offAllNamed('/login');
          }
          return;
        }

        // Optional Terms/EULA gate
        try {
          final prefs = await SharedPreferences.getInstance();
          final accepted = prefs.getInt(kEulaVersionKey) ?? 0;
          if (kCurrentEulaVersion > 0 && accepted < kCurrentEulaVersion) {
            if (Get.currentRoute != '/terms') {
              Get.offAllNamed('/terms');
            }
          } else {
            if (Get.currentRoute != '/') {
              Get.offAllNamed('/');
            }
          }
        } catch (_) {
          if (Get.currentRoute != '/') {
            Get.offAllNamed('/');
          }
        }
      });
    });
  }

  Future<void> signInWithGoogle({bool linkToExisting = false}) async {
    isLoading.value = true;
    try {
      if (linkToExisting && FirebaseAuth.instance.currentUser != null) {
        await _authRepository.linkGoogleToCurrentUser();
      } else {
        await _authRepository.signInWithGoogle();
      }
    } catch (e) {
      Get.snackbar(
        'Sign in failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    try {
      await _authRepository.logOut();
    } catch (e) {
      Get.snackbar(
        'Logout failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteAccount() async {
    isLoading.value = true;
    try {
      await _authRepository.deleteAccount();
      Get.offAllNamed('/login');
    } catch (e) {
      // Common: FirebaseAuthException(code: 'requires-recent-login')
      Get.snackbar(
        'Delete account failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Convenience: get a fresh Firebase ID token for backend calls.
  Future<String?> firebaseIdToken() => _authRepository.getFreshIdToken();
}
