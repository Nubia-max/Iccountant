import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:taxpal/auth/login_screen.dart';
import 'chatbot/screens/chat_screen.dart';

/// Same env var you use elsewhere:
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iccountant',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      // Start at the login route
      initialRoute: '/home',
      routes: {
        '/login':
            (ctx) => LoginScreen(
              // After successful login, go to Home
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
  _MyHomePageState createState() => _MyHomePageState();
}

// ⬇️ Your original UI, with a small addition: avatar at the bottom of the sidebar
class _MyHomePageState extends State<MyHomePage> {
  String? _fullName;
  String? _email;
  bool _loadingUser = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile(); // fetch /auth/me to show initials
  }

  Future<void> _loadUserProfile() async {
    setState(() => _loadingUser = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        setState(() => _loadingUser = false);
        return;
      }

      final res = await http.get(
        Uri.parse('$API_BASE/auth/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _fullName = (m['full_name'] as String?)?.trim();
          _email = (m['email'] as String?)?.trim();
          _loadingUser = false;
        });
      } else {
        setState(() => _loadingUser = false);
      }
    } catch (_) {
      setState(() => _loadingUser = false);
    }
  }

  String _initials() {
    // Prefer full name; fall back to email user-part; ultimately "U"
    String basis =
        (_fullName != null && _fullName!.isNotEmpty)
            ? _fullName!
            : (_email ?? '');
    if (basis.isEmpty) return 'U';

    String text = basis;
    if (basis.contains('@')) {
      text = basis.split('@').first;
    }
    // Normalize to words
    text = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim();
    if (text.isEmpty) return 'U';

    final parts = text.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final s = parts.first.toUpperCase();
      return s.length >= 2 ? s.substring(0, 2) : s;
    } else {
      final a = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
      final b = parts[1].isNotEmpty ? parts[1][0].toUpperCase() : '';
      final both = (a + b).trim();
      return both.isEmpty ? 'U' : both;
    }
  }

  Widget _buildAvatar() {
    final initials = _initials();
    final tooltip =
        (_fullName?.isNotEmpty == true)
            ? '${_fullName!}\n${_email ?? ''}'
            : (_email ?? 'User');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
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
                right: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ), // Thin right border
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start, // icons start at top
              children: [
                const SizedBox(height: 100), // Space at the top of the sidebar
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    // Action for search button
                  },
                ),
                const SizedBox(height: 1), // Space between icons
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    // Navigate to settings screen
                  },
                ),

                // Push avatar to the extreme bottom
                const Spacer(),
                if (_loadingUser)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  _buildAvatar(),
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
