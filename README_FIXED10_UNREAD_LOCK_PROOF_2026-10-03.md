# HF Team FIXED10 — Unread Chats, Attachment Lock, Proof Note

## Changes
1. Unread reply counts:
   - Task Chat tab shows unread reply count.
   - Messages drawer shows number of message conversations with unread replies.
   - Each external message shows unread reply count like WhatsApp.
   - Opening the task Chat tab or message marks replies as read.
2. Task filters show counts for every status; All remains last.
3. Daily Work Log attachments are available only while creating the log. After Save, the record is finalized/locked and no new attachment can be uploaded.
4. Admin approval is visibly enabled and mandatory for every new task; it is not an optional switch.
5. Message Type is removed from the New Message form; messages are stored internally as `information`.
6. Completion proof text is now shown in Task Overview when `completion_proof_note` exists. Completion-proof attachments remain in Task Attachments.
7. Follower Daily Work Log write access remains allowed while the task is in progress; Progress and Stages remain read-only for the follower.

## Database
Run:
`database/HF_Team_UNREAD_CHAT_AND_ATTACHMENT_LOCK_2026-10-03.sql`

Run it after the existing HF Team task/security patches. It is idempotent.

## Web Push
No Web Push / Service Worker logic was changed.
