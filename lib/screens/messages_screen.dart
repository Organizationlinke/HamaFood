import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hama_work/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../services/realtime_service.dart';
import '../core/supabase_client.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  String? selectedId;
  String _statusTab = 'not_started';
  Future<List<Profile>>? recipientsFuture;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _messageCommentsChannel;

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    final commentsChannel = _messageCommentsChannel;
    if (commentsChannel != null) {
      supabase.removeChannel(commentsChannel);
    }
    super.dispose();
  }

  void _startRealtime() {
    if (_realtimeChannel != null) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel = HamaRealtime.messagesForUser(
      userId: userId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(messagesProvider);
        ref.invalidate(messageStatusCountsProvider);
        ref.invalidate(messageUnreadCommentsCountsProvider);
        ref.invalidate(unreadMessageConversationsProvider);
        ref.invalidate(notificationsProvider);
        ref.invalidate(dashboardProvider);
      },
    );
    // Replies can arrive without changing the parent message row.
    _messageCommentsChannel = HamaRealtime.messageCommentsForUser(
      userId: userId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(messageUnreadCommentsCountsProvider);
        ref.invalidate(unreadMessageConversationsProvider);
      },
    );
  }

  Future<void> _changeStatus(String messageId, String status) async {
    try {
      await ref.read(repoProvider).setMessageStatus(messageId, status);
      if (!mounted) return;
      ref.invalidate(messagesProvider);
      ref.invalidate(messageStatusCountsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _select(String id, {bool markRead = true}) async {
    setState(() {
      selectedId = id;
      recipientsFuture = ref.read(repoProvider).messageRecipients(id);
    });
    if (!markRead) return;
    try {
      await ref.read(repoProvider).markMessageSeen(id);
      await ref.read(repoProvider).markMessageCommentsRead(id);
      ref.invalidate(messagesProvider);
      ref.invalidate(messageUnreadCommentsCountsProvider);
      ref.invalidate(unreadMessageConversationsProvider);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _startRealtime();
    return AppScaffold(
      title: 'Messages',
      actions: [
        IconButton(
          tooltip: tr('New Message'),
          onPressed: () => _newMessage(context),
          icon: const Icon(Icons.add_comment_outlined),
        ),
      ],
      body: ref.watch(messagesProvider).when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e, retry: () => ref.invalidate(messagesProvider)),
        data: (items) {
          final unreadCounts = ref.watch(messageUnreadCommentsCountsProvider).maybeWhen(data: (m) => m, orElse: () => const <String, int>{});
          final statusCounts = ref.watch(messageStatusCountsProvider).maybeWhen(data: (m) => m, orElse: () => const <String, int>{});
          final filtered = items.where((m) => m.myStatus == _statusTab).toList();
          final activeList = filtered.isNotEmpty ? filtered : items;
          if (items.isEmpty) return const EmptyView('No messages', icon: Icons.chat_bubble_outline);
          final active = selectedId == null || !activeList.any((m) => m.id == selectedId)
              ? activeList.first
              : activeList.firstWhere((m) => m.id == selectedId);
          if (selectedId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _select(active.id, markRead: false);
            });
          }

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: HamaSectionHeader(
                  title: 'Messages',
                  subtitle: 'Information, actions and task-related communication',
                  icon: Icons.forum_rounded,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _statusTabs(statusCounts),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (!wide) {
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(messagesProvider);
                          await ref.read(messagesProvider.future);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _messageTile(filtered[i], unreadCounts[filtered[i].id] ?? 0),
                        ),
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: HamaColors.border),
                        boxShadow: [BoxShadow(color: HamaColors.navy.withOpacity(.06), blurRadius: 22, offset: const Offset(0, 8))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 430,
                            child: RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(messagesProvider);
                                await ref.read(messagesProvider.future);
                              },
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _messageTile(filtered[i], unreadCounts[filtered[i].id] ?? 0),
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _recipientPanel(active)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusTabs(Map<String, int> counts) {
    final tabs = [
      ('not_started', 'لم يتم البدء', Icons.radio_button_unchecked),
      ('in_progress', 'تحت التنفيذ', Icons.pending_actions),
      ('completed', 'منتهية', Icons.check_circle_outline),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HamaColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: tabs.map((tab) {
          final selected = _statusTab == tab.$1;
          final count = counts[tab.$1] ?? 0;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _statusTab = tab.$1;
                selectedId = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                decoration: BoxDecoration(
                  color: selected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab.$3, size: 17),
                    const SizedBox(width: 6),
                    Flexible(child: Text(tab.$2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w900 : FontWeight.w700))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: selected ? Theme.of(context).colorScheme.primary : HamaColors.border, borderRadius: BorderRadius.circular(20)),
                      child: Text('$count', style: TextStyle(color: selected ? Colors.white : HamaColors.ink, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _statusChip(String status) {
    final label = status == 'not_started' ? 'لم يتم البدء' : status == 'in_progress' ? 'تحت التنفيذ' : 'منتهية';
    final icon = status == 'not_started' ? Icons.radio_button_unchecked : status == 'in_progress' ? Icons.pending_actions : Icons.check_circle;
    return Chip(avatar: Icon(icon, size: 15), label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)));
  }

  Widget _statusMenu(MessageItem message) {
    return PopupMenuButton<String>(
      tooltip: 'حالة الرسالة',
      initialValue: message.myStatus,
      onSelected: (value) => _changeStatus(message.id, value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'not_started', child: Text('لم يتم البدء')),
        PopupMenuItem(value: 'in_progress', child: Text('تحت التنفيذ')),
        PopupMenuItem(value: 'completed', child: Text('منتهية')),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  Widget _messageTile(MessageItem message, int unreadReplies) {
    final selected = selectedId == message.id;
    final icon = message.messageType == 'task'
        ? Icons.task_alt
        : message.messageType == 'action_required'
            ? Icons.priority_high
            : Icons.info_outline;
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: () async {
          if (MediaQuery.sizeOf(context).width < 900) {
            await context.push('/messages/${message.id}');
            if (mounted) ref.invalidate(messagesProvider);
          } else {
            _select(message.id);
          }
        },
        leading: UserAvatar(user: AvatarData(message.senderName, message.senderAvatarUrl), radius: 22),
        title: Text(message.senderName),
        subtitle: Text(
          '${message.content}\n${tr('Seen')}: ${message.seenCount}/${message.recipientCount}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _statusChip(message.myStatus),
          if (unreadReplies > 0) Container(width: 24, height: 24, alignment: Alignment.center, decoration: const BoxDecoration(color: HamaColors.red, shape: BoxShape.circle), child: Text('$unreadReplies', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
          const SizedBox(width: 4),
          message.seenByMe ? const Icon(Icons.done_all) : const Icon(Icons.mark_unread_chat_alt_outlined),
          _statusMenu(message),
        ]),
      ),
    );
  }

  Widget _recipientPanel(MessageItem message) {
    final future = recipientsFuture ?? ref.read(repoProvider).messageRecipients(message.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [HamaColors.navy, HamaColors.navy2]), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              UserAvatar(user: AvatarData(message.senderName, message.senderAvatarUrl), radius: 23),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.senderName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(shortDate(message.createdAt), style: TextStyle(color: Colors.white.withOpacity(.72))) ])),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(padding: const EdgeInsets.all(18), child: Text(message.content, style: const TextStyle(fontSize: 17, height: 1.5))),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.people_alt_outlined),
                    const SizedBox(width: 8),
                    const Expanded(child: T('Recipients', style: TextStyle(fontWeight: FontWeight.w700))),
                    Text('${message.recipientCount}'),
                  ]),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Profile>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                      if (snapshot.hasError) return Text(tr('Could not load recipients'));
                      final users = snapshot.data ?? const <Profile>[];
                      if (users.isEmpty) return Text(tr('No recipients'));
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: users.map((u) => InputChip(avatar: UserAvatar(user: u, radius: 14), label: Text(u.fullName), onPressed: () => _showUserImage(u))).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.go('/messages/${message.id}'),
            icon: const Icon(Icons.open_in_new),
            label: const T('Open Message'),
          ),
        ],
      ),
    );
  }

  void _showUserImage(Profile u) {
    if (u.avatarUrl == null || u.avatarUrl!.isEmpty) return;
    showDialog<void>(context: context, builder: (_) => Dialog(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [UserAvatar(user: u, radius: 110), const SizedBox(height: 12), Text(u.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text('@${u.username}'), const SizedBox(height: 12), TextButton(onPressed: () => Navigator.pop(context), child: const T('Close'))]))));
  }

  Future<void> _newMessage(BuildContext context) async {
    final users = await ref.read(usersProvider.future);
    if (!mounted) return;
    final content = TextEditingController();
    String audience = 'everyone';
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('New Message'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(children: [
                DropdownButtonFormField<String>(
                  value: audience,
                  decoration: InputDecoration(labelText: tr('Recipients')),
                  items: const [
                    DropdownMenuItem(value: 'everyone', child: T('Everyone')),
                    DropdownMenuItem(value: 'selected', child: T('Selected users')),
                  ],
                  onChanged: (v) => setDialogState(() => audience = v ?? audience),
                ),
                if (audience == 'selected') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${tr('Selected users')}: ${selected.length}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final result = await showModalBottomSheet<Set<String>>(
                            context: context,
                            isScrollControlled: true,
                            builder: (sheetContext) {
                              final search = TextEditingController();
                              Set<String> temp = {...selected};
                              return StatefulBuilder(
                                builder: (context, setSheetState) => SafeArea(
                                  child: SizedBox(
                                    height: MediaQuery.sizeOf(context).height * .78,
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: TextField(
                                            controller: search,
                                            decoration: InputDecoration(
                                              prefixIcon: const Icon(Icons.search),
                                              hintText: tr('Search users'),
                                            ),
                                            onChanged: (_) => setSheetState(() {}),
                                          ),
                                        ),
                                        Expanded(
                                          child: ListView(
                                            children: users.where((u) {
                                              final q = search.text.trim().toLowerCase();
                                              return q.isEmpty ||
                                                  u.fullName.toLowerCase().contains(q) ||
                                                  u.username.toLowerCase().contains(q);
                                            }).map((u) => CheckboxListTile(
                                              dense: true,
                                              value: temp.contains(u.id),
                                              title: Text(u.fullName),
                                              subtitle: Text('@${u.username}'),
                                              onChanged: (v) => setSheetState(() {
                                                if (v == true) {
                                                  temp.add(u.id);
                                                } else {
                                                  temp.remove(u.id);
                                                }
                                              }),
                                            )).toList(),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: FilledButton(
                                            onPressed: () => Navigator.pop(sheetContext, temp),
                                            child: Text(tr('Done')),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                          if (result != null) setDialogState(() {
                            selected
                              ..clear()
                              ..addAll(result);
                          });
                        },
                        icon: const Icon(Icons.people_outline),
                        label: Text(tr('Choose')),
                      ),
                    ],
                  ),
                  if (selected.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selected.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, index) {
                          final id = selected.elementAt(index);
                          final u = users.firstWhere((x) => x.id == id);
                          return InputChip(
                            avatar: UserAvatar(user: u, radius: 13),
                            label: Text(u.fullName, overflow: TextOverflow.ellipsis),
                            onDeleted: () => setDialogState(() => selected.remove(id)),
                          );
                        },
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextField(controller: content, maxLines: 8, decoration: InputDecoration(labelText: tr('Message'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                if (content.text.trim().isEmpty || (audience == 'selected' && selected.isEmpty)) return;
                try {
                  await ref.read(repoProvider).createMessage(
                    content: content.text,
                    messageType: 'information',
                    audienceType: audience,
                    recipientIds: selected.toList(),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(messagesProvider);
                  ref.invalidate(notificationsProvider);
                  ref.invalidate(dashboardProvider);
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Send'),
            ),
          ],
        ),
      ),
    );
    content.dispose();
  }
}
