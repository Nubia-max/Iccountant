// Minimal login screen that works on Web & Mobile.
// Path: lib/features/auth/screens/login_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:taxpal/auth/sign_in_button.dart';
import 'package:taxpal/auth/controller/auth_controller.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final isWide = kIsWeb && MediaQuery.of(context).size.width > 900;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Text(
          'Welcome to TaxPal',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to start chatting with your Iccountant.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        const SignInButton(),
        const SizedBox(height: 12),
        Obx(
          () =>
              auth.isLoading.value
                  ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const SizedBox.shrink(),
        ),
        const SizedBox(height: 40),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 560 : 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: content,
          ),
        ),
      ),
    );
  }
}
