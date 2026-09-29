# Hama Work Core Fix - 24 Sep 2026

Scope: Tasks, Messages, Notifications, with Users kept as essential support infrastructure.

## Database
Run `Hama_Work_CORE_FIX_2026-09-24.sql` AFTER the existing 3-module schema/patches.

## Flutter
Replace the `lib` folder with this package's `lib` folder.

Main fixes:
- task status enum/text mismatch fixed through `set_task_status`
- task manager confirmation columns guaranteed
- Users screen restored as an essential support screen
- Users navigation and GM user creation via `create-user` Edge Function
- Messages screen changed to master/detail so it does not issue one recipient query per message
- Recipients remain visible in a dedicated side panel on desktop
- message access/read RPC hardened

Additional stability change:
- AppScaffold notification badge no longer forces the full Dashboard/Tasks synchronization on every screen build; it derives the badge from the notifications provider.
