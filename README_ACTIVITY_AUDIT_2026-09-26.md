# Hama Work — Activity / Notifications / Professional Lists Upgrade

## Included
- Professional redesign for Notifications, Progress & Daily Achievement, Task Stages, and Daily Work Log.
- Precise notifications include the actor name and action (e.g. user started a task / recorded quantity / requested completion).
- Notification actor avatar is displayed.
- Task header shows Responsible and Follower with avatars.
- Task overview shows Created By and Created At.
- Daily achievements show recorder name, avatar, work date and registration timestamp.
- Task stages show creator name, avatar and creation timestamp.
- Task replies and message replies show avatar, name and exact timestamp in a professional card layout.

## Database patch
Run:
`database/Hama_Work_ACTIVITY_AUDIT_NOTIFICATIONS_PATCH_2026-09-26.sql`

Run this AFTER the existing core/admin/progress patches. It is safe to re-run.

## Flutter
Replace the `lib` folder with the one in this package, then:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```

No old core database build scripts need to be rerun.

## Runtime note
Flutter/Dart runtime is not available in the build environment used to assemble this package, so runtime execution/analyze was not claimed here.
