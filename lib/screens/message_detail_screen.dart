import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../services/realtime_service.dart';
import '../core/supabase_client.dart';
import '../widgets/chat_bubble.dart';

class MessageDetailScreen extends ConsumerStatefulWidget {
  final String messageId;
  const MessageDetailScreen({super.key, required this.messageId});

  @override
  ConsumerState<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends ConsumerState<MessageDetailScreen> {
  Future<MessageItem> _load() => ref.read(repoProvider).messageById(widget.messageId);
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
    _realtimeChannel = HamaRealtime.messageComments(
      messageId: widget.messageId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(messageCommentsProvider(widget.messageId));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _startRealtime();
    return AppScaffold(
      title: 'Messages',
      showBack: true,
      backRoute: '/messages',
      body: FutureBuilder<MessageItem>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(snapshot.error!);

          final message = snapshot.data!;
          final profile = ref.watch(profileProvider).valueOrNull;
          final allUsers = ref.watch(usersProvider).valueOrNull ?? const <Profile>[];
          final senderProfile = message.createdBy == null ? null : allUsers.where((u) => u.id == message.createdBy).isEmpty ? null : allUsers.firstWhere((u) => u.id == message.createdBy);
          final comments = ref.watch(messageCommentsProvider(widget.messageId));
          final recipients = ref.watch(messageRecipientsProvider(widget.messageId));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(user: senderProfile ?? AvatarData(message.senderName, message.senderAvatarUrl), radius: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message.senderName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(shortDate(message.createdAt)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.content,
                        style: const TextStyle(fontSize: 17),
                      ),
                      const SizedBox(height: 10),
                      Text('${tr('Seen')}: ${message.seenCount}/${message.recipientCount}'),
                      if (message.taskId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: FilledButton(
                            onPressed: () => context.go('/tasks/${message.taskId}'),
                            child: const T('Open Task'),
                          ),
                        ),
                      if (message.taskId == null && profile?.isGm == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton.icon(
                            onPressed: () => _convertToTask(message),
                            icon: const Icon(Icons.task_alt),
                            label: const T('New Task'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const T(
                        'Recipients',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      recipients.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('$e'),
                        data: (users) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: users.map((u) => InputChip(avatar: UserAvatar(user: u, radius: 15), label: Text(u.fullName), onPressed: () => showDialog<void>(context: context, builder: (_) => Dialog(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [UserAvatar(user: u, radius: 110), const SizedBox(height: 10), Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 10), TextButton(onPressed: () => Navigator.pop(context), child: const T('Close'))])))))).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _attachmentsCard(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const T(
                        'Reply',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      comments.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('$e'),
                        data: (items) {
                              if (items.isEmpty) return const _ReplyEmpty();
                              final me = profile?.id;
                              return Column(
                                children: items.map((comment) => HamaChatBubble(
                                  isMine: comment.createdBy == me,
                                  name: comment.creatorName,
                                  avatarUrl: comment.creatorAvatarUrl,
                                  content: comment.content,
                                  createdAt: comment.createdAt,
                                  attachments: _commentAttachments(comment.id),
                                )).toList(),
                              );
                            },
                      ),
                      TextButton.icon(
                        onPressed: _reply,
                        icon: const Icon(Icons.reply),
                        label: const T('Reply'),
                      ),
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

  Widget _attachmentsCard() {
    return FutureBuilder<List<AttachmentItem>>(
      future: ref.read(repoProvider).attachmentsForMessage(widget.messageId),
      builder: (context, snap) {
        final items = snap.data ?? const <AttachmentItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: T('Attachments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(onPressed: _addAttachment, icon: const Icon(Icons.attach_file_rounded), tooltip: tr('Add attachment')),
              ]),
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting) const LinearProgressIndicator()
              else if (items.isEmpty) const _ReplyEmpty()
              else Column(children: items.map((item) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: const CircleAvatar(child: Icon(Icons.insert_drive_file_outlined)),
                title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Row(children: [UserAvatar(user: AvatarData(item.uploaderName, item.uploaderAvatarUrl), radius: 13), const SizedBox(width: 6), Expanded(child: Text('${item.uploaderName} • ${item.createdAt == null ? '-' : dateTimeText(item.createdAt!)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: HamaColors.muted)))]),
                trailing: IconButton(onPressed: () async { final url = await ref.read(repoProvider).attachmentUrl(item); await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'); }, icon: const Icon(Icons.open_in_new_rounded)),
              )).toList()),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _addAttachment() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true, type: FileType.custom, allowedExtensions: ['doc','docx','xls','xlsx','pdf','jpg','jpeg','png','webp']);
    if (result == null) return;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        await ref.read(repoProvider).uploadAttachment(messageId: widget.messageId, fileName: file.name, bytes: file.bytes!, mimeType: _mimeFor(file.extension ?? ''));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() {});
  }

  String _mimeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _reply() async {
    final controller = TextEditingController();
    List<PlatformFile> files = [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('Reply'),
          content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: controller, maxLines: 6, decoration: InputDecoration(hintText: tr('Write a comment...'))),
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(onPressed: () async {
              final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true, type: FileType.custom, allowedExtensions: ['doc','docx','xls','xlsx','pdf','jpg','jpeg','png','webp']);
              if (result != null) setDialogState(() => files = result.files);
            }, icon: const Icon(Icons.attach_file_rounded), label: Text('${tr('Attachments')} (${files.length})'))),
            if (files.isNotEmpty) ...files.map((f) => Align(alignment: AlignmentDirectional.centerStart, child: Text('• ${f.name}', overflow: TextOverflow.ellipsis))).toList(),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const T('Cancel')),
            FilledButton(onPressed: () async {
              if (controller.text.trim().isEmpty && files.isEmpty) return;
              try {
                final commentId = await ref.read(repoProvider).addMessageComment(widget.messageId, controller.text);
                for (final file in files) { if (file.bytes != null) await ref.read(repoProvider).uploadAttachment(messageCommentId: commentId, fileName: file.name, bytes: file.bytes!, mimeType: _mimeFor(file.extension ?? '')); }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ref.invalidate(messageCommentsProvider(widget.messageId));
              } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
            }, child: const T('Send')),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Widget _commentAttachments(String commentId) {
    return FutureBuilder<List<AttachmentItem>>(future: ref.read(repoProvider).attachmentsForMessageComment(commentId), builder: (context, snap) {
      final items = snap.data ?? const <AttachmentItem>[];
      if (items.isEmpty) return const SizedBox.shrink();
      return Wrap(spacing: 6, runSpacing: 6, children: items.map((a) => ActionChip(avatar: const Icon(Icons.insert_drive_file_outlined, size: 16), label: Text(a.fileName, overflow: TextOverflow.ellipsis), onPressed: () async { final url = await ref.read(repoProvider).attachmentUrl(a); await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'); })).toList());
    });
  }

  Future<void> _convertToTask(MessageItem message) async {
    final users = await ref.read(usersProvider.future);
    if (!mounted) return;

    final title = TextEditingController(
      text: message.content.length > 60
          ? message.content.substring(0, 60)
          : message.content,
    );
    String? responsible = users.isEmpty ? null : users.first.id;
    DateTime deadline = DateTime.now().add(const Duration(days: 1));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: const T('New Task'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: tr('Title')),
                ),
                DropdownButtonFormField<String>(
                  value: responsible,
                  decoration: InputDecoration(labelText: tr('Responsible')),
                  items: users
                      .map(
                        (user) => DropdownMenuItem<String>(
                          value: user.id,
                          child: Text(user.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => dialogSetState(() => responsible = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${tr('Deadline')}: ${shortDate(deadline)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: dialogContext,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                        initialDate: deadline,
                      );
                      if (selected != null) {
                        dialogSetState(() {
                          deadline = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            17,
                          );
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const T('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (responsible == null || title.text.trim().isEmpty) return;
                try {
                  final task = await ref.read(repoProvider).createTask(
                        title: title.text,
                        priority: 'normal',
                        deadline: deadline,
                        responsibleId: responsible!,
                        messageId: message.id,
                      );
                  await ref.read(repoProvider).linkMessageToTask(message.id, task.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) setState(() {});
                  ref.invalidate(messagesProvider);
                  ref.invalidate(dashboardProvider);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                }
              },
              child: const T('Create'),
            ),
          ],
        ),
      ),
    );

    title.dispose();
  }
}


class _ReplyEmpty extends StatelessWidget {
  const _ReplyEmpty();
  @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: HamaColors.surface, borderRadius: BorderRadius.circular(14)), child: const T('No messages'));
}
