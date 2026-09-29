# Hama Work — Real-Time In-App Notifications + Closed-App Push Roadmap

## Implemented in this patch

### In-app notifications
- Removed the old 10-second polling timer from Notifications.
- Added Supabase Realtime subscription to `notifications` filtered by `user_id`.
- New notifications invalidate the notifications and dashboard providers immediately.
- The notification bell/unread indicator in the global AppScaffold also listens in real time, so it can update while the user is on Tasks, Messages, Dashboard, Settings, etc.
- Channel is removed when the screen/scaffold is disposed.

### Supabase one-time step

Run:
`database/Hama_Work_NOTIFICATIONS_REALTIME_2026-09-29.sql`

This adds `public.notifications` to the `supabase_realtime` publication.

## Important distinction: app open vs app closed

Supabase Realtime works while the web application/browser session is running.

If the browser tab/window is completely closed, Realtime cannot execute JavaScript in that closed page, so it cannot by itself show a desktop/browser push notification.

For notifications while Hama Work is closed, the next layer is **Web Push / Firebase Cloud Messaging (FCM)** (or a service such as OneSignal).

Recommended Hama Work architecture:

1. Supabase inserts a row into `public.notifications`.
2. A Supabase Database Webhook/Edge Function detects the new notification.
3. The Edge Function sends a Web Push/FCM message to the user's registered browser/device token.
4. The browser's service worker displays the notification even when Hama Work is not open.
5. Clicking the notification opens the correct Hama Work task/message route.

For a production deployment, store each user's push subscription/token in a dedicated table such as:
`user_push_subscriptions`
with user_id, endpoint/token, platform, browser/device metadata, created_at, last_seen_at, and active.

The app should ask the user for notification permission from Settings rather than unexpectedly prompting on first load.

This is a separate feature from Supabase Realtime and should be implemented as Phase 2 so it does not disturb the current stable application.

## Security notes
- Never store passwords for push notifications.
- Push tokens/subscriptions are not passwords, but should still be treated as private credentials.
- The Edge Function must use server-side credentials and must never expose a Supabase service-role key or FCM server credential in Flutter Web.
