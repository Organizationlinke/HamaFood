# Hama Work – Next Upgrade

This package addresses the latest requested fixes:

1. Working Back button with route fallback for Task/Message details.
2. Task deletion is now **soft delete**: the task is hidden from normal lists and appears in **Trash** for the GM. Trash supports restore; there is no permanent-delete button in the UI.
3. Fixed PostgreSQL enum mismatch when editing task priority by casting `p_priority` to `public.priority_level`.
4. Added `tasks.cancel` permission. Cancel is denied unless GM or explicitly enabled for the user; server-side RPC enforces it too.
5. User avatars are shown next to user names across the app where user identity is displayed.
6. Clicking an avatar opens a large, clear image with a close button.
7. Messages screen and Task Detail tabs received a consistent professional section/header treatment.
8. Sender/recipient/comment avatar data is supported.
9. Added Trash screen and GM navigation item.

## Database
Run only:

`database/Hama_Work_ADMIN_PROFILE_PERMISSIONS_PATCH.sql`

It is intended to run after the current core/progress patches already used by the project.

## Flutter
Replace the project's `lib` with this package's `lib`.

If `file_picker` is not already in your project's pubspec, add the dependency listed in `PUBSPEC_ADDITIONS.txt`.

Then:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```

No old database rebuild script should be rerun.
