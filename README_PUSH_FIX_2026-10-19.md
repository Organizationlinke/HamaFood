# HF Team Push Notification Fix - 2026-10-19

## What was happening
The browser permission could already be **Allowed**, but the app could still show the permission dialog again. The startup code converted any later subscription/HTTP failure into permission `default`, so the UI treated a subscription problem as a permission problem.

The app also uses `http 0.13.6`. Its web `BrowserClient` implementation is based on XMLHttpRequest. The current `http` package moved BrowserClient to Fetch in 1.3.0, which avoids the old XHR response-status path involved in the reported `xhr.status!` / null-check failure.

## Changes
- Upgrade direct `http` dependency from `^0.13.6` to `^1.3.0`.
- Preserve actual browser permission state after push setup errors.
- Never show the permission-request dialog again when browser permission is already `granted`.
- Make push subscription validation explicit before saving to Supabase.
- Report Supabase subscription-save failures clearly.
- Fix the JS bridge error handling so rejected Promises are not converted into misleading Dart values.
- Keep the existing Supabase storage, login, task, notification, and routing logic unchanged.

## Required after replacing the project
Run:

    flutter pub get

This updates pubspec.lock from http 0.13.6 to a compatible 1.x release.
