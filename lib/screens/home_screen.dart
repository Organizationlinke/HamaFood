import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final stats = ref.watch(dashboardProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return AppScaffold(
      title: 'Dashboard',
      body: stats.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e, retry: () => ref.invalidate(dashboardProvider)),
        data: (s) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [HamaColors.navy, HamaColors.navy2, HamaColors.teal],
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: HamaColors.navy.withOpacity(.18), blurRadius: 22, offset: const Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    const HamaMark(size: 62),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(greeting), style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(profile?.fullName ?? '', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          Text(tr('Keep work moving forward'), style: TextStyle(color: Colors.white.withOpacity(.78))),
                        ],
                      ),
                    ),
                    const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 34),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _metric(context, '${s.myTasks}', 'My Tasks', Icons.task_alt_rounded, HamaColors.teal, '/my-tasks')),
                  const SizedBox(width: 10),
                  Expanded(child: _metric(context, '${s.overdueTasks}', 'Overdue Tasks', Icons.warning_amber_rounded, HamaColors.red, '/team-tasks')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _metric(context, '${s.unreadMessages}', 'Unread Messages', Icons.forum_rounded, HamaColors.navy2, '/messages')),
                  const SizedBox(width: 10),
                  Expanded(child: _metric(context, '${s.unreadNotifications}', 'Unread Notifications', Icons.notifications_active_rounded, HamaColors.orange, '/notifications')),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: _action(context, 'New Task', Icons.add_task_rounded, HamaColors.teal, '/my-tasks')),
                  const SizedBox(width: 10),
                  Expanded(child: _action(context, 'Messages', Icons.forum_rounded, HamaColors.navy2, '/messages')),
                ],
              ),
              const SizedBox(height: 22),
              const HamaSectionHeader(title: 'Needs Your Attention', subtitle: 'A quick view of items that may need action', icon: Icons.bolt_rounded),
              const SizedBox(height: 12),
              _attentionRow(context, 'Ready Tasks', '${s.readyTasks}', Icons.playlist_add_check_rounded, HamaColors.orange, '/team-tasks'),
              const SizedBox(height: 8),
              _attentionRow(context, 'Unread Notifications', '${s.unreadNotifications}', Icons.notifications_none_rounded, HamaColors.teal, '/notifications'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String value, String label, IconData icon, Color color, String route) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go(route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: HamaColors.border)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HamaColors.ink)), T(label, style: const TextStyle(fontSize: 12, color: HamaColors.muted))])),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, String label, IconData icon, Color color, String route) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15)),
      onPressed: () => context.go(route),
      icon: Icon(icon),
      label: T(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _attentionRow(BuildContext context, String label, String value, IconData icon, Color color, String route) {
    return Card(
      child: ListTile(
        onTap: () => context.go(route),
        leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
        title: T(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(width: 8), const Icon(Icons.chevron_right_rounded)]),
      ),
    );
  }
}
