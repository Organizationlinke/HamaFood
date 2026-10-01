# Hama Work — Task Workflow & Mobile UX Upgrade — 2026-10-01

Implemented in this patch:

1. **Follower review before completion**
   - The follower cannot Start or Request Completion.
   - The responsible person (or manager/GM) can Start and Request Completion.
   - After `Ready for Completion`, if a follower exists, only that follower gets the **Follow-up completed / تمت المتابعة** action.
   - The follower-only action completes the task.
   - Manager confirmation remains the fallback only for tasks without a follower.
   - A dedicated notification is sent to the follower when review is required.

2. **Progress gate**
   - Daily achievement/progress entries can only be recorded while the task status is `In Progress`.
   - The database RLS policy also enforces this rule.

3. **Team Tasks filters**
   - `All` is now the last filter button.

4. **Mobile layout**
   - On phones, hide the top New Task action and the duplicate inline New Task button; keep the floating action button.
   - Hide the Tasks section header/subtitle on phones.
   - Hide responsible/follower chips in the task header after the user scrolls.
   - Hide Task Overview / Progress / Stages / Daily Work / Chat section headers on phones.
   - Hide explanatory progress text and secondary headings on phones.
   - Hide responsible/follower lines inside team-task cards on phones to save vertical space.

## Database migration
Run:
`database/Hama_Work_TASK_FOLLOWER_REVIEW_MOBILE_2026-10-01.sql`

## Notes
The existing Web Push implementation is not modified by this patch.
