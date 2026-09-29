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
  Future<List<Profile>>? recipientsFuture;
  RealtimeChannel? _realtimeChannel;

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
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
        ref.invalidate(notificationsProvider);
        ref.invalidate(dashboardProvider);
      },
    );
  }

  void _select(String id) {
    setState(() {
      selectedId = id;
      recipientsFuture = ref.read(repoProvider).messageRecipients(id);
    });
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
          if (items.isEmpty) return const EmptyView('No messages', icon: Icons.chat_bubble_outline);
          final active = selectedId == null || !items.any((m) => m.id == selectedId)
              ? items.first
              : items.firstWhere((m) => m.id == selectedId);
          if (selectedId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _select(active.id);
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
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _messageTile(items[i]),
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
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _messageTile(items[i]),
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

  Widget _messageTile(MessageItem message) {
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
        trailing: message.seenByMe
            ? const Icon(Icons.done_all)
            : const Icon(Icons.mark_unread_chat_alt_outlined),
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
    String type = 'information';
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
                  value: type,
                  decoration: InputDecoration(labelText: tr('Type')),
                  items: const [
                    DropdownMenuItem(value: 'information', child: T('Information')),
                    DropdownMenuItem(value: 'action_required', child: T('Action Required')),
                    DropdownMenuItem(value: 'task', child: T('Task')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
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
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
                    child: ListView(
                      shrinkWrap: true,
                      children: users.map((u) => CheckboxListTile(
                        value: selected.contains(u.id),
                        title: Text(u.fullName),
                        subtitle: Text('@${u.username}'),
                        onChanged: (v) => setDialogState(() => v == true ? selected.add(u.id) : selected.remove(u.id)),
                      )).toList(),
                    ),
                  ),
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
                    messageType: type,
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
