import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

/// Small wrapper around Supabase Realtime used by the live communication screens.
///
/// Realtime is event-driven: there is no polling/refresh timer for messages or
/// task chat. Each screen owns its channel and removes it in dispose().
class HamaRealtime {
  static RealtimeChannel taskComments({
    required String taskId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-task-comments-$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel taskFollowerNotes({
    required String taskId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-task-follower-notes-$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_follower_notes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel messageComments({
    required String messageId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-message-comments-$messageId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'message_id',
            value: messageId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel messageCommentsForUser({
    required String userId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-message-comments-unread-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_comments',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel messagesForUser({
    required String userId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-messages-$userId')
        // New recipient rows make newly received messages visible immediately.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_recipients',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        // Also listen to messages created by the current user so the sender's
        // own Messages screen updates immediately.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'created_by',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }
  static RealtimeChannel notificationsForUser({
    required String userId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('hama-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

}
