import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/realtime_service.dart';
import '../core/supabase_client.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  RealtimeChannel? _realtimeChannel;

  void _startRealtime() {
    if (_realtimeChannel != null) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel = HamaRealtime.notificationsForUser(
      userId: userId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(notificationsProvider);
        ref.invalidate(dashboardProvider);
      },
    );
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _startRealtime();
    return AppScaffold(
      title: 'Notifications',
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(repoProvider).markAllNotificationsRead();
            ref.invalidate(notificationsProvider);
            ref.invalidate(dashboardProvider);
          },
          child: const T('Mark all read'),
        ),
      ],
      body: ref.watch(notificationsProvider).when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          e,
          retry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              'No notifications',
              icon: Icons.notifications_none,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              await ref.read(notificationsProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final n = items[i];
                return _NotificationCard(
                  item: n,
                  onTap: () async {
                    if (!n.isRead) {
                      await ref.read(repoProvider).markNotificationRead(n.id);
                      ref.invalidate(notificationsProvider);
                      ref.invalidate(dashboardProvider);
                    }
                    if (!context.mounted) return;
                    if (n.targetType == 'task' && n.targetId != null) {
                      context.go('/tasks/${n.targetId}');
                    } else if (n.targetType == 'message' && n.targetId != null) {
                      context.go('/messages/${n.targetId}');
                    }
                  },
                  onMarkRead: n.isRead ? null : () async {
                    await ref.read(repoProvider).markNotificationRead(n.id);
                    ref.invalidate(notificationsProvider);
                    ref.invalidate(dashboardProvider);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}


class _NotificationCard extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  const _NotificationCard({required this.item, required this.onTap, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread ? HamaColors.teal.withOpacity(.055) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: unread ? HamaColors.teal.withOpacity(.20) : HamaColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.025), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(user: AvatarData(item.actorName, item.actorAvatarUrl), radius: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item.title.isEmpty ? tr('Notification') : tr(item.title), style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w700, fontSize: 15))),
                if (unread) Container(width: 8, height: 8, decoration: const BoxDecoration(color: HamaColors.orange, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 7),
              Text(item.body, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 14, color: HamaColors.muted),
                const SizedBox(width: 4),
                Text(dateTimeText(item.createdAt), style: const TextStyle(fontSize: 11, color: HamaColors.muted)),
                const Spacer(),
                if (onMarkRead != null) IconButton(onPressed: onMarkRead, icon: const Icon(Icons.done_rounded, size: 18), tooltip: tr('Mark read')),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}
