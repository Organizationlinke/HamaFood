import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hama_work/theme.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

class LoginHistoryScreen extends ConsumerWidget {
  const LoginHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myLoginHistoryProvider);

    return AppScaffold(
      title: 'Login history',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const HamaSectionHeader(
            title: 'Login history',
            subtitle: 'Your recent app entries and returns',
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: 14),
          Card(
            child: history.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 42),
                    const SizedBox(height: 10),
                    Text('${tr('Error')}: $e', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(myLoginHistoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const T('Retry'),
                    ),
                  ],
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(tr('No login history'))),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = rows[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        radius: 18,
                        child: Icon(Icons.login_rounded, size: 18),
                      ),
                      title: Text(
                        DateFormat('dd/MM/yyyy HH:mm:ss')
                            .format(item.loginAt.toLocal()),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        item.source == 'password_login'
                            ? tr('Password login')
                            : tr('App activity'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
