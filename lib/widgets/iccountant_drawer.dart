// lib/widgets/iccountant_drawer.dart
import 'package:flutter/material.dart';
import 'package:taxpal/chatbot/service/ChatService.dart';

/// Drawer content that shows accounting data:
/// - Trial Balance quick view
/// - Saved Statements (any type)
/// - Recent Journals
///
/// Vertical sections; each section scrolls horizontally.
/// Tapping a card opens a bottom sheet with more details.
class IccountantDrawer extends StatefulWidget {
  final ChatService chatService;
  const IccountantDrawer({super.key, required this.chatService});

  @override
  State<IccountantDrawer> createState() => _IccountantDrawerState();
}

class _IccountantDrawerState extends State<IccountantDrawer> {
  bool _loading = true;
  List<Map<String, dynamic>> _statements = [];
  List<Map<String, dynamic>> _journals = [];
  Map<String, dynamic> _tb = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await widget.chatService.listStatements(limit: 50);
      final jr = await widget.chatService.listJournals(limit: 20);
      final tb = await widget.chatService.trialBalanceSummary();
      setState(() {
        _statements = st;
        _journals = jr;
        _tb = tb;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'Trial Balance',
            child: SizedBox(
              height: 160,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _TileCard(
                    title: 'Totals',
                    subtitle:
                        'DR: ${_num(_tb['totals']?['debit'])} • CR: ${_num(_tb['totals']?['credit'])}',
                    onTap: () => _showTrialBalanceSheet(context),
                  ),
                  const SizedBox(width: 12),
                  // Show top few accounts as small cards (if available)
                  ..._topTbRows()
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _TileCard(
                            title: (r['account'] ?? 'Account').toString(),
                            subtitle:
                                'DR ${_num(r['debit'])} • CR ${_num(r['credit'])}',
                            onTap: () => _showTrialBalanceSheet(context),
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ),

          _Section(
            title: 'Statements',
            child: SizedBox(
              height: 170,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _statements.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final s = _statements[i];
                  final title = (s['name'] ?? 'Statement').toString();
                  final perStart = (s['period_start'] ?? '').toString();
                  final perEnd = (s['period_end'] ?? '').toString();
                  final subtitle =
                      (perStart.isEmpty && perEnd.isEmpty)
                          ? 'Saved'
                          : '$perStart → $perEnd';
                  return _TileCard(
                    title: title,
                    subtitle: subtitle,
                    onTap: () => _showStatementSheet(context, s),
                  );
                },
              ),
            ),
          ),

          _Section(
            title: 'Recent Journals',
            child: SizedBox(
              height: 170,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _journals.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final j = _journals[i];
                  final date = (j['date'] ?? '').toString();
                  final narr = (j['narration'] ?? '').toString();
                  final lines = (j['lines'] as List?) ?? const [];
                  final firstLine =
                      lines.isNotEmpty
                          ? '${lines.first['account']}  (DR ${_num(lines.first['debit'])}, CR ${_num(lines.first['credit'])})'
                          : 'Tap to view lines';
                  return _TileCard(
                    title: date.isEmpty ? 'Journal' : date,
                    subtitle: (narr.isNotEmpty ? '$narr • ' : '') + firstLine,
                    onTap: () => _showJournalSheet(context, j),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helpers
  Iterable<Map<String, dynamic>> _topTbRows() {
    final rows = (_tb['rows'] as List?) ?? const [];
    return rows.take(6).cast<Map<String, dynamic>>();
  }

  String _num(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toStringAsFixed(2);
    final p = double.tryParse(v.toString());
    return p == null ? v.toString() : p.toStringAsFixed(2);
  }

  void _showTrialBalanceSheet(BuildContext context) {
    final rows = (_tb['rows'] as List?)?.cast<Map>() ?? const [];
    final totals = (_tb['totals'] as Map?) ?? const {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder:
                (_, controller) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Trial Balance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          controller: controller,
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i].cast<String, dynamic>();
                            return ListTile(
                              dense: true,
                              title: Text(
                                r['account']?.toString() ?? 'Account',
                              ),
                              trailing: Text(
                                'DR ${_num(r['debit'])}  •  CR ${_num(r['credit'])}',
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Totals —  DR ${_num(totals['debit'])}  •  CR ${_num(totals['credit'])}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showStatementSheet(BuildContext context, Map<String, dynamic> s) {
    final title = (s['name'] ?? 'Statement').toString();
    final perStart = (s['period_start'] ?? '').toString();
    final perEnd = (s['period_end'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    perStart.isEmpty && perEnd.isEmpty
                        ? 'Saved statement'
                        : '$perStart → $perEnd',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Tip: Ask the assistant to export this statement to Excel or PDF (it will return download links in chat).",
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  void _showJournalSheet(BuildContext context, Map<String, dynamic> j) {
    final date = (j['date'] ?? '').toString();
    final narr = (j['narration'] ?? '').toString();
    final lines = (j['lines'] as List?)?.cast<Map>() ?? const [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            builder:
                (_, controller) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        date.isEmpty ? 'Journal' : date,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (narr.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(narr),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: controller,
                          itemCount: lines.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final l = lines[i].cast<String, dynamic>();
                            return ListTile(
                              dense: true,
                              title: Text(
                                l['account']?.toString() ?? 'Account',
                              ),
                              trailing: Text(
                                'DR ${_num(l['debit'])}  •  CR ${_num(l['credit'])}',
                              ),
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
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _TileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _TileCard({
    required this.title,
    required this.subtitle,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: InkWell(
        onTap: onTap,
        child: Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.arrow_forward_ios, size: 14),
                    SizedBox(width: 4),
                    Text('Open', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
