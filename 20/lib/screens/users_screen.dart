import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    return AppScaffold(
      title: 'Users',
      actions: [
        if (profile?.isGm == true)
          IconButton(
            tooltip: tr('New User'),
            onPressed: () => _newUser(context),
            icon: const Icon(Icons.person_add_alt_1),
          ),
      ],
      body: ref.watch(usersProvider).when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e, retry: () => ref.invalidate(usersProvider)),
        data: (users) {
          if (users.isEmpty) {
            return const EmptyView('No users', icon: Icons.people_outline);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(usersProvider);
              await ref.read(usersProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final u = users[i];
                return Card(
                  child: ListTile(
                    leading: UserAvatar(user: u, radius: 22),
                    title: Text(u.fullName),
                    subtitle: Text('@${u.username} • ${u.department}'),
                    trailing: profile?.isGm == true
                        ? PopupMenuButton<String>(
                            onSelected: (value) { if (value == 'reset') _resetPassword(u); },
                            itemBuilder: (_) => [PopupMenuItem(value: 'reset', child: T('Reset password'))],
                          )
                        : Chip(label: Text(AppI18n.roleLabel(u.role))),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: profile?.isGm == true
          ? FloatingActionButton.extended(
              onPressed: () => _newUser(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const T('New User'),
            )
          : null,
    );
  }

  Future<void> _resetPassword(Profile user) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Reset password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${tr('User')}: ${user.fullName}'),
          const SizedBox(height: 12),
          TextField(controller: controller, obscureText: true, decoration: InputDecoration(labelText: tr('Temporary password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Reset')),
        ],
      ),
    );
    if (ok != true) { controller.dispose(); return; }
    if (controller.text.length < 6) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password must be at least 6 characters'))));
      controller.dispose(); return;
    }
    try {
      await ref.read(repoProvider).resetUserPassword(userId: user.id, newPassword: controller.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password reset successfully'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    controller.dispose();
  }

  Future<void> _newUser(BuildContext context) async {
    final fullName = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final jobTitle = TextEditingController();
    String role = 'employee';
    String department = 'SITE';

    const departments = <String, String>{
      'SITE': 'إدارة الموقع',
      'PROD': 'الإنتاج',
      'MAINT': 'الصيانة',
      'COLD': 'الثلاجة / التبريد',
      'PURCH': 'المشتريات',
      'LOG': 'اللوجستيات',
      'QUALITY': 'الجودة',
      'WAREHOUSE': 'المخازن',
      'PLANNING': 'تخطيط',
      'LEGAL': 'قانونية',
      'FINANCE': 'مالية',
      'SECURITY': 'أمن',
      'LOCAL_SALES': 'مبيعات محلية',
      'EXPORT_SALES': 'مبيعات تصدير',
      'IT': 'IT',
      'HR': 'HR',
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('New User'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: fullName, decoration: InputDecoration(labelText: tr('Full Name'))),
                  const SizedBox(height: 10),
                  TextField(controller: username, decoration: InputDecoration(labelText: tr('Username'))),
                  const SizedBox(height: 10),
                  TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: tr('Password'))),
                  const SizedBox(height: 10),
                  TextField(controller: jobTitle, decoration: InputDecoration(labelText: tr('Job Title'))),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: InputDecoration(labelText: tr('Role')),
                    items: const [
                      DropdownMenuItem(value: 'manager', child: T('Manager')),
                      DropdownMenuItem(value: 'employee', child: T('Employee')),
                    ],
                    onChanged: (v) => setDialogState(() => role = v ?? role),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: department,
                    decoration: InputDecoration(labelText: tr('Department')),
                    items: departments.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => department = v ?? department),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                if (fullName.text.trim().isEmpty || username.text.trim().isEmpty || password.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Please complete the required fields'))));
                  return;
                }
                try {
                  await ref.read(repoProvider).createUser(
                    username: username.text,
                    fullName: fullName.text,
                    password: password.text,
                    role: role,
                    departmentCode: department,
                    jobTitle: jobTitle.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(usersProvider);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('User created successfully'))));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Create'),
            ),
          ],
        ),
      ),
    );

    fullName.dispose();
    username.dispose();
    password.dispose();
    jobTitle.dispose();
  }
}
