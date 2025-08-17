// lib/icc_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

// ---------- Models (name-only) ----------
class TrialRow {
  final String accountTitle, type;
  final double debit, credit, balance;
  TrialRow({
    required this.accountTitle,
    required this.type,
    required this.debit,
    required this.credit,
    required this.balance,
  });
  factory TrialRow.fromJson(Map<String, dynamic> j) => TrialRow(
    accountTitle: j['account_title'],
    type: j['type'],
    debit: (j['debit'] as num).toDouble(),
    credit: (j['credit'] as num).toDouble(),
    balance: (j['balance'] as num).toDouble(),
  );
}

class JournalLineItem {
  final int lineNo;
  final String accountTitle;
  final double debit, credit;
  JournalLineItem({
    required this.lineNo,
    required this.accountTitle,
    required this.debit,
    required this.credit,
  });
  factory JournalLineItem.fromJson(Map<String, dynamic> j) => JournalLineItem(
    lineNo: j['line_no'],
    accountTitle: j['account_title'],
    debit: (j['debit'] as num).toDouble(),
    credit: (j['credit'] as num).toDouble(),
  );
}

class JournalItem {
  final int id;
  final String date, memo;
  final String explanation; // <— NEW
  final List<JournalLineItem> lines;
  JournalItem({
    required this.id,
    required this.date,
    required this.memo,
    required this.explanation,
    required this.lines,
  });
  factory JournalItem.fromJson(Map<String, dynamic> j) => JournalItem(
    id: j['id'],
    date: j['date'],
    memo: j['memo'] ?? '',
    explanation: (j['explanation'] ?? '').toString(), // <— NEW
    lines:
        (j['lines'] as List)
            .map((e) => JournalLineItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
  );
}

class AccountRow {
  final String title, type, currency;
  final int active;
  AccountRow({
    required this.title,
    required this.type,
    required this.currency,
    required this.active,
  });
  factory AccountRow.fromJson(Map<String, dynamic> j) => AccountRow(
    title: j['title'],
    type: j['type'],
    currency: j['currency'] ?? 'NGN',
    active: (j['active'] ?? 1) as int,
  );
}

// ---------- Calls ----------
Future<List<TrialRow>> fetchTrialBalance() async {
  final r = await http.get(Uri.parse('$API_BASE/trial_balance'));
  if (r.statusCode >= 400) {
    throw Exception('GET /trial_balance failed: ${r.statusCode} ${r.body}');
  }
  final list = jsonDecode(r.body) as List;
  return list.map((e) => TrialRow.fromJson(e)).toList();
}

Future<List<JournalItem>> fetchJournals() async {
  final r = await http.get(Uri.parse('$API_BASE/journals'));
  if (r.statusCode >= 400) {
    throw Exception('GET /journals failed: ${r.statusCode} ${r.body}');
  }
  final list = jsonDecode(r.body) as List;
  return list.map((e) => JournalItem.fromJson(e)).toList();
}

Future<List<AccountRow>> fetchAccounts() async {
  final r = await http.get(Uri.parse('$API_BASE/accounts'));
  if (r.statusCode >= 400) {
    throw Exception('GET /accounts failed: ${r.statusCode} ${r.body}');
  }
  final list = jsonDecode(r.body) as List;
  return list.map((e) => AccountRow.fromJson(e)).toList();
}
