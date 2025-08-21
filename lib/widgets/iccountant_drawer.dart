// lib/widgets/iccountant_drawer.dart
// Dynamic, LLM-driven drawer that lists Google Sheets “books” and opens them in a WebView.
//
// Requires ChatService + showGoogleSheetBottomSheet().

import 'package:flutter/material.dart';
import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/widgets/google_sheet_view.dart';

class IccountantDrawer extends StatefulWidget {
  const IccountantDrawer({super.key});

  /// Expose a single global key so ChatScreen can call openFromChat2().
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
      await showGoogleSheetBottomSheet(
        context,
        title: bk.name,
        sheetUrl: bk.sheetUrl,
      );
    }

    await _loadBooks();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // IMPORTANT: do NOT use the globalKey again here.
      // If you want a key for this box, use a ValueKey instead.
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
                                    (context, i) => _BookCard(book: _books[i]),
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
    // Compact placeholder to avoid overflow in short containers
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
  const _BookCard({required this.book});

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
        onTap: () async {
          if (book.sheetUrl.isEmpty) return;
          await showGoogleSheetBottomSheet(
            context,
            title: book.name,
            sheetUrl: book.sheetUrl,
          );
        },
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
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap to edit in Google Sheets',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
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
