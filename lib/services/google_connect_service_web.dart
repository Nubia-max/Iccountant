// Helper to connect a user’s Google account (Web).
// Works with FastAPI endpoints: /oauth/google/start, /oauth/google/callback, /oauth/google/status.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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

  /// Opens a centered popup; resolves on postMessage('google_linked') or polling.
  Future<bool> connect(
    BuildContext context, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final idToken = await _requireIdToken();
    final started = await _start(idToken: idToken);

    Future<bool> pollUntilConnected() async {
      final sw = Stopwatch()..start();
      while (sw.elapsed < timeout) {
        await Future.delayed(const Duration(seconds: 2));
        if (await status(idToken: idToken)) return true;
      }
      return false;
    }

    final width = 520;
    final height = 650;
    final left = ((html.window.screen?.width ?? 1200) - width) / 2;
    final top = ((html.window.screen?.height ?? 800) - height) / 2;
    final features =
        'width=$width,height=$height,top=$top,left=$left,menubar=no,toolbar=no,location=no,status=no';

    final popup = html.window.open(started.authUrl, 'google_oauth', features);

    final completer = Completer<bool>();
    late StreamSubscription<html.MessageEvent> sub;

    sub = html.window.onMessage.listen((event) async {
      if (event.data == 'google_linked') {
        try {
          final ok = await status(idToken: idToken);
          if (!completer.isCompleted) completer.complete(ok);
        } catch (_) {
          if (!completer.isCompleted) completer.complete(false);
        } finally {
          await sub.cancel();
          popup?.close();
        }
      }
    });

    // Fallback: polling
    unawaited(() async {
      final ok = await pollUntilConnected();
      if (!completer.isCompleted) {
        completer.complete(ok);
        await sub.cancel();
        popup?.close();
      }
    }());

    return await completer.future;
  }
}
