# HF Team — Login Audit FIX6 — 2026-10-17

## Requested behavior
`last_login_at` must update in two cases:

1. The user taps the app icon and enters the authenticated home page, including when Supabase restores an existing session without a new password login.
2. The user leaves HF Team in the background / switches to another app or browser tab and later returns; `AppLifecycleState.resumed` updates the timestamp.

## Implementation
- Kept the existing `record_my_login()` RPC and server-side `NOW()` timestamp.
- Added a one-time `_recordHomeEntryOnce()` call after the authenticated profile/home shell is ready.
- Kept resume handling through `didChangeAppLifecycleState`.
- Added a small in-flight guard so startup/home-entry and resume callbacks cannot issue overlapping audit writes.
- On sign-out, the home-entry flag resets so the next authenticated session records again.
- User login is never blocked if the audit RPC fails; the failure is logged in debug output.
- `usersProvider` is invalidated after a successful audit write so an administrator can see the new time without restarting the app.

## Important
This is still an activity/session timestamp, not a password-login history. It intentionally records the moment the authenticated app session becomes active.
