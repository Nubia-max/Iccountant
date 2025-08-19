import 'package:flutter/material.dart';
import 'package:taxpal/chatbot/service/ChatService.dart';
import 'package:taxpal/books/worksheet_screen.dart';

/// Collapsible drawer that shows mini "worksheet" previews:
/// - Trial Balance (mini table)
/// - Journals (recent summary)
/// - Statements (cards)
class IccountantDrawer extends StatefulWidget {
  const IccountantDrawer({super.key});

  @override
  State<IccountantDrawer> createState() => _IccountantDrawerState();
}

class _IccountantDrawerState extends State<IccountantDrawer> {
  final ChatService _svc = ChatService();

  bool _open = false;
  bool _loading = true;

  // Trial Balance
  List<Map<String, dynamic>> _tbRows = [];
  Map<String, dynamic>? _tbTotals;

  // Journals
  List<Map<String, dynamic>> _journals = [];

  // Statements (metadata list from /statements)
  List<Map<String, dynamic>> _statements = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // --- Trial Balance
      final tbResp = await _svc.trialBalance(); // {rows: [], totals: {}}
      final rows =
          (tbResp['rows'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      final totals = Map<String, dynamic>.from(
        (tbResp['totals'] as Map?) ?? {},
      );

      // --- Journals
      final journals = await _svc.listJournals(limit: 20);

      // --- Statements (metadata)
      final statements = await _svc.listStatements(limit: 200);

      setState(() {
        _tbRows = rows;
        _tbTotals = totals;
        _journals = journals;
        _statements = statements;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
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
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Iccountant',
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
                Icon(
                  _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.black,
                ),
              ],
            ),
            onTap: () => setState(() => _open = !_open),
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
                      : RefreshIndicator(
                        onRefresh: _loadAll,
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
                                  'Accounts & Reports',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              GridView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 1.45,
                                    ),
                                children: [
                                  _tbCard(context),
                                  _journalsCard(context),
                                  ..._statementCards(context),
                                ],
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

  // ---------------- Cards ----------------
  Widget _tbCard(BuildContext context) {
    final preview = _tbRows.take(6).toList();
    final totals = _tbTotals ?? const {};

    return _MiniSheetCard(
      title: 'Trial Balance',
      subtitle:
          'Rows: ${_tbRows.length} • Dr ${_fmtAmt(totals['debit'])} / Cr ${_fmtAmt(totals['credit'])}',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorksheetScreen.tb()),
        );
      },
      child: _buildTbMiniTable(preview),
    );
  }

  Widget _journalsCard(BuildContext context) {
    final preview = _journals.take(3).toList();
    return _MiniSheetCard(
      title: 'Journals',
      subtitle: 'Entries: ${_journals.length}',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorksheetScreen.journals()),
        );
      },
      child: _buildJournalsMini(preview),
    );
  }

  List<Widget> _statementCards(BuildContext context) {
    if (_statements.isEmpty) {
      return [
        _MiniSheetCard(
          title: 'Statements',
          subtitle: 'No statements yet',
          onTap: () {},
          child: const Center(
            child: Text('Ask the AI to prepare a statement.'),
          ),
        ),
      ];
    }
    final items = _statements.take(4).toList();
    return items.map((m) {
      final name = (m['name'] ?? '').toString();
      final ver = (m['version'] ?? 1).toString();
      final ps = (m['period_start'] ?? '').toString();
      final pe = (m['period_end'] ?? '').toString();
      final id = (m['id'] ?? 0) as int;

      return _MiniSheetCard(
        title: name.isEmpty ? 'Statement' : name,
        subtitle: [
          if (ps.isNotEmpty || pe.isNotEmpty) '$ps → $pe',
          'v$ver',
        ].where((s) => s.isNotEmpty).join('  •  '),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorksheetScreen.statement(id: id, name: name),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Tap to open full statement',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      );
    }).toList();
  }

  // ---------------- Mini renderers ----------------
  Widget _buildTbMiniTable(List<Map<String, dynamic>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Account')),
          DataColumn(label: Text('Debit')),
          DataColumn(label: Text('Credit')),
        ],
        rows:
            rows
                .map(
                  (r) => DataRow(
                    cells: [
                      DataCell(Text((r['account'] ?? '').toString())),
                      DataCell(Text(_fmtAmt(r['debit']))),
                      DataCell(Text(_fmtAmt(r['credit']))),
                    ],
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _buildJournalsMini(List<Map<String, dynamic>> entries) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Narration & Lines')),
        ],
        rows:
            entries.map((e) {
              final date = (e['date'] ?? '').toString();
              final narration = (e['narration'] ?? '').toString();
              final lines =
                  (e['lines'] as List? ?? const [])
                      .cast<Map>()
                      .map((m) => Map<String, dynamic>.from(m as Map))
                      .toList();

              final lineTxt = lines
                  .take(2)
                  .map((l) {
                    final acc = (l['account'] ?? '').toString();
                    final dr = (l['debit'] ?? 0).toString();
                    final cr = (l['credit'] ?? 0).toString();
                    return '$acc (Dr $dr / Cr $cr)';
                  })
                  .join(' · ');

              return DataRow(
                cells: [
                  DataCell(Text(date)),
                  DataCell(
                    Text(
                      narration.isEmpty ? lineTxt : '$narration — $lineTxt',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }).toList(),
      ),
    );
  }

  String _fmtAmt(dynamic v) {
    if (v == null) return '0.00';
    try {
      final n = v is num ? v.toDouble() : double.parse(v.toString());
      return n.toStringAsFixed(2);
    } catch (_) {
      return v.toString();
    }
  }
}

class _MiniSheetCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onTap;

  const _MiniSheetCard({
    required this.title,
    this.subtitle,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // title + subtitle
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if ((subtitle ?? '').isNotEmpty)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
