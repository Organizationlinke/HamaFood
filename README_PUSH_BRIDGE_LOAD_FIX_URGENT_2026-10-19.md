# Urgent Push Bridge Load Fix – 2026-10-19

## Exact error fixed
The browser reported:
`Cannot read properties of undefined (reading 'apply')`
for `Hama Push bridge "getPermission"`.

The previous fix checked only whether `window.hamaPush` existed. A stale/partial cached bridge could still exist without the requested method. Dart `js_util.callMethod()` then attempted to call an undefined method and produced `undefined.apply`.

## Fix
- Verify the exact requested bridge method exists before calling it.
- Remove any stale `push_bridge.js` script tag.
- Reload `push_bridge.js` with a cache-busting query string.
- Wait for the requested method to become available.
- Keep the existing notification permission/subscription/Supabase logic unchanged.

## Test
Run:
`flutter clean`
`flutter pub get`
`flutter run -d chrome`

If the browser still shows an old cached build, use a hard refresh once (Ctrl+Shift+R).
