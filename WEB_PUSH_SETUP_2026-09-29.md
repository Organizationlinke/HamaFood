# Hama Work — Web Push setup

The application-side implementation is included. Three external configuration steps
are required because the browser and Supabase must know the VAPID keys and the
database must call the Edge Function.

## 1) Generate a VAPID key pair

On a machine with Node.js and the `web-push` package:

```bash
npx web-push generate-vapid-keys
```

Keep the **private** key secret.

You will have:
- VAPID public key → used in the Flutter Web build
- VAPID private key → Supabase Edge Function secret

## 2) Run the SQL

Run:

`database/Hama_Work_WEB_PUSH_2026-09-29.sql`

This creates `user_push_subscriptions` with RLS.

## 3) Deploy the Edge Function

Deploy:

`supabase/functions/push-notification/index.ts`

The function uses `npm:web-push`.

Set these Supabase Edge Function secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `HAMA_VAPID_PUBLIC_KEY`
- `HAMA_VAPID_PRIVATE_KEY`
- `HAMA_VAPID_SUBJECT` (example: `mailto:admin@hamaholding.com`)
- `HAMA_WEBHOOK_SECRET` (generate a random long secret)

Never put the service-role key or VAPID private key in Flutter/GitHub Pages.

## 4) Create the Database Webhook

In Supabase Dashboard, create a Database Webhook for:

- schema: `public`
- table: `notifications`
- event: `INSERT`
- target: Edge Function `push-notification`

Add HTTP header:

`x-hama-webhook-secret: <same HAMA_WEBHOOK_SECRET>`

The webhook sends the inserted notification row to the Edge Function.
The Edge Function finds the recipient's active browser subscriptions and sends
Web Push.

## 5) Add the web bridge

The package contains:

- `web/push_bridge.js`
- `web/push_service_worker.js`

Add this script to `web/index.html` before Flutter's bootstrap script:

```html
<script src="push_bridge.js"></script>
```

The service worker file must remain at the web root.

## 6) GitHub Actions / Flutter build

Add repository secret:

`HAMA_VAPID_PUBLIC_KEY`

Then add this compile-time define to the Flutter web build:

```bash
--dart-define="HAMA_VAPID_PUBLIC_KEY=$HAMA_VAPID_PUBLIC_KEY"
```

For local VS Code `.vscode/hama_work.env.json`, add:

```json
"HAMA_VAPID_PUBLIC_KEY": "YOUR_VAPID_PUBLIC_KEY"
```

Do not add the private key there.

## 7) User flow

Settings → Browser notifications → ON.

The browser asks for permission once.

After permission:
- a push subscription is stored for the logged-in user;
- when a new `notifications` row is inserted, Supabase calls the Edge Function;
- the Edge Function sends the notification even when Hama Work is closed;
- clicking the notification opens the task/message when the notification has a target.

## GitHub Pages note

The service worker builds URLs from its own scope and uses Flutter hash routes.
That keeps links working under repository paths such as:

`https://<org>.github.io/HamaFood/`

No custom domain is required.

## Browser support

This uses standard Web Push APIs. Support depends on the browser/device and
permission settings. Desktop Chrome/Edge/Firefox are the primary target.
Safari support varies by platform and requires its own Web Push behavior.
