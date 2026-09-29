# Hama Work – Daily/Reply Attachments & Completion Proof

This patch preserves the current project and adds only the requested changes:

1. Deleted tasks: existing task notifications are removed, and notification reads exclude deleted-task notifications.
2. Progress tab is hidden for tasks without a total quantity.
3. Task Stages tab is hidden when the task has no stages.
4. Daily Work Log supports attachments linked to each daily update.
5. Task Chat/message replies support attachments linked to the individual reply.
6. If Evidence Required = Yes, Request Completion requires either a written proof note or an attachment explicitly marked as completion proof. Enforcement is also in PostgreSQL.

Run only the new SQL patch after the currently working database patches:
`database/Hama_Work_SECURITY_ATTACHMENTS_DAILY_REPLY_PROOF_PATCH_2026-09-29.sql`

Then replace `lib` and run:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```
