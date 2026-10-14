# HF Team — Login/Session Audit FIX5

## Change
`profiles.last_login_at` is now updated not only after a successful password login, but also whenever the running app returns to the foreground (`AppLifecycleState.resumed`).

### Expected behavior
- User opens HF Team while an existing Supabase session is active → timestamp is updated.
- User leaves HF Team in the background and opens another app, then returns to HF Team → timestamp is updated again.
- User switches browser tabs away from HF Team and returns, where Flutter reports `resumed` → timestamp is updated.
- A normal password login still records the timestamp through the existing login flow.
- Logout is not required.
- The audit write uses the existing `record_my_login()` RPC and Supabase server time (`NOW()`).
- If the audit RPC fails, the user remains logged in; the error is written to debug output instead of being silently swallowed.

## Scope
No task/message workflow, permissions, attachment, avatar, copy/selection, or UI layout logic was changed.
