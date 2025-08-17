// lib/screens/accounts_screen.dart
import 'package:flutter/material.dart';
import '../icc_api.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late Future<List<AccountRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chart of Accounts')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = fetchAccounts()),
        child: FutureBuilder<List<AccountRow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final accounts = snap.data ?? [];
            if (accounts.isEmpty) {
              return const Center(child: Text('No accounts found.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final a = accounts[i];
                return ListTile(
                  title: Text(a.title),
                  subtitle: Text(
                    '${a.type}  •  ${a.currency}  •  ${a.active == 1 ? "Active" : "Inactive"}',
                  ),
                  leading: const Icon(Icons.account_balance_wallet),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
