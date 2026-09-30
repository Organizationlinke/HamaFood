# Hama Work — Fix 2026-09-30: Push Toggle Persistence + Chat Screen Shake

## Fixes
- Browser notification toggle now uses the user's active push subscription in Supabase as the persisted preference and verifies the browser subscription. If the user had already enabled push and the browser subscription disappeared after a reload/service-worker restart, the app attempts to recreate it without asking for permission again. Turning the toggle OFF marks the subscription inactive, so it is not silently re-enabled.
- Message detail caches its Message future instead of creating a new Future on every build. This prevents the whole screen from entering LoadingView repeatedly during composer setState calls, file selection, upload progress, and send.
- Task detail caches the task stages future as well as the task future. This prevents full-screen loading/rebuild flicker during Task Chat sends and other setState operations.

## Validation
Brace/parenthesis balance was checked for the modified Dart files. Flutter analyze/build was not available in this environment.
