import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../theme.dart';

class TasksScreen extends ConsumerStatefulWidget {
  final String scope;

  const TasksScreen({super.key, this.scope = 'team'});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String status = 'not_started';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final provider = tasksProvider(widget.scope);

    return AppScaffold(
      title: widget.scope == 'my' ? 'My Tasks' : 'Team Tasks',
      actions: [
        if (!isMobile && profile?.isGm == true)
          IconButton(
            tooltip: tr('New Task'),
            onPressed: () => _newTask(context),
            icon: const Icon(Icons.add_task),
          ),
      ],
      floatingActionButton: profile?.isGm == true
          ? FloatingActionButton.extended(
              onPressed: () => _newTask(context),
              icon: const Icon(Icons.add_task),
              label: const T('New Task'),
            )
          : null,
      body: ref.watch(provider).when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              e,
              retry: () => ref.invalidate(provider),
            ),
            data: (tasks) {
              final users =
                  ref.watch(usersProvider).valueOrNull ?? const <Profile>[];
              final byId = {for (final u in users) u.id: u};
              final filtered = status == 'all'
                  ? tasks
                  : tasks.where((t) => t.effectiveStatus == status).toList();

              return Column(
                children: [
                  if (!isMobile && profile?.isGm == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.icon(
                          onPressed: () => _newTask(context),
                          icon: const Icon(Icons.add_task),
                          label: const T('New Task'),
                        ),
                      ),
                    ),
                  if (!isMobile)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: HamaSectionHeader(
                        title: 'Tasks',
                        subtitle:
                            'Track responsibility, deadlines and progress',
                        icon: Icons.task_alt_rounded,
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: HamaColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: HamaColors.border)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _filter('not_started', 'Not Started',
                            Icons.radio_button_unchecked_rounded),
                        _filter('in_progress', 'In Progress',
                            Icons.play_circle_outline_rounded),
                        _filter('ready_for_completion', 'Ready for Completion',
                            Icons.fact_check_outlined),
                        _filter(
                            'overdue', 'Overdue', Icons.warning_amber_rounded),
                        _filter('completed', 'Completed',
                            Icons.check_circle_outline_rounded),
                        _filter(
                            'cancelled', 'Cancelled', Icons.cancel_outlined),
                        _filter('all', 'All', Icons.grid_view_rounded),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const EmptyView('No tasks',
                            icon: Icons.task_alt_outlined)
                        : RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(provider);
                              await ref.read(provider.future);
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final task = filtered[index];
                                final urgent = task.priority == 'urgent';
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        context.go('/tasks/${task.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 52,
                                            height: 52,
                                            decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                    colors: [
                                                      HamaColors.teal
                                                          .withOpacity(.15),
                                                      HamaColors.navy2
                                                          .withOpacity(.08)
                                                    ]),
                                                borderRadius:
                                                    BorderRadius.circular(15)),
                                            child: Icon(
                                                task
                                                            .effectiveStatus ==
                                                        'overdue'
                                                    ? Icons
                                                        .warning_amber_rounded
                                                    : Icons.task_alt_rounded,
                                                color: task.effectiveStatus ==
                                                        'overdue'
                                                    ? HamaColors.red
                                                    : HamaColors.teal),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(children: [
                                                    Expanded(
                                                        child: Text(task.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                color:
                                                                    HamaColors
                                                                        .ink))),
                                                    const SizedBox(width: 8),
                                                    StatusChip(
                                                        task.effectiveStatus)
                                                  ]),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      '${task.code} • ${tr('Deadline')}: ${shortDate(task.deadline)}',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: HamaColors
                                                              .muted)),
                                                  const SizedBox(height: 9),
                                                  if (!isMobile)
                                                    Wrap(
                                                        spacing: 14,
                                                        runSpacing: 6,
                                                        children: [
                                                          _personLine(
                                                              'Responsible',
                                                              byId[task
                                                                  .responsibleId]),
                                                          _personLine(
                                                              'Follower',
                                                              byId[task
                                                                  .followerId]),
                                                          if (urgent)
                                                            const PriorityChip(
                                                                'urgent'),
                                                        ])
                                                  else if (urgent)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                          top: 4),
                                                      child: PriorityChip(
                                                          'urgent'),
                                                    ),
                                                ]),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                              Icons.chevron_right_rounded,
                                              color: HamaColors.muted),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
    );
  }

  Widget _filter(String value, String label, IconData icon) {
    final selected = status == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        avatar: Icon(icon,
            size: 17, color: selected ? HamaColors.teal : HamaColors.muted),
        label: T(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        selected: selected,
        selectedColor: HamaColors.teal.withOpacity(.12),
        backgroundColor: Colors.white,
        side: BorderSide(
            color: selected
                ? HamaColors.teal.withOpacity(.35)
                : HamaColors.border),
        onSelected: (_) => setState(() => status = value),
      ),
    );
  }

  Widget _personLine(String label, Profile? user) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      UserAvatar(user: user ?? const AvatarData('—', null), radius: 13),
      const SizedBox(width: 5),
      Text('${tr(label)}: ${user?.fullName ?? '—'}',
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: HamaColors.ink)),
    ]);
  }

  Future<void> _newTask(BuildContext context) async {
    final users = await ref.read(usersProvider.future);
    if (!mounted) return;

    final title = TextEditingController();
    final description = TextEditingController();
    String priority = 'normal';
    String? responsible = users.isEmpty ? null : users.first.id;
    String? follower;
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
    bool evidence = false;
    bool confirmation = true;
    final quantity = TextEditingController();
    final unit = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const T('New Task'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: InputDecoration(labelText: tr('Title *')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: tr('Description')),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              InputDecoration(labelText: tr('Total quantity')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: unit,
                          decoration: InputDecoration(labelText: tr('Unit')),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: InputDecoration(labelText: tr('Priority')),
                    items: const [
                      DropdownMenuItem(
                        value: 'normal',
                        child: T('Normal'),
                      ),
                      DropdownMenuItem(
                        value: 'urgent',
                        child: T('Urgent'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => priority = value ?? priority);
                    },
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
                    onChanged: (value) {
                      setDialogState(() => responsible = value);
                    },
                  ),
                  DropdownButtonFormField<String?>(
                    value: follower,
                    decoration: InputDecoration(labelText: tr('Follower')),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: T('No follower'),
                      ),
                      ...users.map(
                        (user) => DropdownMenuItem<String?>(
                          value: user.id,
                          child: Text(user.fullName),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => follower = value);
                    },
                  ),
                  SwitchListTile(
                    value: evidence,
                    title: const T('Evidence required'),
                    onChanged: (value) {
                      setDialogState(() => evidence = value);
                    },
                  ),
                  SwitchListTile(
                    value: confirmation,
                    title: const T('Manager confirmation before completion'),
                    onChanged: (value) {
                      setDialogState(() => confirmation = value);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${tr('Deadline')}: ${dateTimeText(deadline)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.event),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: deadline,
                        );
                        if (picked != null) {
                          setDialogState(() {
                            deadline = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const T('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || responsible == null) return;

                try {
                  await ref.read(repoProvider).createTask(
                        title: title.text,
                        description: description.text,
                        priority: priority,
                        deadline: deadline,
                        responsibleId: responsible!,
                        followerId: follower,
                        evidenceRequired: evidence,
                        managerConfirmationRequired: confirmation,
                        totalQuantity: double.tryParse(quantity.text.trim()),
                        quantityUnit: unit.text,
                      );

                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(tasksProvider(widget.scope));
                  ref.invalidate(dashboardProvider);
                } catch (e) {
                  if (context.mounted) {
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
    description.dispose();
    quantity.dispose();
    unit.dispose();
  }
}
