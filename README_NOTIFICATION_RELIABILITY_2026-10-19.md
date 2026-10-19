# Hama Work - Push Notification Reliability Update

## What changed
- On every authenticated app startup, Flutter checks browser notification permission.
- If permission is `granted`, the current Push Subscription is re-saved to `user_push_subscriptions` and marked active.
- If permission is `granted` but the browser no longer has a Push Subscription, a new subscription is created silently (no second permission prompt).
- The web Push bridge calls `ServiceWorkerRegistration.update()` on startup so GitHub Pages deployments can refresh the service worker without requiring the user to re-enable notifications.
- If permission is `default`, the existing startup dialog asks the user to allow notifications. If the user closes it, it will be offered again on the next app opening.
- If permission is `denied`, the app explains that notifications are blocked and tells the user to enable them from browser/site settings.

## No database schema change
The update only changes Flutter/web push registration behavior. It does not change notification generation, the Supabase webhook, or the push Edge Function.
