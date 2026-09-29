# Hama Work – Admin & Profile Upgrade

This package addresses the requested items:

1. Task actions now refresh the actual task after Start / Request completion / Confirm / Cancel / Reopen / Evaluate.
2. Task detail shows Responsible and Follower names.
3. GM-only Task Edit and Delete, enforced by server-side RPCs.
4. User can change their own password from Settings.
5. GM can reset a user's password from Users.
6. User can upload a profile photo.
7. GM gets a Permissions screen with per-user permission switches.

## Database
Run this SQL in Supabase SQL Editor AFTER the existing Core + Progress patches:

`database/Hama_Work_ADMIN_PROFILE_PERMISSIONS_PATCH.sql`

Do not rerun the old full database build.

## Flutter dependency
Add to the existing `pubspec.yaml`:

```yaml
file_picker: ^8.1.7
```

Then:

```powershell
flutter pub get
```

## Edge Function
Deploy the included function:

```powershell
supabase functions deploy admin-reset-password
```

The function uses the standard Supabase environment variables, including the service-role key server-side. Never put the service-role key in Flutter.

## Flutter refresh
After replacing `lib`:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```

## Notes
- GM is treated as the System Administrator for the requested task edit/delete and password-reset operations.
- The permission matrix is stored in `user_permissions`. GM automatically has all permissions.
- The existing business rules for task status and manager confirmation remain in force.
