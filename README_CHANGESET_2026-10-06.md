# Hama Work – Independent Overdue + Per-User Message Status

## Changes

### Tasks
- `tasks.status` remains the real workflow status.
- Overdue is derived from `deadline < now` while status is not `completed` or `cancelled`.
- The overdue sync function no longer writes `status='overdue'`.
- Existing overdue notifications remain supported.
- Flutter task lists show the real status chip plus a separate `متأخرة` indicator.
- The Overdue filter uses `task.isOverdue` independently of task status.

### Messages
- Added `message_recipients.status` with values:
  - `not_started`
  - `in_progress`
  - `completed`
- Status belongs to each recipient/user, not the message globally.
- Added RPC `set_message_recipient_status(message_id,status)`.
- Added RPC `get_my_message_status_counts()`.
- `get_visible_messages()` now returns `my_status`.
- Messages screen has 3 tabs with live counters:
  - لم يتم البدء
  - تحت التنفيذ
  - منتهية
- Each message has a status menu for the current user.
- Existing read/unread and comment-unread logic stays separate from workflow status.
- Realtime already listens to `message_recipients`, so status changes trigger message/counter refresh.

## SQL
Run:
`database/Hama_Work_MESSAGE_STATUS_AND_OVERDUE_INDEPENDENT_2026-10-06.sql`

## Flutter files changed
- `lib/models/models.dart`
- `lib/providers/providers.dart`
- `lib/services/repository.dart`
- `lib/screens/messages_screen.dart`
- `lib/screens/tasks_screen.dart`
- `lib/screens/task_detail_screen.dart`


## FIX 1 — Message status legacy/sender rows (2026-10-06)

Fixed the reported `PostgrestException: Message recipient not found`.
The previous patch incorrectly treated a missing `message_recipients` row as `completed` for sender/GM.
The corrected logic uses `not_started` as the default and creates the user's personal status row when the user is authorized to view the message.

This fixes:
- New messages appearing in `منتهية` immediately.
- Legacy messages appearing as `منتهية` when no personal recipient-status row exists.
- Changing those messages back to `لم يتم البدء` / `تحت التنفيذ` failing with P0001.
