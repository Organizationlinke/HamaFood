# HF Team – Task Tab State + Supabase Duplicate Write Guard (2026-10-20)

This patch preserves the current application and adds only two targeted fixes:

## 1. Task list tab/navigation state
- Home **Overdue Tasks** opens `/team-tasks?status=overdue`.
- Home **Ready Tasks** opens `/team-tasks?status=ready_for_completion`.
- Opening a task from any task-list tab carries the current `scope` and `status` in the task URL.
- Back from task details returns to the exact originating task list and tab.
- No task status/business logic was changed.

## 2. Duplicate Supabase writes on slow networks
`AppRepository` now has a centralized in-flight write guard.

If the same logical write is still being sent to Supabase and the user presses the button again, the second request is rejected locally with:

`A previous save is still in progress. Please wait.`

This guard covers the repository's database/RPC/storage write methods, including task creation, task status changes, messages, comments, daily updates, stages, follower notes, permissions, users, attachments, notifications, and other write actions.

The New Task dialog also disables its Create button and shows a progress indicator while the save is in progress.

The guard is intentionally scoped by logical action key, so unrelated operations can still run concurrently.

No database schema change is required.

## Build

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

For web deployment:

```bash
flutter build web
```
