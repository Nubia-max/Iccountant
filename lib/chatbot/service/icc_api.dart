// lib/icc_api.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Configure your API base at build time if needed:
/// flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

/// --- Auth header helper (reads the JWT saved by login_screen.dart) ---
final _storage = const FlutterSecureStorage();

Future<Map<String, String>> _authHeaders({Map<String, String>? base}) async {
  final token = await _storage.read(key: 'access_token');
  final h = <String, String>{};
  if (base != null) h.addAll(base);
  h['Accept'] = 'application/json';
  if (token != null && token.isNotEmpty) {
    h['Authorization'] = 'Bearer $token';
  }
  return h;
}

/// =======================
/// Models (name-only)
/// =======================
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
  final String explanation; // compact "Dr … • Cr …"
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
    memo: (j['memo'] ?? '').toString(),
    explanation: (j['explanation'] ?? '').toString(),
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
    currency: (j['currency'] ?? 'NGN').toString(),
    active: (j['active'] ?? 1) as int,
  );
}

/// =======================
/// API calls
/// =======================
Future<List<TrialRow>> fetchTrialBalance() async {
  final r = await http.get(
    Uri.parse('$API_BASE/trial_balance'),
    headers: await _authHeaders(),
  );
  if (r.statusCode >= 400) {
    throw Exception('GET /trial_balance failed: ${r.statusCode} ${r.body}');
  }
  final data = jsonDecode(r.body) as List;
  return data
      .map((e) => TrialRow.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

Future<List<JournalItem>> fetchJournals() async {
  final r = await http.get(
    Uri.parse('$API_BASE/journals'),
    headers: await _authHeaders(),
  );
  if (r.statusCode >= 400) {
    throw Exception('GET /journals failed: ${r.statusCode} ${r.body}');
  }
  final data = jsonDecode(r.body) as List;
  return data
      .map((e) => JournalItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

Future<List<AccountRow>> fetchAccounts() async {
  final r = await http.get(
    Uri.parse('$API_BASE/accounts'),
    headers: await _authHeaders(),
  );
  if (r.statusCode >= 400) {
    throw Exception('GET /accounts failed: ${r.statusCode} ${r.body}');
  }
  final data = jsonDecode(r.body) as List;
  return data
      .map((e) => AccountRow.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}
