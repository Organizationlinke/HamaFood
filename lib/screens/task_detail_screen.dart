import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../services/attachment_opener.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../services/realtime_service.dart';
import '../core/supabase_client.dart';
import '../widgets/chat_bubble.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late Future<Task> _taskFuture;
  late Future<List<TaskStage>> _stagesFuture;
  Set<String> _permissions = <String>{};
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _followerNotesChannel;
  final TextEditingController _taskChatController = TextEditingController();
  final List<PlatformFile> _taskChatFiles = <PlatformFile>[];
  bool _taskChatSending = false;
  bool _mobileCompactHeader = false;
  final Set<String> _taskChatUploaded = <String>{};

  @override
  void initState() {
    super.initState();
    _taskFuture = ref.read(repoProvider).taskById(widget.taskId);
    _stagesFuture = ref.read(repoProvider).taskStages(widget.taskId);
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final p = await ref.read(repoProvider).myProfile();
      final keys = [
        'tasks.start',
        'tasks.request_completion',
        'tasks.manage_status',
        'tasks.confirm_completion',
        'tasks.reopen',
        'tasks.evaluate',
        'tasks.cancel',
        'attachments.upload'
      ];
      final granted = <String>{};
      if (p?.isGm == true) {
        granted.addAll(keys);
      } else {
        for (final k in keys) {
          if (await ref.read(repoProvider).hasPermission(k)) granted.add(k);
        }
      }
      if (mounted) setState(() => _permissions = granted);
    } catch (_) {}
  }

  bool _can(String key) => _permissions.contains(key);

  bool _canExecutionAction(Task task, Profile? profile, String permission) =>
      profile != null && _can(permission) && task.responsibleId == profile.id;

  void _startRealtime() {
    if (_realtimeChannel != null) return;
    _realtimeChannel = HamaRealtime.taskComments(
      taskId: widget.taskId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(taskCommentsProvider(widget.taskId));
        ref.invalidate(taskUnreadCommentsProvider(widget.taskId));
      },
    );
    _followerNotesChannel = HamaRealtime.taskFollowerNotes(
      taskId: widget.taskId,
      onChange: () {
        if (!mounted) return;
        ref.invalidate(taskFollowerNotesProvider(widget.taskId));
      },
    );
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    final followerChannel = _followerNotesChannel;
    if (followerChannel != null) {
      supabase.removeChannel(followerChannel);
    }
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    _taskChatController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _taskFuture = ref.read(repoProvider).taskById(widget.taskId);
      _stagesFuture = ref.read(repoProvider).taskStages(widget.taskId);
    });
    await _taskFuture;
  }

  String _fmt(double n) =>
      n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    _startRealtime();
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return AppScaffold(
      title: 'Tasks',
      showBack: true,
      backRoute: '/team-tasks',
      onRefresh: _refresh,
      body: FutureBuilder<Task>(
        future: _taskFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snapshot.hasError) return ErrorView(snapshot.error!);

          final task = snapshot.data!;
          final profile = ref.watch(profileProvider).valueOrNull;
          final comments = ref.watch(taskCommentsProvider(widget.taskId));
          final unreadChatCount = ref
              .watch(taskUnreadCommentsProvider(widget.taskId))
              .maybeWhen(data: (n) => n, orElse: () => 0);

          return FutureBuilder<List<TaskStage>>(
            future: _stagesFuture,
            builder: (context, stageSnap) {
              if (!stageSnap.hasData) return const LoadingView();
              final stages = stageSnap.data!;
              final isAdmin =
                  ref.watch(profileProvider).valueOrNull?.isGm == true;
              final showProgress = isAdmin || task.totalQuantity != null;
              final showStages = isAdmin || stages.isNotEmpty;
              final tabs = <Tab>[const Tab(text: 'Task')];
              final views = <Widget>[_taskTab(task, profile)];
              if (showProgress) {
                tabs.add(Tab(text: tr('Progress')));
                views.add(_progressTab(task, profile));
              }
              if (showStages) {
                tabs.add(Tab(text: tr('Stages')));
                views.add(_stagesTab(task, profile));
              }
              tabs.add(Tab(text: tr('Daily Work Log')));
              views.add(_dailyTab(task));
              tabs.add(Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Chat')),
                if (unreadChatCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: HamaColors.red, shape: BoxShape.circle),
                      child: Text('$unreadChatCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)))
                ]
              ])));
              views.add(_chatTab(comments, task));

              return DefaultTabController(
                length: tabs.length,
                child: Column(
                  children: [
                    _taskHeader(
                        task,
                        ref.watch(usersProvider).valueOrNull ??
                            const <Profile>[],
                        isMobile: isMobile),
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: HamaColors.border)),
                      child: Material(
                        color: Colors.transparent,
                        child: TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                              color: HamaColors.teal.withOpacity(.10),
                              borderRadius: BorderRadius.circular(12)),
                          labelColor: HamaColors.teal,
                          unselectedLabelColor: HamaColors.muted,
                          labelStyle:
                              const TextStyle(fontWeight: FontWeight.w800),
                          tabs: tabs,
                        ),
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (isMobile &&
                              notification.metrics.axis == Axis.vertical) {
                            final compact = notification.metrics.pixels > 18;
                            if (compact != _mobileCompactHeader && mounted) {
                              setState(() => _mobileCompactHeader = compact);
                            }
                          }
                          return false;
                        },
                        child: TabBarView(children: views),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _taskHeader(Task task, List<Profile> users, {required bool isMobile}) {
    final byId = {for (final u in users) u.id: u};
    final responsible = byId[task.responsibleId];
    final follower = byId[task.followerId];

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(16, isMobile ? 8 : 14, 16, 8),
      padding: EdgeInsets.all(isMobile ? 12 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [HamaColors.navy, HamaColors.navy2],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: HamaColors.navy.withOpacity(.16),
              blurRadius: 18,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isMobile ? 250 : 430),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          style: TextStyle(
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white),
                          maxLines: isMobile ? 2 : null,
                          overflow: isMobile ? TextOverflow.ellipsis : null),
                      const SizedBox(height: 5),
                      Text(task.code,
                          style: TextStyle(
                              color: Colors.white.withOpacity(.70),
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              StatusChip(task.status),
              if (task.isOverdue) const Chip(avatar: Icon(Icons.warning_amber_rounded, size: 15), label: Text('متأخرة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              PriorityChip(task.priority),
            ],
          ),
          if (!isMobile || !_mobileCompactHeader) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _headerUser('Responsible', responsible),
                _headerUser('Follower', follower),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerUser(String label, Profile? user) {
    return Container(
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(.12))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        UserAvatar(user: user ?? AvatarData('—', null), radius: 17),
        const SizedBox(width: 9),
        Flexible(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(label),
              style: TextStyle(
                  color: Colors.white.withOpacity(.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Text(user?.fullName ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ])),
      ]),
    );
  }

  Widget _tabScroll(Widget child) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [child],
      ),
    );
  }

  Widget _sectionHeader(
      {required String title,
      required String subtitle,
      required IconData icon}) {
    if (MediaQuery.sizeOf(context).width < 600) return const SizedBox.shrink();
    return HamaSectionHeader(title: title, subtitle: subtitle, icon: icon);
  }

  Widget _taskTab(Task task, Profile? profile) {
    final users = ref.watch(usersProvider).valueOrNull ?? const <Profile>[];
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final userById = {for (final u in users) u.id: u};
    final responsibleName = task.responsibleId == null
        ? '-'
        : (userById[task.responsibleId!]?.fullName ?? task.responsibleId!);
    final followerName = task.followerId == null
        ? '-'
        : (userById[task.followerId!]?.fullName ?? task.followerId!);

    return _tabScroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           
          
          _sectionHeader(
              title: 'Task Overview',
              subtitle: 'Details, ownership and available actions',
              icon: Icons.dashboard_customize_rounded),
          const SizedBox(height: 12),
            if (task.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) ...[
                      const T('Description',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                    ],
                    Text(task.description!),
                  ],
                ),
              ),
            ),
          ],
             const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMobile) ...[
                    const T('Task Actions',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                  ],
                  _actions(task, profile),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
          _attachmentsCard(task),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  _kv(
                      'Status',
                      tr(_statusLabel(task.status))),
                  _kv('Deadline',
                      task.deadline == null ? '-' : shortDate(task.deadline!)),
                  if (task.isOverdue) _kv('Task timing', tr('Overdue')), 
                  _kv('Evidence required',
                      task.evidenceRequired ? tr('Yes') : tr('No')),
                  _kv('Admin approval',
                      task.managerConfirmed ? tr('Yes') : tr('No')),
                  // _userKv('Responsible', userById[task.responsibleId]),
                  // _userKv('Follower', userById[task.followerId]),
                  // _userKv('Created by', userById[task.createdBy]),
                  _kv('Created at', dateTimeText(task.createdAt)),
                  if (task.totalQuantity != null)
                    _kv('Total quantity',
                        '${_fmt(task.totalQuantity!)} ${task.quantityUnit ?? ''}'),
                  if (task.score != null) _kv('Score 1-10', '${task.score}'),
                ],
              ),
            ),
          ),
          if (task.completionProofNote?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Card(
              color: HamaColors.teal.withOpacity(.06),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.fact_check_rounded,
                            color: HamaColors.teal),
                        const SizedBox(width: 8),
                        const Expanded(
                            child: T('Completion proof note',
                                style: TextStyle(fontWeight: FontWeight.w900)))
                      ]),
                      const SizedBox(height: 8),
                      Text(task.completionProofNote!),
                    ]),
              ),
            ),
          ],
          // if (task.description?.isNotEmpty == true) ...[
          //   const SizedBox(height: 8),
          //   Card(
          //     child: Padding(
          //       padding: const EdgeInsets.all(16),
          //       child: Column(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           if (!isMobile) ...[
          //             const T('Description',
          //                 style: TextStyle(
          //                     fontSize: 18, fontWeight: FontWeight.bold)),
          //             const SizedBox(height: 8),
          //           ],
          //           Text(task.description!),
          //         ],
          //       ),
          //     ),
          //   ),
          // ],
          // const SizedBox(height: 12),
          // Card(
          //   child: Padding(
          //     padding: const EdgeInsets.all(16),
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.start,
          //       children: [
          //         if (!isMobile) ...[
          //           const T('Task Actions',
          //               style: TextStyle(
          //                   fontSize: 18, fontWeight: FontWeight.bold)),
          //           const SizedBox(height: 12),
          //         ],
          //         _actions(task, profile),
          //       ],
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _progressTab(Task task, Profile? profile) {
    return _tabScroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              title: 'Progress',
              subtitle: 'Track daily achievement against the target',
              icon: Icons.insights_rounded),
          const SizedBox(height: 12),
          _progressSection(task, profile),
          if (MediaQuery.sizeOf(context).width >= 600) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const T('How progress works',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const T(
                        'The responsible person records the quantity completed each day. The task progress is calculated from the accumulated daily achievement against the total quantity.'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stagesTab(Task task, Profile? profile) {
    return _tabScroll(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(
          title: 'Task Stages',
          subtitle: 'Break the task into manageable parts',
          icon: Icons.account_tree_rounded),
      const SizedBox(height: 12),
      _stagesSection(task, profile)
    ]));
  }

  Widget _dailyTab(Task task) {
    return _tabScroll(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(
          title: 'Daily Work Log',
          subtitle: 'A clear record of what was achieved each day',
          icon: Icons.calendar_month_rounded),
      const SizedBox(height: 12),
      _dailySection(task)
    ]));
  }

  Widget _chatTab(AsyncValue<List<TaskComment>> comments, Task task) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader(
                title: 'Task Chat',
                subtitle: 'Keep task-related communication in one place',
                icon: Icons.forum_rounded,
              ),
              const SizedBox(height: 12),
              comments.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (items) {
                  if (items.isEmpty)
                    return const _EmptyInline(
                        icon: Icons.chat_bubble_outline, text: 'No messages');
                  final me = ref.read(profileProvider).valueOrNull?.id;
                  return Column(
                    children: items
                        .map((comment) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: HamaChatBubble(
                                isMine: comment.createdBy == me,
                                name: comment.creatorName,
                                avatarUrl: comment.creatorAvatarUrl,
                                content: comment.content,
                                createdAt: comment.createdAt,
                                attachments: _commentAttachments(comment),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        if (_taskIsClosed(task))
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: HamaColors.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 18, color: HamaColors.muted),
                  const SizedBox(width: 8),
                  Text(tr('Completed tasks are read-only'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: HamaColors.muted)),
                ],
              ),
            ),
          )
        else
          _taskChatComposer(isMobile, enabled: true),
      ],
    );
  }

  Widget _taskChatComposer(bool isMobile, {bool enabled = true}) {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 8, 10, isMobile ? 8 : 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_taskChatFiles.isNotEmpty) _taskChatFilesPreview(),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_can('attachments.upload'))
                    IconButton(
                      tooltip: tr('Add attachment'),
                      onPressed: !enabled || _taskChatSending
                          ? null
                          : _pickTaskChatFiles,
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _taskChatController,
                      minLines: 1,
                      maxLines: 5,
                      enabled: enabled && !_taskChatSending,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: tr('Write a comment...'),
                        filled: true,
                        fillColor: HamaColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: tr('Send'),
                    onPressed:
                        !enabled || _taskChatSending ? null : _sendTaskChat,
                    icon: _taskChatSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskChatFilesPreview() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: HamaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HamaColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _taskChatFiles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final file = _taskChatFiles[index];
          final uploaded = _taskChatUploaded.contains(file.name);
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              radius: 17,
              child: Icon(
                  uploaded
                      ? Icons.check_rounded
                      : Icons.insert_drive_file_outlined,
                  size: 18),
            ),
            title: Text(file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(uploaded
                ? tr('Uploaded')
                : (_taskChatSending
                    ? tr('Uploading...')
                    : '${_taskFileSize(file.size)} • ${tr('Ready to send')}')),
            trailing: _taskChatSending && !uploaded
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    onPressed: _taskChatSending
                        ? null
                        : () => setState(() => _taskChatFiles.removeAt(index)),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
          );
        },
      ),
    );
  }

  String _taskFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickTaskChatFiles() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'doc',
        'docx',
        'xls',
        'xlsx',
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp'
      ],
    );
    if (result != null && mounted) {
      setState(() {
        _taskChatUploaded.clear();
        _taskChatFiles.addAll(result.files.where((f) => f.bytes != null));
      });
    }
  }

  Future<void> _sendTaskChat() async {
    final task = await ref.read(repoProvider).taskById(widget.taskId);
    if (_taskIsClosed(task)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Completed tasks are read-only'))));
      return;
    }
    final text = _taskChatController.text.trim();
    if (text.isEmpty && _taskChatFiles.isEmpty) return;
    setState(() => _taskChatSending = true);
    try {
      final comment =
          await ref.read(repoProvider).addTaskComment(widget.taskId, text);
      for (final file in List<PlatformFile>.from(_taskChatFiles)) {
        if (file.bytes != null) {
          await ref.read(repoProvider).uploadAttachment(
                taskCommentId: comment.id,
                fileName: file.name,
                bytes: file.bytes!,
                mimeType: _mimeFor(file.extension ?? ''),
              );
          if (mounted) setState(() => _taskChatUploaded.add(file.name));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
      _taskChatController.clear();
      _taskChatFiles.clear();
      _taskChatUploaded.clear();
      ref.invalidate(taskCommentsProvider(widget.taskId));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _taskChatSending = false);
    }
  }

  Widget _followerNotesTab(Task task, Profile? profile) {
    final canWrite = profile != null &&
        (profile.isGm || profile.isManager || profile.id == task.followerId);
    return Column(
      children: [
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final notes = ref.watch(taskFollowerNotesProvider(task.id));
              return notes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (items) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const HamaSectionHeader(
                      title: 'Follower Notes',
                      subtitle:
                          'Follow-up notes are separate from the task chat',
                      icon: Icons.visibility_outlined,
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const _EmptyInline(
                          icon: Icons.note_alt_outlined,
                          text: 'No follower notes yet.')
                    else
                      ...items.map((n) => _followerNoteCard(n, profile)),
                  ],
                ),
              );
            },
          ),
        ),
        if (canWrite) _followerNoteComposer(task),
      ],
    );
  }

  Widget _followerNoteCard(TaskFollowerNote note, Profile? profile) {
    final canManage = profile != null &&
        (profile.isGm || profile.isManager || profile.id == note.createdBy);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
                user: AvatarData(note.creatorName, note.creatorAvatarUrl),
                radius: 19),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(note.creatorName,
                          style: const TextStyle(fontWeight: FontWeight.w900))),
                  if (canManage) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editFollowerNote(note),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteFollowerNote(note),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ]),
                Text(dateTimeText(note.createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: HamaColors.muted)),
                const SizedBox(height: 6),
                Text(note.note),
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget _followerNoteComposer(Task task) {
    final controller = TextEditingController();
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: tr('Write a follower note...'),
                filled: true,
                fillColor: HamaColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                try {
                  await ref
                      .read(repoProvider)
                      .addTaskFollowerNote(task.id, controller.text);
                  controller.clear();
                  ref.invalidate(taskFollowerNotesProvider(task.id));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editFollowerNote(TaskFollowerNote note) async {
    final controller = TextEditingController(text: note.note);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const T('Edit follower note'),
        content: TextField(controller: controller, maxLines: 6),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const T('Cancel')),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await ref
                  .read(repoProvider)
                  .updateTaskFollowerNote(note.id, controller.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              ref.invalidate(taskFollowerNotesProvider(widget.taskId));
            },
            child: const T('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _deleteFollowerNote(TaskFollowerNote note) async {
    await ref.read(repoProvider).deleteTaskFollowerNote(note.id);
    ref.invalidate(taskFollowerNotesProvider(widget.taskId));
  }

  Widget _commentAttachments(TaskComment comment) {
    return FutureBuilder<List<AttachmentItem>>(
      future: ref.read(repoProvider).attachmentsForTaskComment(comment.id),
      builder: (context, snap) {
        final items = snap.data ?? const <AttachmentItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .map((a) => ActionChip(
                    avatar: const Icon(Icons.attach_file_rounded, size: 15),
                    label: Text(a.fileName, overflow: TextOverflow.ellipsis),
                    onPressed: () async {
                      final ok = await openAttachment(() => ref.read(repoProvider).attachmentUrl(a));
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح المرفق. اسمح بالنوافذ المنبثقة لهذا الموقع ثم حاول مرة أخرى.')));
                      }
                    },
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _userKv(String key, Profile? user) {
    return SizedBox(
      width: 235,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          T(key),
          const SizedBox(height: 6),
          if (user == null)
            const Text('—')
          else
            Row(
              children: [
                UserAvatar(user: user, radius: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          T(key),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'not_started':
        return 'Not Started';
      case 'in_progress':
        return 'In Progress';
      case 'ready_for_completion':
        return 'Ready for Completion';
      case 'awaiting_approval':
        return 'Awaiting Approval';
      case 'completed':
        return 'Completed';
      case 'overdue':
        return 'Overdue';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  bool _canRecord(Task task, Profile? p) =>
      task.status == 'in_progress' &&
      p != null &&
      (p.isGm ||
          p.isManager ||
          task.responsibleId == p.id ||
          task.followerId == p.id);

  bool _canWriteProgress(Task task, Profile? p) =>
      task.status == 'in_progress' &&
      p != null &&
      (p.isGm || p.isManager || task.responsibleId == p.id);

  bool _canWriteDailyLog(Task task, Profile? p) =>
      task.status == 'in_progress' &&
      p != null &&
      (p.isGm ||
          p.isManager ||
          task.responsibleId == p.id ||
          task.followerId == p.id);

  bool _isFollower(Task task, Profile? p) =>
      p != null && task.followerId == p.id && !p.isGm && !p.isManager;

  bool _taskIsClosed(Task task) => task.status == 'completed';

  Widget _progressSection(Task task, Profile? profile) {
    return FutureBuilder<List<TaskDailyUpdate>>(
      future: ref.read(repoProvider).taskDailyUpdates(task.id),
      builder: (context, snap) {
        if (!snap.hasData) return const _SectionLoading();
        final updates = snap.data!;
        final done =
            updates.fold<double>(0, (sum, u) => sum + (u.quantityDone ?? 0));
        final total = task.totalQuantity;
        final ratio =
            total != null && total > 0 ? (done / total).clamp(0.0, 1.0) : null;
        return _proCard(
          icon: Icons.insights_rounded,
          title: 'Progress & Daily Achievement',
          trailing: _canWriteProgress(task, profile)
              ? IconButton(
                  onPressed: () => _addDailyUpdate(task, null),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: tr('Add daily achievement'))
              : null,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (total != null && total > 0) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: Text('${_fmt(done)} ${task.quantityUnit ?? ''}',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: HamaColors.navy))),
                Text('${_fmt(total)} ${task.quantityUnit ?? ''}',
                    style: const TextStyle(
                        color: HamaColors.muted, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: ratio, minHeight: 10)),
              const SizedBox(height: 7),
              Text(
                  '${((ratio ?? 0) * 100).toStringAsFixed(1)}% ${tr('completed')}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: HamaColors.teal)),
            ] else
              const _EmptyInline(
                  icon: Icons.track_changes_outlined,
                  text: 'No total quantity was defined for this task.'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(tr('Recent daily achievements'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (updates.isEmpty)
              const _EmptyInline(
                  icon: Icons.event_note_outlined,
                  text: 'No daily achievement recorded yet.')
            else
              ...updates.take(8).map((u) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: HamaColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: HamaColors.border)),
                    child: Row(children: [
                      UserAvatar(
                          user: AvatarData(u.creatorName, u.creatorAvatarUrl),
                          radius: 19),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(u.creatorName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(
                                '${shortDate(u.workDate)} • ${u.quantityDone == null ? tr('No quantity') : '${_fmt(u.quantityDone!)} ${task.quantityUnit ?? ''}'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (u.workNote?.isNotEmpty == true)
                              Text(u.workNote!,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(dateTimeText(u.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: HamaColors.muted)),
                          ])),
                    ]),
                  )),
          ]),
        );
      },
    );
  }

  Widget _stagesSection(Task task, Profile? profile) {
    final canManage = profile?.isGm == true;
    return FutureBuilder<List<TaskStage>>(
      future: ref.read(repoProvider).taskStages(task.id),
      builder: (context, snap) {
        if (!snap.hasData) return const _SectionLoading();
        final stages = snap.data!;
        return _proCard(
          icon: Icons.account_tree_rounded,
          title: 'Task Stages',
          trailing: canManage && !_taskIsClosed(task)
              ? IconButton(
                  onPressed: () => _addStage(task, stages.length + 1),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: tr('Add stage'))
              : null,
          child: stages.isEmpty
              ? const _EmptyInline(
                  icon: Icons.account_tree_outlined, text: 'No stages defined.')
              : Column(
                  children: stages.asMap().entries.map((entry) {
                  final stage = entry.value;
                  return FutureBuilder<List<TaskDailyUpdate>>(
                    future: ref.read(repoProvider).taskDailyUpdates(task.id),
                    builder: (context, uSnap) {
                      final updates = uSnap.data ?? const <TaskDailyUpdate>[];
                      final done = updates
                          .where((u) => u.stageId == stage.id)
                          .fold<double>(
                              0, (sum, u) => sum + (u.quantityDone ?? 0));
                      final target = stage.targetQuantity;
                      final ratio = target != null && target > 0
                          ? (done / target).clamp(0.0, 1.0)
                          : null;
                      return Container(
                        margin: EdgeInsets.only(
                            bottom: entry.key == stages.length - 1 ? 0 : 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: HamaColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: HamaColors.border)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 38,
                                        height: 38,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: HamaColors.teal
                                                .withOpacity(.10),
                                            shape: BoxShape.circle),
                                        child: Text('${stage.sortOrder}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: HamaColors.teal))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(stage.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16)),
                                          const SizedBox(height: 5),
                                          Text(
                                              '${tr('Deadline')}: ${shortDate(stage.deadline)}',
                                              style: const TextStyle(
                                                  color: HamaColors.muted)),
                                          if (target != null) ...[
                                            const SizedBox(height: 9),
                                            Text(
                                                '${_fmt(done)} / ${_fmt(target)} ${stage.quantityUnit ?? task.quantityUnit ?? ''}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            const SizedBox(height: 5),
                                            LinearProgressIndicator(
                                                value: ratio,
                                                minHeight: 7,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ],
                                        ])),
                                    if (_canWriteProgress(task, profile))
                                      IconButton(
                                          onPressed: () =>
                                              _addDailyUpdate(task, stage),
                                          icon: const Icon(
                                              Icons.add_circle_outline_rounded),
                                          tooltip: tr('Add daily achievement')),
                                  ]),
                              const Divider(height: 22),
                              _auditLine(
                                  stage.creatorName,
                                  stage.creatorAvatarUrl,
                                  stage.createdAt,
                                  'Recorded by'),
                            ]),
                      );
                    },
                  );
                }).toList()),
        );
      },
    );
  }

  Widget _dailySection(Task task) {
    return FutureBuilder<List<TaskDailyUpdate>>(
      future: ref.read(repoProvider).taskDailyUpdates(task.id),
      builder: (context, snap) {
        if (!snap.hasData) return const _SectionLoading();
        final updates = snap.data!;
        final grouped = <String, List<TaskDailyUpdate>>{};
        for (final u in updates)
          grouped
              .putIfAbsent(
                  u.workDate.toIso8601String().substring(0, 10), () => [])
              .add(u);
        final profile = ref.watch(profileProvider).valueOrNull;
        return _proCard(
          icon: Icons.calendar_month_rounded,
          title: 'Daily Work Log',
          trailing: _canWriteDailyLog(task, profile)
              ? IconButton(
                  onPressed: () => _addDailyUpdate(task, null),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: tr('Add daily work'))
              : null,
          child: grouped.isEmpty
              ? const _EmptyInline(
                  icon: Icons.event_note_outlined,
                  text: 'No daily work recorded yet.')
              : Column(
                  children: grouped.entries.map((entry) {
                  final dayItems = entry.value;
                  final total = dayItems.fold<double>(
                      0, (s, u) => s + (u.quantityDone ?? 0));
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: HamaColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HamaColors.border)),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      leading: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: HamaColors.navy.withOpacity(.07),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.today_rounded,
                              color: HamaColors.navy2)),
                      title: Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(
                          '${dayItems.length} ${tr('updates')} • ${_fmt(total)} ${task.quantityUnit ?? ''}'),
                      children: dayItems
                          .map((u) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border:
                                        Border.all(color: HamaColors.border)),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      UserAvatar(
                                          user: AvatarData(u.creatorName,
                                              u.creatorAvatarUrl),
                                          radius: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(u.creatorName,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900)),
                                            const SizedBox(height: 3),
                                            Text(
                                                '${u.quantityDone == null ? tr('No quantity') : '${_fmt(u.quantityDone!)} ${task.quantityUnit ?? ''}'}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: HamaColors.teal)),
                                            if (u.workNote?.isNotEmpty ==
                                                true) ...[
                                              const SizedBox(height: 5),
                                              Text(u.workNote!)
                                            ],
                                            const SizedBox(height: 5),
                                            Text(dateTimeText(u.createdAt),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: HamaColors.muted)),
                                            const SizedBox(height: 8),
                                            _dailyAttachments(u, task),
                                          ])),
                                    ]),
                              ))
                          .toList(),
                    ),
                  );
                }).toList()),
        );
      },
    );
  }

  Widget _proCard(
      {required IconData icon,
      required String title,
      Widget? trailing,
      required Widget child}) {
    return Card(
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: HamaColors.teal.withOpacity(.10),
                      borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: HamaColors.teal)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(tr(title),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900))),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 14),
            child,
          ])),
    );
  }

  Widget _auditLine(String name, String? avatar, DateTime? date, String label) {
    return Row(children: [
      UserAvatar(user: AvatarData(name, avatar), radius: 16),
      const SizedBox(width: 8),
      Expanded(
          child: Text('${tr(label)}: $name',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: HamaColors.muted))),
      Text(dateTimeText(date),
          style: const TextStyle(fontSize: 11, color: HamaColors.muted)),
    ]);
  }

  Future<void> _addStage(Task task, int order) async {
    if (_taskIsClosed(task)) return;
    final title = TextEditingController();
    final qty = TextEditingController();
    final unit = TextEditingController();
    DateTime deadline =
        task.deadline ?? DateTime.now().add(const Duration(days: 1));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('Add stage'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: title,
                    decoration: InputDecoration(labelText: tr('Stage name'))),
                TextField(
                    controller: qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: tr('Stage quantity'))),
                TextField(
                    controller: unit,
                    decoration: InputDecoration(labelText: tr('Unit'))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${tr('Deadline')}: ${shortDate(deadline)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                        initialDate: deadline,
                      );
                      if (d != null)
                        setDialogState(() =>
                            deadline = DateTime(d.year, d.month, d.day, 17));
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                try {
                  await ref.read(repoProvider).createTaskStage(
                        taskId: task.id,
                        title: title.text,
                        deadline: deadline,
                        targetQuantity: double.tryParse(qty.text.trim()),
                        quantityUnit: unit.text.trim().isEmpty
                            ? task.quantityUnit
                            : unit.text,
                        sortOrder: order,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() {});
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Save'),
            ),
          ],
        ),
      ),
    );

    title.dispose();
    qty.dispose();
    unit.dispose();
  }

  Future<void> _addDailyUpdate(Task task, TaskStage? stage) async {
    if (task.status != 'in_progress') {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Start the task before recording progress'))));
      return;
    }
    final qty = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final pickedFiles = <PlatformFile>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(stage == null
              ? tr('Add daily achievement')
              : '${tr('Daily achievement')}: ${stage.title}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: tr('Quantity completed')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 4,
                  decoration:
                      InputDecoration(labelText: tr('What did you do today?')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${tr('Work date')}: ${shortDate(date)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: date,
                      );
                      if (d != null) setDialogState(() => date = d);
                    },
                  ),
                ),
                if (_can('attachments.upload')) ...[
                  const Divider(),
                  Row(children: [
                    const Expanded(
                        child: T('Attachments',
                            style: TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          withData: true,
                          allowMultiple: true,
                          type: FileType.custom,
                          allowedExtensions: [
                            'doc',
                            'docx',
                            'xls',
                            'xlsx',
                            'pdf',
                            'jpg',
                            'jpeg',
                            'png',
                            'webp'
                          ],
                        );
                        if (result != null)
                          setDialogState(() => pickedFiles.addAll(
                              result.files.where((f) => f.bytes != null)));
                      },
                      icon: const Icon(Icons.attach_file_rounded),
                      tooltip: tr('Add attachment'),
                    ),
                  ]),
                  if (pickedFiles.isNotEmpty)
                    ...pickedFiles.asMap().entries.map((e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(e.value.name,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setDialogState(
                                  () => pickedFiles.removeAt(e.key))),
                        )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                final q = double.tryParse(qty.text.trim());
                if (q != null && q < 0) return;
                if (q == null &&
                    note.text.trim().isEmpty &&
                    pickedFiles.isEmpty) return;
                try {
                  final update = await ref.read(repoProvider).saveDailyUpdate(
                        taskId: task.id,
                        stageId: stage?.id,
                        workDate: date,
                        quantityDone: q,
                        workNote: note.text,
                      );
                  for (final file in pickedFiles) {
                    if (file.bytes != null) {
                      await ref.read(repoProvider).uploadAttachment(
                            dailyUpdateId: update.id,
                            fileName: file.name,
                            bytes: file.bytes!,
                            mimeType: _mimeFor(file.extension ?? ''),
                          );
                    }
                  }
                  await ref
                      .read(repoProvider)
                      .finalizeDailyUpdateAttachments(update.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() {});
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Save'),
            ),
          ],
        ),
      ),
    );

    qty.dispose();
    note.dispose();
  }

  Widget _dailyAttachments(TaskDailyUpdate update, Task task) {
    return FutureBuilder<List<AttachmentItem>>(
      future: ref.read(repoProvider).attachmentsForDailyUpdate(update.id),
      builder: (context, snap) {
        final items = snap.data ?? const <AttachmentItem>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(tr('Attachments'),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: HamaColors.muted))
          ]),
          if (items.isNotEmpty)
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items
                    .map((a) => ActionChip(
                        avatar: const Icon(Icons.insert_drive_file_outlined,
                            size: 16),
                        label:
                            Text(a.fileName, overflow: TextOverflow.ellipsis),
                        onPressed: () async {
                          final ok = await openAttachment(() => ref.read(repoProvider).attachmentUrl(a));
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح المرفق. اسمح بالنوافذ المنبثقة لهذا الموقع ثم حاول مرة أخرى.')));
                          }
                        }))
                    .toList()),
        ]);
      },
    );
  }

  Widget _attachmentsCard(Task task) {
    return FutureBuilder<List<AttachmentItem>>(
      future: ref.read(repoProvider).attachmentsForTask(widget.taskId),
      builder: (context, snap) {
        final items = snap.data ?? const <AttachmentItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: T('Attachments',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))),
                if (!_taskIsClosed(task) &&
                    !_isFollower(task, ref.read(profileProvider).valueOrNull) &&
                    _can('attachments.upload'))
                  IconButton(
                      onPressed: _addAttachment,
                      icon: const Icon(Icons.attach_file_rounded),
                      tooltip: tr('Add attachment')),
              ]),
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (items.isEmpty)
                const _EmptyInline(
                    icon: Icons.attach_file_outlined, text: 'No attachments')
              else
                Column(children: items.map(_attachmentTile).toList()),
            ]),
          ),
        );
      },
    );
  }

  Widget _attachmentTile(AttachmentItem item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading:
          const CircleAvatar(child: Icon(Icons.insert_drive_file_outlined)),
      title: Text(item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Row(children: [
        UserAvatar(
            user: AvatarData(item.uploaderName, item.uploaderAvatarUrl),
            radius: 13),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
                '${item.uploaderName} • ${item.createdAt == null ? '-' : dateTimeText(item.createdAt!)}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: HamaColors.muted)))
      ]),
      trailing: IconButton(
          onPressed: () async {
            final ok = await openAttachment(() => ref.read(repoProvider).attachmentUrl(item));
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح المرفق. اسمح بالنوافذ المنبثقة لهذا الموقع ثم حاول مرة أخرى.')));
            }
          },
          icon: const Icon(Icons.open_in_new_rounded)),
    );
  }

  Future<void> _addAttachment() async {
    final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'doc',
          'docx',
          'xls',
          'xlsx',
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'webp'
        ]);
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        await ref.read(repoProvider).uploadAttachment(
            taskId: widget.taskId,
            fileName: file.name,
            bytes: bytes,
            mimeType:
                file.extension == null ? null : _mimeFor(file.extension!));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() {});
  }

  String _mimeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _actions(Task task, Profile? profile) {
    final isAdmin = profile?.isGm == true;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (task.status == 'not_started' &&
            _canExecutionAction(task, profile, 'tasks.start'))
          OutlinedButton.icon(
              onPressed: () => _setStatus('in_progress'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const T('Start')),
        if (task.status == 'in_progress' &&
            _canExecutionAction(task, profile, 'tasks.request_completion'))
          OutlinedButton.icon(
              onPressed: () => _requestCompletion(task),
              icon: const Icon(Icons.done_all_rounded),
              label: const T('Request completion')),
        if (task.status == 'ready_for_completion' &&
            task.followerId != null &&
            profile?.id == task.followerId)
          FilledButton.icon(
              onPressed: () => _reviewCompletion(task),
              icon: const Icon(Icons.fact_check_rounded),
              label: const T('Follow-up completed')),
        if ((task.status == 'awaiting_approval' ||
                (task.status == 'ready_for_completion' &&
                    task.followerId == null)) &&
            isAdmin)
          FilledButton.icon(
              onPressed: () => _confirm(task),
              icon: const Icon(Icons.verified_rounded),
              label: const T('Approve operation')),
        if (_can('tasks.cancel') &&
            task.status != 'cancelled' &&
            task.status != 'completed')
          OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const T('Cancel')),
        if (_can('tasks.reopen') && task.status == 'completed')
          OutlinedButton.icon(
              onPressed: _reopen,
              icon: const Icon(Icons.replay_rounded),
              label: const T('Reopen')),
        if (_can('tasks.evaluate'))
          FilledButton.icon(
              onPressed: _evaluate,
              icon: const Icon(Icons.star_rate_rounded),
              label: const T('Evaluate')),
        if (isAdmin)
          OutlinedButton.icon(
              onPressed: () => _editTask(task),
              icon: const Icon(Icons.edit_rounded),
              label: const T('Edit')),
        if (isAdmin)
          OutlinedButton.icon(
              onPressed: _deleteTask,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const T('Delete')),
      ],
    );
  }

  Future<void> _requestCompletion(Task task) async {
    if (!task.evidenceRequired) {
      await _setStatus('ready_for_completion');
      return;
    }
    final note = TextEditingController();
    bool uploading = false;
    bool attached = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('Completion proof required'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const T(
                'Add a written proof or attach a file before requesting completion.'),
            const SizedBox(height: 12),
            TextField(
                controller: note,
                maxLines: 4,
                decoration:
                    InputDecoration(labelText: tr('Achievement proof / note'))),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: uploading
                  ? null
                  : () async {
                      final result = await FilePicker.platform.pickFiles(
                          withData: true,
                          type: FileType.custom,
                          allowedExtensions: [
                            'doc',
                            'docx',
                            'xls',
                            'xlsx',
                            'pdf',
                            'jpg',
                            'jpeg',
                            'png',
                            'webp'
                          ]);
                      if (result == null || result.files.first.bytes == null)
                        return;
                      setDialogState(() => uploading = true);
                      try {
                        await ref.read(repoProvider).uploadAttachment(
                            taskId: task.id,
                            fileName: result.files.first.name,
                            bytes: result.files.first.bytes!,
                            mimeType:
                                _mimeFor(result.files.first.extension ?? ''),
                            isCompletionProof: true);
                        setDialogState(() => attached = true);
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                      } finally {
                        if (dialogContext.mounted)
                          setDialogState(() => uploading = false);
                      }
                    },
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(attached ? tr('Proof attached') : tr('Attach proof')),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const T('Cancel')),
            FilledButton(
                onPressed: uploading
                    ? null
                    : () async {
                        if (note.text.trim().isEmpty && !attached) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      tr('Add a proof note or attachment'))));
                          return;
                        }
                        try {
                          await ref.read(repoProvider).updateTaskStatus(
                              task.id, 'ready_for_completion',
                              proofNote: note.text.trim().isEmpty
                                  ? null
                                  : note.text.trim());
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                          await _refresh();
                          ref.invalidate(tasksProvider('my'));
                          ref.invalidate(tasksProvider('team'));
                          ref.invalidate(dashboardProvider);
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      },
                child: const T('Request completion'))
          ],
        ),
      ),
    );
    note.dispose();
  }

  Future<void> _setStatus(String status) async {
    try {
      await ref.read(repoProvider).updateTaskStatus(widget.taskId, status);
      await _refresh();
      ref.invalidate(tasksProvider('my'));
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reviewCompletion(Task task) async {
    try {
      await ref.read(repoProvider).reviewTaskCompletion(task.id);
      await _refresh();
      ref.invalidate(tasksProvider('my'));
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirm(Task task) async {
    try {
      await ref.read(repoProvider).confirmTask(task.id);
      await _refresh();
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(repoProvider).cancelTask(widget.taskId);
      await _refresh();
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reopen() async {
    try {
      await ref.read(repoProvider).reopenTask(widget.taskId);
      await _refresh();
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Delete task'),
        content: const T(
            'This action cannot be undone. Are you sure you want to delete this task?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const T('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(c, true),
              child: const T('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repoProvider).deleteTask(widget.taskId);
      ref.invalidate(tasksProvider('my'));
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(dashboardProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editTask(Task task) async {
    final users = await ref.read(usersProvider.future);
    if (!mounted) return;
    final title = TextEditingController(text: task.title);
    final description = TextEditingController(text: task.description ?? '');
    final quantity = TextEditingController(
        text: task.totalQuantity == null ? '' : _fmt(task.totalQuantity!));
    final unit = TextEditingController(text: task.quantityUnit ?? '');
    String priority = task.priority;
    String responsible =
        task.responsibleId ?? (users.isEmpty ? '' : users.first.id);
    String? follower = task.followerId;
    DateTime deadline =
        task.deadline ?? DateTime.now().add(const Duration(days: 1));
    bool evidence = task.evidenceRequired;
    const bool confirmation = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('Edit Task'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(children: [
                TextField(
                    controller: title,
                    decoration: InputDecoration(labelText: tr('Title *'))),
                const SizedBox(height: 10),
                TextField(
                    controller: description,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: tr('Description'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: tr('Total quantity')))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: unit,
                          decoration: InputDecoration(labelText: tr('Unit')))),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: InputDecoration(labelText: tr('Priority')),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: T('Normal')),
                    DropdownMenuItem(value: 'urgent', child: T('Urgent'))
                  ],
                  onChanged: (v) =>
                      setDialogState(() => priority = v ?? priority),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: responsible.isEmpty ? null : responsible,
                  decoration: InputDecoration(labelText: tr('Responsible')),
                  items: users
                      .map((u) => DropdownMenuItem(
                          value: u.id, child: Text(u.fullName)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => responsible = v ?? responsible),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: follower,
                  decoration: InputDecoration(labelText: tr('Follower')),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: T('No follower')),
                    ...users.map((u) => DropdownMenuItem<String?>(
                        value: u.id, child: Text(u.fullName)))
                  ],
                  onChanged: (v) => setDialogState(() => follower = v),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text('${tr('Deadline')}: ${shortDate(deadline)}'),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: deadline,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (picked != null)
                      setDialogState(() => deadline = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          deadline.hour,
                          deadline.minute));
                  },
                ),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: evidence,
                    title: const T('Evidence required'),
                    onChanged: (v) => setDialogState(() => evidence = v)),
                const SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: T('Admin approval required'),
                    onChanged: null),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || responsible.isEmpty) return;
                try {
                  await ref.read(repoProvider).updateTask(
                        id: task.id,
                        title: title.text,
                        description: description.text,
                        priority: priority,
                        deadline: deadline,
                        responsibleId: responsible,
                        followerId: follower,
                        evidenceRequired: evidence,
                        managerConfirmationRequired: confirmation,
                        totalQuantity: double.tryParse(quantity.text.trim()),
                        quantityUnit: unit.text,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _refresh();
                  ref.invalidate(tasksProvider('my'));
                  ref.invalidate(tasksProvider('team'));
                  ref.invalidate(dashboardProvider);
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    description.dispose();
    quantity.dispose();
    unit.dispose();
  }

  Future<void> _evaluate() async {
    final score = ValueNotifier<int>(8);
    final comment = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const T('Evaluate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: score,
              builder: (_, value, __) => Text('${tr('Score 1-10')}: $value'),
            ),
            ValueListenableBuilder<int>(
              valueListenable: score,
              builder: (_, value, __) => Slider(
                min: 1,
                max: 10,
                divisions: 9,
                value: value.toDouble(),
                onChanged: (v) => score.value = v.round(),
              ),
            ),
            TextField(
                controller: comment,
                maxLines: 4,
                decoration:
                    InputDecoration(labelText: tr('Evaluation comment'))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const T('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await ref
                    .read(repoProvider)
                    .evaluateTask(widget.taskId, score.value, comment.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _refresh();
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const T('Save'),
          ),
        ],
      ),
    );

    score.dispose();
    comment.dispose();
  }

  Future<void> _addComment() async {
    final controller = TextEditingController();
    final pickedFiles = <PlatformFile>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('Reply'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: InputDecoration(hintText: tr('Write a comment...')),
              ),
              if (_can('attachments.upload')) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(
                      child: T('Attachments',
                          style: TextStyle(fontWeight: FontWeight.w800))),
                  IconButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        withData: true,
                        allowMultiple: true,
                        type: FileType.custom,
                        allowedExtensions: [
                          'doc',
                          'docx',
                          'xls',
                          'xlsx',
                          'pdf',
                          'jpg',
                          'jpeg',
                          'png',
                          'webp'
                        ],
                      );
                      if (result != null)
                        setDialogState(() => pickedFiles.addAll(
                            result.files.where((f) => f.bytes != null)));
                    },
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                ]),
                if (pickedFiles.isNotEmpty)
                  ...pickedFiles.asMap().entries.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title:
                            Text(e.value.name, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setDialogState(
                                () => pickedFiles.removeAt(e.key))),
                      )),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const T('Cancel')),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty && pickedFiles.isEmpty)
                  return;
                try {
                  final comment = await ref
                      .read(repoProvider)
                      .addTaskComment(widget.taskId, controller.text);
                  for (final file in pickedFiles) {
                    if (file.bytes != null) {
                      await ref.read(repoProvider).uploadAttachment(
                            taskCommentId: comment.id,
                            fileName: file.name,
                            bytes: file.bytes!,
                            mimeType: _mimeFor(file.extension ?? ''),
                          );
                    }
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(taskCommentsProvider(widget.taskId));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const T('Send'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr('Loading...'))
          ])));
}

class _EmptyInline extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyInline({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: HamaColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(icon, size: 34, color: HamaColors.muted),
        const SizedBox(height: 8),
        T(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: HamaColors.muted, fontWeight: FontWeight.w600))
      ]));
}
