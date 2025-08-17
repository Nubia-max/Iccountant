// lib/screens/trial_balance_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../icc_api.dart';

class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  late Future<List<TrialRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchTrialBalance();
  }

  String _fmt(num v) =>
      NumberFormat.currency(symbol: '₦', decimalDigits: 2).format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trial Balance')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = fetchTrialBalance()),
        child: FutureBuilder<List<TrialRow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return const Center(child: Text('No postings yet.'));
            }
            final totalDr = rows.fold<double>(0, (a, r) => a + r.debit);
            final totalCr = rows.fold<double>(0, (a, r) => a + r.credit);

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Account Title')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Debit')),
                      DataColumn(label: Text('Credit')),
                      DataColumn(label: Text('Balance')),
                    ],
                    rows:
                        rows
                            .map(
                              (r) => DataRow(
                                cells: [
                                  DataCell(Text(r.accountTitle)),
                                  DataCell(Text(r.type)),
                                  DataCell(Text(_fmt(r.debit))),
                                  DataCell(Text(_fmt(r.credit))),
                                  DataCell(Text(_fmt(r.balance))),
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
              ],
            );
          },
        ),
      ),
    );
  }
}
