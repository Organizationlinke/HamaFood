# Hama Work — Login Persistence + Real-Time Messages + WhatsApp Chat UI

This patch is based on the uploaded Hama Work task-detail build.

## What changed

### 1. Login persistence
Hama Work explicitly keeps the Supabase Auth session persisted and refreshes tokens automatically.
The user's password is **not** stored in the browser.

So after the first successful login, closing/reopening the browser or refreshing the page should keep the user signed in while the Supabase session remains valid.

Logout still ends the session.

### 2. Real-time Messages screen
The Messages screen subscribes to:
- `message_recipients` for newly received messages
- `messages` for messages created by the current user

When a relevant database event occurs, the current Riverpod providers are invalidated and the screen reloads its data automatically.

There is no 10-second polling loop for messages.

### 3. Real-time message replies
`MessageDetailScreen` subscribes to `message_comments` for the open message.
A new reply appears in the same open session without F5.

### 4. Real-time Task Chat
`TaskDetailScreen` subscribes to `task_comments` for the open task.
A new task-chat reply appears immediately without page refresh.

### 5. WhatsApp-like conversation bubbles
A shared `HamaChatBubble` widget is used for message replies and Task Chat:
- current user's messages → right side
- other users' messages → left side
- avatar + sender name
- message body
- time
- attachments remain inside the bubble area

## One-time Supabase step

Run:

`database/Hama_Work_REALTIME_MESSAGES_CHAT_2026-09-29.sql`

in the Supabase SQL Editor.

This adds the communication tables to the `supabase_realtime` publication.

## Files added/changed

Added:
- `lib/services/realtime_service.dart`
- `lib/widgets/chat_bubble.dart`
- `database/Hama_Work_REALTIME_MESSAGES_CHAT_2026-09-29.sql`

Changed:
- `lib/main.dart`
- `lib/screens/messages_screen.dart`
- `lib/screens/message_detail_screen.dart`
- `lib/screens/task_detail_screen.dart`

No old database rebuild is required.
