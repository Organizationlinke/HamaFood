import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

class HamaChatBubble extends StatelessWidget {
  final bool isMine;
  final String name;
  final String? avatarUrl;
  final String content;
  final DateTime createdAt;
  final Widget? attachments;

  const HamaChatBubble({
    super.key,
    required this.isMine,
    required this.name,
    required this.avatarUrl,
    required this.content,
    required this.createdAt,
    this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
      decoration: BoxDecoration(
        color: isMine ? HamaColors.teal.withOpacity(.10) : HamaColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 5),
          bottomRight: Radius.circular(isMine ? 5 : 18),
        ),
        border: Border.all(
          color: isMine
              ? HamaColors.teal.withOpacity(.22)
              : HamaColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMine) ...[
                UserAvatar(
                  user: AvatarData(name, avatarUrl),
                  radius: 15,
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  isMine ? 'You' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isMine ? HamaColors.teal : HamaColors.navy,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 7),
                UserAvatar(
                  user: AvatarData(name, avatarUrl),
                  radius: 15,
                ),
              ],
            ],
          ),
          if (content.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                content,
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ),
          ],
          if (attachments != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: attachments!,
            ),
          ],
          const SizedBox(height: 5),
          Text(
            _time(createdAt),
            style: const TextStyle(
              fontSize: 10,
              color: HamaColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  String _time(DateTime value) {
    final d = egyptLocal(value);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${dayLabel(value)} $h:$m';
  }
}
