# HF Team — Push Bridge Load Fix (2026-10-19)

## Symptom
The Home screen showed:

`Notifications are allowed, but the browser push subscription could not be restored: Bad state: Hama Push bridge "getPermission" failed: TypeError: Cannot read properties of undefined (reading 'apply')`

This means the Dart code reached `js_util.callMethod(...)` while `window.hamaPush` was not available. It is a bridge-loading problem, not a notification-permission problem.

## Fix
`lib/services/push_notification_service_web.dart` now:
- waits for `window.hamaPush` when the existing `push_bridge.js` tag is still loading;
- injects `push_bridge.js` if the script tag is missing;
- waits for the script load event and reports a clear error if it cannot load;
- only calls `hamaPush` after confirming the bridge exists.

The existing push permission/subscription and Supabase logic is preserved.

## Test
After extracting the package:

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

Then open the Home screen and check that the previous `undefined (reading 'apply')` message no longer appears.
