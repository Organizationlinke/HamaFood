// import 'dart:html' as html;

// /// Opens an attachment in a browser tab while preserving the user's click
// /// gesture. The blank tab is created synchronously; the signed URL is resolved
// /// afterwards and assigned to that tab.
// Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
//   html.WindowBase? tab;
//   try {
//     // Must happen synchronously in the click handler to avoid popup blockers.
//     tab = html.window.open('about:blank', '_blank');
//   } catch (_) {
//     tab = null;
//   }

//   try {
//     final url = (await resolveUrl()).trim();
//     if (url.isEmpty) throw StateError('Empty attachment URL');

//     if (tab != null) {
//       // Preferred path: keep the application open in the original tab.
//       tab.location.href = url;
//     } else {
//       // Last-resort fallback: some browsers block _blank even when the click
//       // originated from the user. Top-level navigation is not a popup, so it
//       // remains reliable. The browser Back button returns to the app.
//       html.window.location.href = url;
//     }
//     return true;
//   } catch (_) {
//     try {
//       tab?.close();
//     } catch (_) {}
//     return false;
//   }
// }
// lib/services/attachment_opener_web.dart

// lib/services/attachment_opener_web.dart

import 'dart:html' as html;

Future<bool> openAttachment(Future<String> Function() fetchUrl) async {
  // 1. فتح نافذة فارغة فوراً بمجرد ضغط المستخدم (هذا ما يمنع الحظر في الهاتف)
  final html.WindowBase? newWindow = html.window.open('', '_blank');

  try {
    // 2. الآن ننتظر جلب الرابط من Supabase 
    final url = await fetchUrl();

    if (newWindow != null) {
      // 3. توجيه النافذة الفارغة إلى الرابط الصحيح
      newWindow.location.href = url;
    }
    return true; // تمت العملية بنجاح
  } catch (e) {
    print('Error opening attachment: $e');
    // إذا حدث خطأ، نغلق النافذة الفارغة حتى لا يراها المستخدم
    newWindow?.close();
    return false; // فشلت العملية
  }
}