# Hama Work — All Activity Notifications + Fast Closed-App Push

## Included

### Task notifications
The SQL patch adds notifications for:
- New task (existing localized notification remains)
- Status changes (existing localized notification remains)
- Responsible/follower changes
- Priority changes
- Deadline changes
- Total quantity/unit changes
- Manager confirmation changes
- Evaluation/score changes
- Task chat replies
- Follow-up notes (create/update/delete)
- Task stages (create/update/delete)
- Daily work log (create/update/delete)
- Direct task attachments

Notifications are sent to the task creator, responsible person, and follower, excluding the person who performed the action. Each recipient gets Arabic/English according to `profiles.preferred_language`.

### Message notifications
Replies to a message notify:
- the original sender
- all recipients of the message
- excluding the person who wrote the reply

If a reply contains only an attachment, the notification says that a file was attached in the reply.

## Closed-app push speed
The Edge Function now:
- sends to all active subscriptions in parallel
- uses Web Push `urgency: high`
- uses a short `TTL: 60`
- removes expired 404/410 subscriptions without blocking other devices

Deploy the updated Edge Function after applying the SQL patch:

```bash
supabase functions deploy push-notification
```

No private VAPID key is placed in the Flutter project.

## Attachment UX
Message and Task Chat composers now show a visible attachment panel before sending:
- file name
- file size
- "Ready to send"
- upload spinner while sending
- check mark + "Uploaded" after successful upload
- remove button before sending

## Required files
- `database/Hama_Work_NOTIFICATIONS_ALL_ACTIVITY_2026-09-30.sql`
- `supabase/functions/push-notification/index.ts`
- updated `lib/screens/message_detail_screen.dart`
- updated `lib/screens/task_detail_screen.dart`
- updated `lib/services/localization.dart`

## SQL order
Run this after:
`database/Hama_Work_FINAL_FIX_2026-09-30.sql`

The new SQL is idempotent and replaces the activity triggers it owns.
