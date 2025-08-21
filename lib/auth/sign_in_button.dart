// Simple Google Sign-In button that calls AuthController
// Path: lib/core/common/sign_in_button.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:taxpal/auth/controller/auth_controller.dart';

class SignInButton extends StatelessWidget {
  const SignInButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    return SizedBox(
      width: 320,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () => auth.signInWithGoogle(),
        icon: const Icon(Icons.login, size: 20),
        label: const Text(
          'Continue with Google',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
