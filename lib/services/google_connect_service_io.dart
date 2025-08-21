// Helper to connect a user’s Google account (IO: mobile/desktop).
// Works with FastAPI endpoints: /oauth/google/start, /oauth/google/status.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleConnectService {
  const GoogleConnectService({required this.baseUrl});
  final String baseUrl;

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in to Firebase.');
    }
    final tok = await user.getIdToken(true); // String?
    if (tok == null || tok.isEmpty) {
      throw StateError('Failed to retrieve Firebase ID token.');
    }
    return tok; // non-null after the guard
  }

  Future<bool> status({String? idToken}) async {
    idToken ??= await _requireIdToken();
    final r = await http.get(
      Uri.parse('$baseUrl/oauth/google/status'),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (r.statusCode != 200) return false;
    final j = json.decode(r.body) as Map<String, dynamic>;
    return j['connected'] == true;
  }

  Future<({String authUrl, String state})> _start({
    String? returnTo,
    String? idToken,
  }) async {
    idToken ??= await _requireIdToken();
    final uri = Uri.parse('$baseUrl/oauth/google/start').replace(
      queryParameters: {
        if (returnTo != null && returnTo.isNotEmpty) 'return_to': returnTo,
      },
    );
    final r = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (r.statusCode != 200) {
      throw StateError(
        'Failed to start Google OAuth: ${r.statusCode} ${r.body}',
      );
    }
    final j = json.decode(r.body) as Map<String, dynamic>;
    return (authUrl: j['auth_url'] as String, state: j['state'] as String);
  }

  /// Opens system browser for consent; polls /oauth/google/status until connected.
  Future<bool> connect(
    BuildContext context, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final idToken = await _requireIdToken();
    final started = await _start(idToken: idToken);

    final uri = Uri.parse(started.authUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    Future<bool> pollUntilConnected() async {
      final sw = Stopwatch()..start();
      while (sw.elapsed < timeout) {
        await Future.delayed(const Duration(seconds: 2));
        if (await status(idToken: idToken)) return true;
      }
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        bool done = false;
        unawaited(() async {
          final ok = await pollUntilConnected();
          if (!done && ctx.mounted) {
            done = true;
            Navigator.of(ctx).pop(ok);
          }
        }());
        return const AlertDialog(
          title: Text('Connecting Google…'),
          content: Text('Finish the Google screen, then return here.'),
        );
      },
    );

    return result ?? false;
  }
}
