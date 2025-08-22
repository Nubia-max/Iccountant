// lib/widgets/google_sheet_view.dart
// Mobile: show a bottom sheet with an in-app WebView
// Web:    open the Google Sheet in a new tab (no WebView)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> showGoogleSheetBottomSheet(
  BuildContext context, {
  required String title,
  required String sheetUrl,
}) async {
  if (sheetUrl.isEmpty) return;

  // --- WEB: open in a new tab (embedding is often blocked by Google Docs) ---
  if (kIsWeb) {
    await launchUrl(Uri.parse(sheetUrl), webOnlyWindowName: '_blank');
    return;
  }

  // --- MOBILE/DESKTOP: in-app WebView bottom sheet ---
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) {
      final height = MediaQuery.of(context).size.height * 0.88;
      return SizedBox(
        height: height,
        child: _GoogleSheetWebView(title: title, sheetUrl: sheetUrl),
      );
    },
  );
}

class _GoogleSheetWebView extends StatefulWidget {
  final String title;
  final String sheetUrl;
  const _GoogleSheetWebView({required this.title, required this.sheetUrl});

  @override
  State<_GoogleSheetWebView> createState() => _GoogleSheetWebViewState();
}

class _GoogleSheetWebViewState extends State<_GoogleSheetWebView> {
  late final WebViewController _ctrl;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _ctrl =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (v) {
                setState(() => _progress = v / 100.0);
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.sheetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        if (_progress < 1.0)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: Colors.grey.shade200,
          ),
        const SizedBox(height: 4),
        // WebView
        Expanded(child: WebViewWidget(controller: _ctrl)),
      ],
    );
  }
}
