# HF Team FIX7 — Login history + reset-password diagnostics

## Changes
- Removed the message status chip from the message list row. The per-user status menu remains available.
- Added `login_history` database table and RPCs.
- Every successful `record_my_login()` updates `profiles.last_login_at` and inserts a history record.
- Existing app-open and app-resume audit calls therefore populate the history.
- User Settings shows last seen beside the user's name and the latest 15 login/activity entries.
- GM Users screen shows last seen and adds `Login history` beside `Reset password`.
- Improved the admin-reset-password Edge Function CORS response and client-side error message for browser XHR/CORS failures.

## Required Supabase step
Run: `database/Hama_Work_LOGIN_HISTORY_2026-10-19.sql` in Supabase SQL Editor.

Deploy the Edge Function after updating it:
`supabase functions deploy admin-reset-password`

If the function is already deployed through another CI/CD process, deploy it using that same process.
