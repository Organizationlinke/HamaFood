# HF Team – User Avatars & Copyable Text – 2026-10-14

## Changes

### 1. User photos in selection lists
- Added the user's profile photo/avatar to the recipient selection list when creating a message.
- Added the user's profile photo/avatar to Responsible and Follower dropdowns when creating a task.
- Applied the same visual treatment to the task edit screen for consistency.
- Existing avatar behavior and current application styling remain unchanged.

### 2. Copy text across the application
- Wrapped the routed application content with Flutter `SelectionArea`.
- This allows displayed text to be selected and copied without changing the existing layout or typography.
- Applies to stored/displayed text such as messages, replies/comments, task descriptions, daily work updates, notes, and other text rendered by the app.
- Text input fields keep their normal editing/copy behavior.

## Database
No SQL/database change is required for this update.

## Compatibility
- Uses the existing `avatar_url` already present in the Profile model and users query.
- No workflow, task status, message status, notification, or attachment logic was changed.
