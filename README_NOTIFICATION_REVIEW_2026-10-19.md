# Hama Work — Notification Review and Startup Permission Fix — 2026-10-19

## Scope
Reviewed the current Flutter + Supabase Web Push implementation directly. This is a code review of the current project, not a comparison with an older release.

## Findings

1. The notification permission flow was only reachable from Settings. The app did not check/request notification permission when an authenticated user entered HF Team.
2. `isEnabled()` depended on an active database subscription row before attempting to repair a browser subscription. This could leave a phone/browser with granted permission but no usable active subscription.
3. The browser bridge did not expose `Notification.permission`, so the Flutter layer could not distinguish `default` (not decided) from `denied` (blocked).
4. The Web Push Edge Function requires a Supabase server secret and a webhook secret. The function now accepts the project's existing `HAMA_SUPABASE_SECRET_KEY` or the built-in `SUPABASE_SECRET_KEYS` default key, without exposing either to Flutter.
5. The Database Webhook that sends `notifications` INSERTs to `push-notification` is an external Supabase configuration and is not represented in Flutter source code. It must still exist and use `x-hama-webhook-secret` matching `HAMA_WEBHOOK_SECRET`.

## Implemented Flutter behavior

- After the authenticated Home shell is ready, HF Team checks browser notification permission.
- If permission is `default`, an in-app dialog appears immediately and asks the user to allow notifications.
- The browser's native permission prompt is opened only after the user taps `Allow notifications`.
- If the user closes/dismisses the HF Team dialog, it will be shown again on the next application launch.
- If the browser permission is already `granted`, the app automatically repairs/recreates the Web Push subscription and saves it to `user_push_subscriptions`.
- If permission is `denied`, HF Team shows a clear message explaining that browser/site notification settings must be changed. Browsers generally do not allow a web page to programmatically override a previously denied permission.
- Settings continues to contain the notification switch.

## Supabase delivery path still required

`notifications` INSERT -> Supabase Database Webhook -> `push-notification` Edge Function -> active `user_push_subscriptions` -> Web Push -> service worker.

The Edge Function already deactivates subscriptions returning HTTP 404/410, so stale phone subscriptions can be cleaned automatically.
