import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

const permissionCatalog = <String, String>{
  'tasks.view': 'View tasks',
  'tasks.create': 'Create tasks',
  'tasks.edit': 'Edit tasks',
  'tasks.delete': 'Delete tasks',
  'tasks.cancel': 'Cancel tasks',
  'tasks.manage_status': 'Manage task status',
  'tasks.evaluate': 'Evaluate tasks',
  'tasks.start': 'Start tasks',
  'tasks.request_completion': 'Request completion',
  'tasks.confirm_completion': 'Confirm completion',
  'tasks.reopen': 'Reopen completed tasks',
  'attachments.upload': 'Upload task/message attachments',
  'messages.view': 'View messages',
  'messages.create': 'Send messages',
  'messages.manage': 'Manage messages',
  'notifications.view': 'View notifications',
  'users.view': 'View users',
  'users.create': 'Create users',
  'users.edit': 'Edit users',
  'users.reset_password': 'Reset user passwords',
  'permissions.manage': 'Manage permissions',
  'profile.edit': 'Edit own profile',
};

const gmOnlyPermissions = <String>{
  'tasks.create','tasks.edit','tasks.delete','users.view','users.create','users.edit','users.reset_password','permissions.manage',
};

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});
  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  String? selectedUserId;
  Set<String> enabled = {};
  bool loading = false;

  Future<void> _load(String userId) async {
    setState(() { selectedUserId = userId; loading = true; });
    try {
      final rows = await ref.read(repoProvider).userPermissions(userId);
      setState(() => enabled = rows.where((x) => x.enabled).map((x) => x.permissionKey).toSet());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _toggle(String key, bool value) async {
    final id = selectedUserId;
    if (id == null) return;
    setState(() => value ? enabled.add(key) : enabled.remove(key));
    try {
      await ref.read(repoProvider).setUserPermission(userId: id, permissionKey: key, enabled: value);
    } catch (e) {
      setState(() => value ? enabled.remove(key) : enabled.add(key));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    if (me?.isGm != true) return AppScaffold(title: 'Permissions', body: const Center(child: T('Administrator permission required')));
    return AppScaffold(
      title: 'Permissions',
      body: ref.watch(usersProvider).when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (users) {
          if (selectedUserId == null && users.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _load(users.first.id));
          }
          final selected = selectedUserId == null ? null : users.where((u) => u.id == selectedUserId).isEmpty ? null : users.firstWhere((u) => u.id == selectedUserId);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 330,
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(10),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = users[i];
                      return ListTile(
                        selected: u.id == selectedUserId,
                        leading: UserAvatar(user: u, radius: 22),
                        title: Text(u.fullName),
                        subtitle: Text('@${u.username} • ${AppI18n.roleLabel(u.role)}'),
                        onTap: () => _load(u.id),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  child: loading
                      ? const LoadingView()
                      : selected == null
                          ? const EmptyView('Select a user', icon: Icons.admin_panel_settings_outlined)
                          : ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                Text(selected.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text('@${selected.username} • ${selected.department}'),
                                const SizedBox(height: 18),
                                if (selected.isGm)
                                  const Card(child: Padding(padding: EdgeInsets.all(14), child: T('The General Manager has all permissions automatically.'))),
                                const T('Effective permissions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 8),
                                ...permissionCatalog.entries.map((entry) {
                                  final gmOnly = gmOnlyPermissions.contains(entry.key);
                                  final effective = selected.isGm || (enabled.contains(entry.key) && !gmOnly);
                                  return SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: effective,
                                    onChanged: selected.isGm || gmOnly ? null : (v) => _toggle(entry.key, v),
                                    title: Row(children: [Expanded(child: T(entry.value)), if (gmOnly) const Chip(label: T('GM only'))]),
                                    subtitle: Text(gmOnly ? '${entry.key} • GM only' : entry.key),
                                  );
                                }),
                              ],
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
