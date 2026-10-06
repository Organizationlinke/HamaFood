# Hama Work - Attachment Open Fix

## المشكلة
نفس المرفق كان يفتح عند مستخدم ولا يفتح عند مستخدم آخر، خصوصًا على Web. الكود السابق كان ينتظر إنشاء Signed URL ثم يستدعي `launchUrl(..., webOnlyWindowName: '_blank')`. بعض المتصفحات تعتبر فتح النافذة بعد `await` Popup غير مرتبط مباشرة بضغطة المستخدم وتمنعه.

كما أن Flutter كان ينشئ Signed URL مباشرة من Storage رغم وجود RPC مخصص أصلًا للتحقق من صلاحية الوصول للمرفق عبر الأب الحقيقي للمرفق.

## الحل
### 1. فتح Web بدون انتظار قبل إنشاء الـ Tab
`lib/services/attachment_opener_web.dart`
- يفتح `about:blank` مباشرة داخل حدث الضغط.
- بعد الحصول على Signed URL يضع الرابط في نفس الـ Tab المفتوح.
- إذا منع المتصفح الـ Popup يرجع `false` ويظهر للمستخدم تنبيه واضح.

### 2. Android / iOS / Desktop
`lib/services/attachment_opener_stub.dart`
- يستخدم `LaunchMode.externalApplication`.
- يعيد `false` بدل كسر الشاشة عند فشل الفتح.

### 3. توحيد إنشاء Signed URL
`Repository.attachmentUrl()` أصبح يستدعي:
`attachment_signed_url(p_attachment_id)`
بدل `storage.createSignedUrl()` المباشر.

### 4. كل المرفقات تستخدم نفس الطريقة
- Message attachments
- Message comment attachments
- Task attachments
- Task comment attachments
- Daily update attachments

## SQL
نفذ:
`database/Hama_Work_ATTACHMENT_OPEN_FIX_2026-10-06.sql`

الـ SQL يعيد إنشاء `attachment_signed_url(UUID)` ليدعم كل أنواع المرفقات الحالية.

## ملاحظة
لا يوجد تغيير في Workflow أو حالات المهام أو حالات الرسائل.
