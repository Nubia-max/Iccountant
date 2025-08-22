// lib/main.dart
// Clean shell: no legacy sidebar. ChatScreen handles the responsive drawer/Sidebar.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

// Auth DI
import 'package:taxpal/auth/controller/auth_controller.dart';
import 'package:taxpal/auth/repository/auth_repository.dart';

// UI
import 'package:taxpal/auth/screens/login_screen.dart';
import 'chatbot/screens/chat_screen.dart';

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

// Your Google OAuth **Web** Client ID (from Google Cloud Console)
const String GOOGLE_WEB_CLIENT_ID =
    '425676843416-4ir8pg0gi3g8b0e1nqdmnlf2h30vbqga.apps.googleusercontent.com';

Future<void> _setupDI() async {
  final repo = AuthRepository(
    apiBase: API_BASE,
    serverClientId: GOOGLE_WEB_CLIENT_ID,
  );
  Get.put<AuthRepository>(repo, permanent: true);
  Get.put<AuthController>(
    AuthController(authRepository: repo),
    permanent: true,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _setupDI();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initial = FirebaseAuth.instance.currentUser == null ? '/login' : '/';

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iccountant',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      initialRoute: initial,
      getPages: [
        GetPage(name: '/login', page: () => const LoginScreen()),
        // ChatScreen internally manages the responsive Iccountant drawer:
        GetPage(name: '/', page: () => const ChatScreen()),
      ],
    );
  }
}
