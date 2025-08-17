// lib/screens/journals_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../icc_api.dart';

class JournalsScreen extends StatefulWidget {
  const JournalsScreen({super.key});

  @override
  State<JournalsScreen> createState() => _JournalsScreenState();
}

class _JournalsScreenState extends State<JournalsScreen> {
  late Future<List<JournalItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchJournals();
  }

  String _fmt(num v) =>
      NumberFormat.currency(symbol: '₦', decimalDigits: 2).format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journals')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = fetchJournals()),
        child: FutureBuilder<List<JournalItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final js = snap.data ?? [];
            if (js.isEmpty) {
              return const Center(child: Text('No journals yet.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: js.length,
              itemBuilder: (ctx, i) {
                final j = js[i];
                final totalDr = j.lines.fold<double>(0, (a, l) => a + l.debit);
                final totalCr = j.lines.fold<double>(0, (a, l) => a + l.credit);

                return Card(
                  child: ExpansionTile(
                    title: Text('Journal ${j.id} — ${j.date}'),
                    subtitle: Text(j.memo.isEmpty ? '(no memo)' : j.memo),
                    childrenPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    children: [
                      // Explanation (compact)
                      if (j.explanation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  j.explanation,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Lines table
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('#')),
                            DataColumn(label: Text('Account Title')),
                            DataColumn(label: Text('Debit')),
                            DataColumn(label: Text('Credit')),
                          ],
                          rows:
                              j.lines
                                  .map(
                                    (l) => DataRow(
                                      cells: [
                                        DataCell(Text(l.lineNo.toString())),
                                        DataCell(Text(l.accountTitle)),
                                        DataCell(Text(_fmt(l.debit))),
                                        DataCell(Text(_fmt(l.credit))),
                                      ],
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Totals — DR: ${_fmt(totalDr)}   CR: ${_fmt(totalCr)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
