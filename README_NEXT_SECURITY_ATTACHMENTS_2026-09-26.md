# Hama Work — Security, Permissions & Attachments Upgrade

## Included
- Delete task returns to previous screen after successful soft-delete.
- Explicit permissions for Start, Request Completion, Confirm Completion, Reopen, Evaluate and Cancel.
- Reopen/Evaluate are no longer role-only actions; they require their explicit permission (GM always has it).
- Team Tasks redesigned with responsible/follower names and avatars plus professional status filters.
- Task and Message attachments: Word, Excel, PDF and images.
- Private Supabase `attachments` bucket with per-user upload paths.
- Attachment metadata stores uploader and timestamp; UI displays uploader avatar/name/date.
- Attachments open through a short-lived signed URL.
- Permissions screen now shows effective permissions and marks GM-only permissions.

## SQL
Run only:
`database/Hama_Work_NEXT_SECURITY_ATTACHMENTS_PATCH_2026-09-26.sql`

Run it after the currently working Hama Work patches. Do not rebuild the database from old core scripts.

## Flutter dependencies
Add:
```yaml
file_picker: ^8.1.7
url_launcher: ^6.3.1
```
Then:
```powershell
flutter pub get
flutter clean
flutter run -d chrome
```

## Attachment behavior
- Task attachments are added from Task > Task Overview > Attachments.
- Message attachments are added from Message Detail > Attachments.
- Supported: `.doc`, `.docx`, `.xls`, `.xlsx`, `.pdf`, `.jpg`, `.jpeg`, `.png`, `.webp`.
- Files are stored in Supabase Storage bucket `attachments`.
