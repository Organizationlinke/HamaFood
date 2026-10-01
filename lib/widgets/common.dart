import 'package:flutter/material.dart';
import '../services/localization.dart';
import '../theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(strokeWidth: 3));
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(color: HamaColors.teal.withOpacity(.08), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: HamaColors.teal),
          ),
          const SizedBox(height: 16),
          T(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: HamaColors.ink)),
        ],
      ),
    ),
  );
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Text(tr(_label(status)), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
  (Color, Color) _colors(String s) {
    switch (s) {
      case 'completed': return (HamaColors.green.withOpacity(.12), HamaColors.green);
      case 'in_progress': return (HamaColors.teal.withOpacity(.12), HamaColors.teal);
      case 'ready_for_completion': return (HamaColors.orange.withOpacity(.14), HamaColors.orange);
      case 'awaiting_approval': return (HamaColors.navy2.withOpacity(.12), HamaColors.navy2);
      case 'overdue': return (HamaColors.red.withOpacity(.12), HamaColors.red);
      case 'cancelled': return (Colors.grey.withOpacity(.12), Colors.grey.shade700);
      case 'deleted': return (HamaColors.red.withOpacity(.10), HamaColors.red);
      default: return (HamaColors.navy2.withOpacity(.08), HamaColors.navy2);
    }
  }
  String _label(String s) {
    switch (s) {
      case 'not_started': return 'Not Started';
      case 'in_progress': return 'In Progress';
      case 'ready_for_completion': return 'Ready for Completion';
      case 'completed': return 'Completed';
      case 'overdue': return 'Overdue';
      case 'cancelled': return 'Cancelled';
      case 'deleted': return 'Deleted';
      default: return s;
    }
  }
}

class PriorityChip extends StatelessWidget {
  final String priority;
  const PriorityChip(this.priority, {super.key});
  @override
  Widget build(BuildContext context) {
    final urgent = priority == 'urgent';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? HamaColors.red : HamaColors.navy2).withOpacity(.09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(tr(urgent ? 'Urgent' : 'Normal'), style: TextStyle(color: urgent ? HamaColors.red : HamaColors.navy2, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}


DateTime egyptLocal(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year;

  // Egypt DST: from the last Friday of April through the last Thursday of October.
  // Using UTC boundaries keeps TIMESTAMPTZ values deterministic regardless of
  // the device/browser timezone.
  DateTime lastWeekdayOfMonth(int y, int month, int weekday) {
    final last = DateTime.utc(y, month + 1, 0);
    final delta = (last.weekday - weekday) % 7;
    return DateTime.utc(y, month, last.day - delta);
  }

  final lastFridayApril = lastWeekdayOfMonth(year, 4, DateTime.friday);
  final lastThursdayOctober = lastWeekdayOfMonth(year, 10, DateTime.thursday);
  final dstStart = DateTime.utc(year, 4, lastFridayApril.day, 0);
  final dstEnd = DateTime.utc(year, 10, lastThursdayOctober.day, 0);
  final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return utc.add(Duration(hours: isDst ? 3 : 2));
}

String dayLabel(DateTime? value) {
  if (value == null) return '—';
  final d = egyptLocal(value);
  final now = egyptLocal(DateTime.now().toUtc());
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return tr('Today');
  if (diff == 1) return tr('Yesterday');
  return '${d.day}/${d.month}/${d.year}';
}

String shortDate(DateTime? value) {
  if (value == null) return '—';
  final d = egyptLocal(value);
  return '${d.day}/${d.month}/${d.year}';
}

String dateTimeText(DateTime? value) {
  if (value == null) return '—';
  final d = egyptLocal(value);
  return '${dayLabel(value)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}


class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? retry;
  const ErrorView(this.error, {super.key, this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: HamaColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 46, color: HamaColors.red),
            const SizedBox(height: 10),
            Text('$error', textAlign: TextAlign.center),
            if (retry != null) ...[const SizedBox(height: 14), OutlinedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded), label: const T('Retry'))],
          ],
        ),
      ),
    ),
  );
}


class UserAvatar extends StatelessWidget {
  final ProfileLike user;
  final double radius;
  final bool clickable;
  const UserAvatar({super.key, required this.user, this.radius = 20, this.clickable = true});

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: HamaColors.teal.withOpacity(.12),
      backgroundImage: user.avatarUrl == null || user.avatarUrl!.isEmpty ? null : NetworkImage(user.avatarUrl!),
      child: user.avatarUrl == null || user.avatarUrl!.isEmpty
          ? Text(user.fullName.isEmpty ? 'U' : user.fullName.substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: HamaColors.teal, fontSize: radius * .72))
          : null,
    );
    if (!clickable || user.avatarUrl == null || user.avatarUrl!.isEmpty) return avatar;
    return InkWell(
      borderRadius: BorderRadius.circular(radius + 4),
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(
                minScale: .8,
                maxScale: 3,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 30)]),
                  child: ClipOval(child: Image.network(user.avatarUrl!, fit: BoxFit.cover)),
                ),
              ),
              Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      ),
      child: avatar,
    );
  }
}

// Small structural interface so UserAvatar can be reused with Profile and other user-like records.
class AvatarData implements ProfileLike {
  @override final String fullName;
  @override final String? avatarUrl;
  const AvatarData(this.fullName, this.avatarUrl);
}

abstract class ProfileLike {
  String get fullName;
  String? get avatarUrl;
}
