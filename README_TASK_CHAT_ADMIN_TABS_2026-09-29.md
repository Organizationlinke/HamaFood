# Hama Work – Task Detail Follow-up

This update preserves the current app and adds only the requested task-detail behavior:

- GM sees all task tabs, including Progress and Stages even when the task has no quantity or stages.
- Regular users continue to see Progress only when a total quantity exists.
- Regular users continue to see Stages only when stages exist.
- Daily Work Log has an Add button for users allowed to record work.
- Daily Work Log creation supports attachments in the same dialog.
- Task Chat comments support attachments.
- Task-chat attachments use `task_comment_id` and are protected by RLS.

Run the SQL follow-up after the previously working fixed attachment patch:
`database/Hama_Work_TASK_CHAT_ATTACHMENTS_AND_ADMIN_TABS_PATCH_2026-09-29.sql`

Then replace `lib`, run `flutter clean`, `flutter pub get`, and `flutter run -d chrome`.
