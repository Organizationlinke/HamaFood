# HF Team - Mobile localStorage resilience fix - 2026-10-19

## Problem addressed
Some mobile browsers can throw:

`SecurityError: Failed to read the 'localStorage' property from 'Window': Access is denied for this document.`

That error happens during Supabase Auth initialization, before the app can use its database or notification code.

## Fix
`ResilientLocalStorage` keeps the normal Supabase browser localStorage behavior. If localStorage becomes inaccessible, it falls back to an in-memory session instead of letting `Supabase.initialize()` fail and showing the initialization error screen.

When browser storage is healthy, session persistence remains unchanged.

If the browser permanently blocks storage, the session can only remain available while the current page/app instance is alive; the user may need to sign in again after a full browser restart. This is a graceful fallback, not a replacement for browser storage.

## Also preserved
- Notification startup/re-registration changes.
- Task-list tab navigation (`?status=`) so entering/exiting a task returns to the correct task tab.
