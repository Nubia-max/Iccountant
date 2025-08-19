// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'auth/login_screen.dart';
import 'chatbot/screens/chat_screen.dart';

/// Same env var used by services.
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final initial =
        FirebaseAuth.instance.currentUser == null ? '/login' : '/home';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iccountant',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: initial,
      routes: {
        '/login':
            (ctx) => LoginScreen(
              onLoggedIn: () => Navigator.pushReplacementNamed(ctx, '/home'),
            ),
        '/home': (ctx) => const MyHomePage(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Your original layout, with a Firebase-powered avatar at the bottom.
class _MyHomePageState extends State<MyHomePage> {
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      setState(() => _user = u);
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
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/login');
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
