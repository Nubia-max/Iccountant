// lib/widgets/iccountant_drawer.dart
// Responsive Iccountant drawer (top on mobile, sidebar on wide screens)
// with a profile menu (Profile • Settings • Upgrade plan • Log out).

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/widgets/google_sheet_view.dart'; // mobile bottom-sheet viewer

enum DrawerPlacement { top, side }

class IccountantDrawer extends StatefulWidget {
  const IccountantDrawer({super.key, this.placement = DrawerPlacement.top});

  final DrawerPlacement placement;

  // Global helpers used by ChatScreen
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

  bool _open = true; // open by default so users notice it
  bool _loading = false;
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
      await launchUrl(Uri.parse(sheetUrl), webOnlyWindowName: '_blank');
    } else {
      await showGoogleSheetBottomSheet(
        context,
        title: title,
        sheetUrl: sheetUrl,
      );
    }
  }

  // ----- UI bits -----

  Widget _profileMenuButton() {
    final u = FirebaseAuth.instance.currentUser;
    final initials = _initialsFrom(u);
    final tooltip = [
      if ((u?.displayName ?? '').isNotEmpty) u!.displayName!,
      if ((u?.email ?? '').isNotEmpty) u!.email!,
    ].join('\n');

    // Ensure a Material ancestor for Ink splashes and the popup.
    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<String>(
        tooltip: 'Account',
        offset: const Offset(0, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder:
            (context) => [
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(
                value: 'upgrade',
                child: Text('Upgrade plan'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Log out', style: TextStyle(color: Colors.red)),
              ),
            ],
        onSelected: (v) async {
          switch (v) {
            case 'logout':
              await FirebaseAuth.instance.signOut();
              break;
            // Hook these up to your routes/screens later:
            case 'profile':
            case 'settings':
            case 'upgrade':
            default:
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$v coming soon')));
          }
        },
        child: Tooltip(
          message: tooltip.isEmpty ? 'Account' : tooltip,
          preferBelow: false,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.black,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
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

  Widget _headerBar() {
    final isSide = widget.placement == DrawerPlacement.side;

    // Wrap row in Material so PopupMenu/InkWell always have a Material ancestor.
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.25)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
              tooltip: _open ? 'Collapse' : 'Expand',
              onPressed: () {
                setState(() => _open = !_open);
                if (_open && _books.isEmpty && !_loading) {
                  _loadBooks();
                }
              },
            ),
            const SizedBox(width: 4),
            const Text(
              'Iccountant',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadBooks,
            ),
            const SizedBox(width: 6),
            _profileMenuButton(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSide = widget.placement == DrawerPlacement.side;

    final listArea =
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
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(
                        'Books (Google Sheets)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cross =
                            c.maxWidth >= 900
                                ? 3
                                : c.maxWidth >= 600
                                ? 2
                                : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
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
                        );
                      },
                    ),
                  ],
                ),
              ),
            );

    if (isSide) {
      // Sidebar container
      return Material(
        color: Colors.white,
        child: Column(children: [_headerBar(), Expanded(child: listArea)]),
      );
    }

    // Top drawer container
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _open ? 420 : 60,
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        children: [_headerBar(), if (_open) Expanded(child: listArea)],
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

    // Card itself supplies Material -> ink splashes are safe.
    return Card(
      elevation: 0.6,
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
