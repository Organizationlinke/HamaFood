# HF Team – Refresh + Completed Task Lock + Follower Write Rules

## Changes
1. Added a Refresh button to the shared app header on every screen.
   - It refreshes common Riverpod data.
   - Task detail, message detail and Trash also refresh their screen-specific Future data.
2. Completed tasks are read-only.
   - No new progress/daily achievement.
   - No new/edit/delete stages.
   - No task chat messages.
   - No task/follower-note mutations.
   - No new task attachments.
   - Existing data remains visible for audit/history.
3. Follower permissions while task is open:
   - Can add Daily Work Log entries (only while task is In Progress).
   - Can write in Task Chat.
   - Can view Progress and Stages.
   - Cannot add progress from the Progress tab.
   - Cannot add/edit stages.
   - Cannot add direct task attachments.
4. SQL adds database-level enforcement for the above rules.

## Database
Run:
`database/HF_Team_TASK_LOCK_AND_FOLLOWER_RULES_2026-10-01.sql`

## Notes
Web Push / Service Worker files were not changed.
