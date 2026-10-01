# HF Team – Task Admin Approval & Departments

## Task workflow

1. **Start** — responsible person only.
2. **Request completion** — responsible person only.
3. **Follow-up completed (تمت المتابعة)** — assigned follower only. This no longer completes the task; it moves the task to `awaiting_approval`.
4. **Approve operation (اعتماد العملية)** — General Manager / Admin only. This changes the task to `completed`.

If a task has no follower, the General Manager can approve it directly after the responsible person requests completion.

## Security

The database RPCs enforce the same workflow; hiding buttons in Flutter is not the only protection.

## Departments added to New User

- المخازن
- تخطيط
- قانونية
- مالية
- أمن
- مبيعات محلية
- مبيعات تصدير
- IT
- HR

Existing departments remain available.

## Task list

- Default filter is `not_started`.
- `All` remains the last filter button.
- Added `Awaiting Approval` status filter.

## Branding

User-facing app name is **HF Team**.
