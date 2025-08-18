import 'package:flutter/material.dart';
import 'auth_repository.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoggedIn; // parent handles navigation to Home
  const LoginScreen({super.key, this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repo = AuthRepository();
  late final AuthController _auth;

  final _emailCon = TextEditingController();
  final _pwCon = TextEditingController();
  final _nameCon = TextEditingController();

  bool _isLogin = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _auth = AuthController(_repo)..init();
    // Rebuild UI when controller changes (loading/error state)
    _auth.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCon.dispose();
    _pwCon.dispose();
    _nameCon.dispose();
    _auth.removeListener(() {}); // safe no-op
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCon.text.trim();
    final pw = _pwCon.text;
    final fullName = _nameCon.text.trim().isEmpty ? null : _nameCon.text.trim();

    if (_isLogin) {
      await _auth.login(email, pw);
    } else {
      await _auth.register(email, pw, fullName);
      if ((_auth.error ?? '').isEmpty) {
        await _auth.login(email, pw);
      }
    }

    if (_auth.isAuthenticated) {
      // IMPORTANT: let the parent (main.dart) navigate to /home.
      widget.onLoggedIn?.call();
      return; // <- do not Navigator.pop or push again here
    }

    if ((_auth.error ?? '').isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_auth.error!.replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLogin ? 'Sign in' : 'Create account';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isLogin)
                  TextField(
                    controller: _nameCon,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                TextField(
                  controller: _emailCon,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwCon,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _auth.isLoading ? null : _submit,
                    child: Text(_auth.isLoading ? 'Please wait…' : title),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign up"
                        : "Already have an account? Sign in",
                  ),
                ),
                const SizedBox(height: 8),
                if ((_auth.error ?? '').isNotEmpty)
                  Text(
                    _auth.error!.replaceFirst('Exception: ', ''),
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
