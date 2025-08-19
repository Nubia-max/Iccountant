import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import 'package:taxpal/chatbot/service/ChatService.dart';

/// Full-screen "worksheet" viewer for:
/// - Trial Balance
/// - Journals
/// - Statements (by id; shows metadata + attempts to load content if endpoint exists)
class WorksheetScreen extends StatefulWidget {
  final _WorksheetKind kind;
  final int? statementId;
  final String? statementName;

  const WorksheetScreen._internal(
    this.kind, {
    Key? key,
    this.statementId,
    this.statementName,
  }) : super(key: key);

  factory WorksheetScreen.tb({Key? key}) =>
      WorksheetScreen._internal(_WorksheetKind.tb, key: key);

  factory WorksheetScreen.journals({Key? key}) =>
      WorksheetScreen._internal(_WorksheetKind.journals, key: key);

  factory WorksheetScreen.statement({
    required int id,
    String? name,
    Key? key,
  }) => WorksheetScreen._internal(
    _WorksheetKind.statement,
    key: key,
    statementId: id,
    statementName: name,
  );

  @override
  State<WorksheetScreen> createState() => _WorksheetScreenState();
}

enum _WorksheetKind { tb, journals, statement }

class _WorksheetScreenState extends State<WorksheetScreen> {
  final ChatService _svc = ChatService();

  bool _loading = true;
  String? _error;

  // TB
  List<Map<String, dynamic>> _tbRows = [];
  Map<String, dynamic>? _tbTotals;

  // Journals
  List<Map<String, dynamic>> _journals = [];

  // Statement
  Map<String, dynamic>?
  _statement; // { id, name, period_start, period_end, version, content }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _authHeaders({Map<String, String>? base}) async {
    final tok = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final h = <String, String>{};
    if (base != null) h.addAll(base);
    h['Accept'] = 'application/json';
    if (tok != null && tok.isNotEmpty) {
      h['Authorization'] = 'Bearer $tok';
    }
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      switch (widget.kind) {
        case _WorksheetKind.tb:
          final resp = await _svc.trialBalance(); // {rows, totals}
          _tbRows =
              (resp['rows'] as List? ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          _tbTotals = Map<String, dynamic>.from((resp['totals'] as Map?) ?? {});
          break;

        case _WorksheetKind.journals:
          _journals = await _svc.listJournals(limit: 500);
          break;

        case _WorksheetKind.statement:
          final api = const String.fromEnvironment(
            'API_BASE',
            defaultValue: 'http://127.0.0.1:8000',
          );
          try {
            final res = await http.get(
              Uri.parse('$api/statements/${widget.statementId}'),
              headers: await _authHeaders(),
            );
            if (res.statusCode == 200) {
              _statement = Map<String, dynamic>.from(jsonDecode(res.body));
            } else {
              _statement = {
                'id': widget.statementId,
                'name': widget.statementName ?? 'Statement',
                'content': {
                  '_notice':
                      'Statement details endpoint not available yet. Metadata loaded only.',
                },
              };
            }
          } catch (_) {
            _statement = {
              'id': widget.statementId,
              'name': widget.statementName ?? 'Statement',
              'content': {
                '_notice':
                    'Could not load statement content. Check backend endpoint.',
              },
            };
          }
          break;
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      _WorksheetKind.tb => 'Trial Balance',
      _WorksheetKind.journals => 'Journals',
      _WorksheetKind.statement =>
        (widget.statementName?.isNotEmpty == true)
            ? widget.statementName!
            : 'Statement',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
              ? Center(child: Text(_error!))
              : switch (widget.kind) {
                _WorksheetKind.tb => _buildTb(),
                _WorksheetKind.journals => _buildJournals(),
                _WorksheetKind.statement => _buildStatement(),
              },
    );
  }

  // ---------------- TB full screen ----------------
  Widget _buildTb() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Account')),
                DataColumn(label: Text('Debit')),
                DataColumn(label: Text('Credit')),
              ],
              rows:
                  _tbRows
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
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          alignment: Alignment.centerRight,
          child: Text(
            'Totals — Dr ${_fmtAmt(_tbTotals?['debit'])} / Cr ${_fmtAmt(_tbTotals?['credit'])}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ---------------- Journals full screen ----------------
  Widget _buildJournals() {
    // Flatten lines visually
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Narration')),
          DataColumn(label: Text('Account')),
          DataColumn(label: Text('Debit')),
          DataColumn(label: Text('Credit')),
        ],
        rows:
            _journals.expand((e) {
              final date = (e['date'] ?? '').toString();
              final narration = (e['narration'] ?? '').toString();
              final lines =
                  (e['lines'] as List? ?? const [])
                      .map((l) => Map<String, dynamic>.from(l as Map))
                      .toList();

              if (lines.isEmpty) {
                return [
                  DataRow(
                    cells: [
                      DataCell(Text(date)),
                      DataCell(Text(narration)),
                      const DataCell(Text('-')),
                      const DataCell(Text('0.00')),
                      const DataCell(Text('0.00')),
                    ],
                  ),
                ];
              }

              return lines.map((l) {
                return DataRow(
                  cells: [
                    DataCell(Text(date)),
                    DataCell(Text(narration)),
                    DataCell(Text((l['account'] ?? '').toString())),
                    DataCell(Text(_fmtAmt(l['debit']))),
                    DataCell(Text(_fmtAmt(l['credit']))),
                  ],
                );
              });
            }).toList(),
      ),
    );
  }

  // ---------------- Statement full screen ----------------
  Widget _buildStatement() {
    final stmt = _statement ?? {};
    final name = (stmt['name'] ?? '').toString();
    final content = (stmt['content'] as Map?) ?? {};

    // Try to render a simple 2-column view from content Map
    final rows = content.entries.toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child:
                rows.isEmpty
                    ? const Center(
                      child: Text(
                        'No content available for this statement yet.',
                      ),
                    )
                    : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Particulars')),
                          DataColumn(label: Text('Value')),
                        ],
                        rows:
                            rows
                                .map(
                                  (e) => DataRow(
                                    cells: [
                                      DataCell(Text(e.key.toString())),
                                      DataCell(Text(_stringify(e.value))),
                                    ],
                                  ),
                                )
                                .toList(),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  // ---------------- helpers ----------------
  String _fmtAmt(dynamic v) {
    if (v == null) return '0.00';
    try {
      final n = v is num ? v.toDouble() : double.parse(v.toString());
      return n.toStringAsFixed(2);
    } catch (_) {
      return v.toString();
    }
  }

  String _stringify(dynamic v) {
    if (v == null) return '';
    if (v is num || v is String || v is bool) return v.toString();
    try {
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (_) {
      return v.toString();
    }
  }
}
