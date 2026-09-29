import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import '../theme.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});
  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  late Future<List<Task>> _future;
  @override
  void initState() { super.initState(); _future = ref.read(repoProvider).trashTasks(); }
  void _reload() => setState(() => _future = ref.read(repoProvider).trashTasks());

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Trash',
      body: FutureBuilder<List<Task>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return snap.hasError ? ErrorView(snap.error!, retry: _reload) : const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) return const EmptyView('Trash is empty', icon: Icons.delete_sweep_outlined);
          return RefreshIndicator(
            onRefresh: () async { _reload(); await _future; },
            child: ListView.separated(
              padding: const EdgeInsets.all(20), itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final task = items[i];
                return Card(child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: HamaColors.red.withOpacity(.09), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.delete_outline, color: HamaColors.red)),
                  title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${task.code} • ${tr('Deleted')}: ${shortDate(task.deletedAt)}'), const SizedBox(height: 6), StatusChip('deleted')]),
                  trailing: IconButton(tooltip: tr('Restore'), icon: const Icon(Icons.restore_rounded, color: HamaColors.teal), onPressed: () async { try { await ref.read(repoProvider).restoreTask(task.id); _reload(); ref.invalidate(tasksProvider('team')); ref.invalidate(tasksProvider('my')); ref.invalidate(dashboardProvider); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }),
                ));
              },
            ),
          );
        },
      ),
    );
  }
}
