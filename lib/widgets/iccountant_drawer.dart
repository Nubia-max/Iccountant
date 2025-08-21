// lib/widgets/iccountant_drawer.dart
// Dynamic drawer that lists Google Sheets “books” with a live mini preview.
// On web: opens the Sheet in a NEW TAB. On mobile: shows an in-app WebView bottom sheet.

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/widgets/google_sheet_view.dart'; // used on mobile only

class IccountantDrawer extends StatefulWidget {
  const IccountantDrawer({super.key});

  static final GlobalKey<_IccountantDrawerState> globalKey =
      GlobalKey<_IccountantDrawerState>();

  static Future<void> openFromChat2(Chat2Response out) async {
    final st = globalKey.currentState;
    if (st == null) return;
    await st._openBooksForChat2(out);
  }

  static Future<void> refresh() async {
    final st = globalKey.currentState;
    if (st == null) return;
    await st._loadBooks();
  }

  @override
  State<IccountantDrawer> createState() => _IccountantDrawerState();
}

class _IccountantDrawerState extends State<IccountantDrawer> {
  final ChatService _svc = ChatService();

  bool _open = false;
  bool _loading = false; // lazy-load on first expand
  List<BookRef> _books = const [];

  Future<void> _loadBooks() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final items = await _svc.listBooks(limit: 200, recent: true);
      if (!mounted) return;
      setState(() {
        _books = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBooksForChat2(Chat2Response out) async {
    if (!mounted) return;
    if (!_open) setState(() => _open = true);

    List<BookRef> toOpen;
    try {
      toOpen = await _svc.booksToAutoOpen(out);
    } catch (_) {
      toOpen = const [];
    }

    final maxAuto = toOpen.length > 3 ? 3 : toOpen.length;
    for (var i = 0; i < maxAuto; i++) {
      final bk = toOpen[i];
      if (bk.sheetUrl.isEmpty) continue;
      await _openSheet(context, bk.name, bk.sheetUrl);
    }

    await _loadBooks();
  }

  Future<void> _openSheet(
    BuildContext context,
    String title,
    String sheetUrl,
  ) async {
    if (kIsWeb) {
      // Web: open in a NEW TAB (never same tab)
      await launchUrl(Uri.parse(sheetUrl), webOnlyWindowName: '_blank');
    } else {
      // Mobile/Desktop: keep your in-app WebView bottom sheet
      await showGoogleSheetBottomSheet(
        context,
        title: title,
        sheetUrl: sheetUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // key: const ValueKey('iccountant_drawer_box'),
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.25), width: 1),
        ),
      ),
      height: _open ? 420 : 60,
      child: Column(
        children: [
          ListTile(
            onTap: () async {
              setState(() => _open = !_open);
              if (_open && _books.isEmpty && !_loading) {
                await _loadBooks();
              }
            },
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Iccountant', style: TextStyle(fontSize: 18)),
                Icon(
                  _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                ),
              ],
            ),
            trailing: IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadBooks,
            ),
          ),
          if (_open)
            Expanded(
              child:
                  _loading
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : _books.isEmpty
                      ? const _EmptyBooks()
                      : RefreshIndicator(
                        onRefresh: _loadBooks,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'Books (Google Sheets)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 1.45,
                                    ),
                                itemCount: _books.length,
                                itemBuilder:
                                    (context, i) => _BookCard(
                                      book: _books[i],
                                      onOpen:
                                          (bk) => _openSheet(
                                            context,
                                            bk.name,
                                            bk.sheetUrl,
                                          ),
                                      svc: _svc,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBooks extends StatelessWidget {
  const _EmptyBooks();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          'No books yet.\nAsk the assistant to record a transaction\nor create a report to see it here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final BookRef book;
  final ChatService svc;
  final void Function(BookRef) onOpen;

  const _BookCard({
    required this.book,
    required this.svc,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if ((book.kind ?? '').isNotEmpty) subtitleParts.add(book.kind!);
    if (book.updatedAt != null) {
      subtitleParts.add('Updated ${_ago(book.updatedAt!)}');
    }

    return Card(
      elevation: 0.3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpen(book),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new, size: 16),
                ],
              ),
              const SizedBox(height: 6),
              if (subtitleParts.isNotEmpty)
                Text(
                  subtitleParts.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const Divider(height: 12),

              // --- PREVIEW AREA ---
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  future: svc.fetchBookThumbnail(book.sheetId, width: 720),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const _PreviewSkeleton();
                    }
                    if (snap.hasData && snap.data != null) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          snap.data!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      );
                    }
                    // Fallback to a tiny grid if no thumbnail
                    return FutureBuilder<List<List<String>>>(
                      future: svc.fetchBookValues(
                        book.sheetId,
                        range: 'A1:F10',
                      ),
                      builder: (context, vSnap) {
                        if (vSnap.connectionState == ConnectionState.waiting) {
                          return const _PreviewSkeleton();
                        }
                        final rows = vSnap.data ?? const [];
                        if (rows.isEmpty) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Tap to edit in Google Sheets',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          );
                        }
                        return _MiniGrid(values: rows);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _MiniGrid extends StatelessWidget {
  final List<List<String>> values;
  const _MiniGrid({required this.values});

  @override
  Widget build(BuildContext context) {
    final maxCols = values
        .fold<int>(0, (m, r) => r.length > m ? r.length : m)
        .clamp(1, 8);
    final maxRows = values.length.clamp(1, 12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: maxRows,
          itemBuilder: (ctx, r) {
            final row = (r < values.length) ? values[r] : const <String>[];
            return Row(
              children: List.generate(maxCols, (c) {
                final txt = (c < row.length) ? row[c] : '';
                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.black12),
                        bottom: BorderSide(color: Colors.black12),
                      ),
                    ),
                    child: Text(
                      txt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
