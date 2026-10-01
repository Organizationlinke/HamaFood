# Hama Work – Phase 2 Fixes

This package is based on `WEB_PUSH_SETUP_2026-09-29(1).zip` and includes the requested fixes.

## Included fixes

1. Follower role
   - Dedicated Follower Notes tab.
   - Follower, GM and Manager can add notes.
   - Responsible user can view but cannot add.
   - Author can edit/delete own note.
   - GM/Manager can manage notes.
   - Realtime refresh for follower notes.

2. Notification language
   - Notification titles are generated using each recipient's `profiles.preferred_language`.
   - Arabic and English titles are supported.
   - Task/status/daily-progress/message/deadline/overdue notification paths are covered.

3. WhatsApp-style composer
   - Message detail: text box + attachment + send at bottom.
   - Task Chat: text box + attachment + send at bottom.
   - Existing attachment upload flow is preserved.

4. Daily Work Log
   - Quantity is optional.
   - Multiple records can be added on the same day.
   - Progress calculations treat missing quantity as zero.
   - A blank record with no note, quantity or attachment is rejected by the UI.

5. Selected users
   - Full-screen recipient list was removed from the new-message dialog.
   - Compact selected-user chips are shown.
   - User selection opens a searchable bottom sheet.
   - This leaves the message composer area usable on mobile.

6. Egypt date/time
   - `TIMESTAMPTZ` remains the database storage type.
   - UI converts timestamps to `Africa/Cairo` rules.
   - Chat timestamps now show Today / Yesterday / date + time.
   - The helper handles Egypt summer/winter offset rules.

## Database

Run:

`Hama_Work_Phase2_Phase3_FixPack.sql`

after the current Hama Work database patches.

The SQL is idempotent for the objects it creates/replaces.


## FINAL FIX 2026-09-30

Run `database/Hama_Work_FINAL_FIX_2026-09-30.sql` in Supabase SQL Editor. It localizes notification bodies per recipient language, removes the old unique-day restriction from daily achievements, and makes daily quantity nullable.
