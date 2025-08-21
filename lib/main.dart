// lib/main.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';

// Auth DI
import 'package:taxpal/auth/controller/auth_controller.dart';
import 'package:taxpal/auth/repository/auth_repository.dart';

// UI
import 'package:taxpal/auth/screens/login_screen.dart';
import 'chatbot/screens/chat_screen.dart';

// Google connect helper (used to nudge user on web)
import 'package:taxpal/services/google_connect_service.dart';

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
      ),
      initialRoute: initial,
      getPages: [
        GetPage(name: '/login', page: () => const LoginScreen()),
        GetPage(name: '/', page: () => const MyHomePage()),
        // Optional placeholder in case you enable a Terms/EULA gate later.
        GetPage(
          name: '/terms',
          page:
              () => const Scaffold(
                body: Center(child: Text('Terms of Service (placeholder)')),
              ),
        ),
      ],
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Sidebar layout with avatar. Long-press avatar to sign out.
class _MyHomePageState extends State<MyHomePage> {
  User? _user;
  late final GoogleConnectService _gsvc;

  @override
  void initState() {
    super.initState();
    _gsvc = GoogleConnectService(baseUrl: API_BASE);

    _user = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((u) async {
      if (!mounted) return;
      setState(() => _user = u);

      // On web, after sign-in, gently prompt once to connect Google Drive
      // so the backend can create Sheets on the user's behalf.
      if (kIsWeb && u != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final connected = await _gsvc.status();
          if (!connected && mounted) {
            final sb = SnackBar(
              content: const Text(
                'Connect Google Drive to let Iccountant create Sheets.',
              ),
              action: SnackBarAction(
                label: 'Connect',
                onPressed: () async {
                  await _gsvc.connect(context);
                  final ok = await _gsvc.status();
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Google connected!')),
                    );
                  }
                },
              ),
              duration: const Duration(seconds: 10),
            );
            ScaffoldMessenger.of(context).showSnackBar(sb);
          }
        });
      }
    });
  }

  String _initialsFrom(User? u) {
    if (u == null) return 'U';
    final basis =
        (u.displayName?.trim().isNotEmpty == true)
            ? u.displayName!.trim()
            : (u.email ?? '').trim();
    if (basis.isEmpty) return 'U';
    var text = basis.contains('@') ? basis.split('@').first : basis;
    text = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim();
    if (text.isEmpty) return 'U';
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final s = parts.first.toUpperCase();
      return s.length >= 2 ? s.substring(0, 2) : s;
    }
    final a = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
    final b = parts[1].isNotEmpty ? parts[1][0].toUpperCase() : '';
    final both = (a + b).trim();
    return both.isEmpty ? 'U' : both;
  }

  Widget _avatar() {
    final initials = _initialsFrom(_user);
    final tooltip = [
      if ((_user?.displayName ?? '').isNotEmpty) _user!.displayName!,
      if ((_user?.email ?? '').isNotEmpty) _user!.email!,
    ].join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: tooltip.isEmpty ? 'User' : tooltip,
        preferBelow: false,
        child: GestureDetector(
          onLongPress: () async {
            await FirebaseAuth.instance.signOut();
            // GetX navigation is handled by AuthController on auth changes.
          },
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Slim sidebar
          Container(
            width: 50,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 100),
                IconButton(icon: const Icon(Icons.search), onPressed: () {}),
                const SizedBox(height: 1),
                IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
                const Spacer(),
                _avatar(),
              ],
            ),
          ),
          // Main content area
          const Expanded(child: ChatScreen()),
        ],
      ),
    );
  }
}
