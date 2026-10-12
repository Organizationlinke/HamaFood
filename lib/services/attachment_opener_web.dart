// // // import 'dart:html' as html;

// // // /// Opens an attachment in a browser tab while preserving the user's click
// // // /// gesture. The blank tab is created synchronously; the signed URL is resolved
// // // /// afterwards and assigned to that tab.
// // // Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
// // //   html.WindowBase? tab;
// // //   try {
// // //     // Must happen synchronously in the click handler to avoid popup blockers.
// // //     tab = html.window.open('about:blank', '_blank');
// // //   } catch (_) {
// // //     tab = null;
// // //   }

// // //   try {
// // //     final url = (await resolveUrl()).trim();
// // //     if (url.isEmpty) throw StateError('Empty attachment URL');

// // //     if (tab != null) {
// // //       // Preferred path: keep the application open in the original tab.
// // //       tab.location.href = url;
// // //     } else {
// // //       // Last-resort fallback: some browsers block _blank even when the click
// // //       // originated from the user. Top-level navigation is not a popup, so it
// // //       // remains reliable. The browser Back button returns to the app.
// // //       html.window.location.href = url;
// // //     }
// // //     return true;
// // //   } catch (_) {
// // //     try {
// // //       tab?.close();
// // //     } catch (_) {}
// // //     return false;
// // //   }
// // // }
// // // lib/services/attachment_opener_web.dart

// // // lib/services/attachment_opener_web.dart

// // import 'dart:html' as html;

// // Future<bool> openAttachment(Future<String> Function() fetchUrl) async {
// //   // 1. فتح نافذة فارغة فوراً بمجرد ضغط المستخدم (هذا ما يمنع الحظر في الهاتف)
// //   final html.WindowBase? newWindow = html.window.open('', '_blank');

// //   try {
// //     // 2. الآن ننتظر جلب الرابط من Supabase
// //     final url = await fetchUrl();

// //     if (newWindow != null) {
// //       // 3. توجيه النافذة الفارغة إلى الرابط الصحيح
// //       newWindow.location.href = url;
// //     }
// //     return true; // تمت العملية بنجاح
// //   } catch (e) {
// //     print('Error opening attachment: $e');
// //     // إذا حدث خطأ، نغلق النافذة الفارغة حتى لا يراها المستخدم
// //     newWindow?.close();
// //     return false; // فشلت العملية
// //   }
// // }
// // lib/services/attachment_opener_web.dart

// import 'dart:html' as html;

// Future<bool> openAttachment(Future<String> Function() fetchUrl) async {
//   html.WindowBase? newWindow;

//   try {
//     // 1. محاولة فتح نافذة وهمية فوراً (متزامنة مع ضغطة المستخدم)
//     newWindow = html.window.open('', '_blank');
//   } catch (_) {
//     print('Popup blocked initially');
//   }

//   try {
//     // 2. انتظار جلب رابط المرفق من السيرفر
//     final url = await fetchUrl();

//     // 3. فحص ما إذا كان متصفح الهاتف قد حظر النافذة الوهمية
//     bool isPopupBlocked = newWindow == null || newWindow.closed == true;

//     if (!isPopupBlocked) {
//       // المتصفح سمح بالنافذة -> نوجهها للرابط
//       newWindow!.location.href = url;
//       return true;
//     } else {
//       // 4. الخطة البديلة (للهواتف): حيلة الرابط المخفي
//       final html.AnchorElement anchor = html.AnchorElement(href: url)
//         ..target = '_blank'
//         ..rel = 'noopener noreferrer';

//       // إضافة خاصية التحميل تجبر المتصفح على التعامل معه كملف وليس كنافذة منبثقة (يتخطى الحظر)
//       anchor.setAttribute('download', '');

//       // إضافة الرابط للصفحة، الضغط عليه، ثم إزالته
//       html.document.body?.children.add(anchor);
//       anchor.click();
//       anchor.remove();

//       return true;
//     }
//   } catch (e) {
//     print('Error opening attachment: $e');
//     newWindow?.close();
//     return false; // هنا سيقوم التطبيق بإظهار رسالة الخطأ الموجودة في الشاشة
//   }
// }
// lib/services/attachment_opener_web.dart

import 'dart:html' as html;

Future<bool> openAttachment(Future<String> Function() fetchUrl) async {
  try {
    // 1. جلب الرابط من قاعدة البيانات أولاً
    final url = await fetchUrl();

    // فحص ما إذا كان الجهاز المستخدم هو هاتف محمول
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final isMobile = userAgent.contains('android') ||
        userAgent.contains('iphone') ||
        userAgent.contains('ipad');

    if (!isMobile) {
      // 2. إذا كان كمبيوتر، نحاول الفتح بالطريقة العادية لأنها غالباً تعمل
      final window = html.window.open(url, '_blank');
      if (window != null && window.closed != true) {
        return true;
      }
    }

    // 3. الحل الجذري للهواتف (أو إذا تم الحظر على الكمبيوتر)
    // إظهار زر HTML أصلي فوق التطبيق لتخطي الحظر الأمني تماماً
    _showNativeOverlay(url);

    return true;
  } catch (e) {
    print('Error in openAttachment: $e');
    return false;
  }
}

/// دالة لإنشاء شاشة HTML فوق التطبيق تحتوي على رابط مباشر
void _showNativeOverlay(String url) {
  // إنشاء خلفية داكنة تغطي الشاشة
  final overlay = html.DivElement()
    ..style.position = 'fixed'
    ..style.top = '0'
    ..style.left = '0'
    ..style.width = '100vw'
    ..style.height = '100vh'
    ..style.backgroundColor = 'rgba(0, 0, 0, 0.85)' // لون خلفية شفاف أنيق
    ..style.zIndex = '999999' // لضمان ظهورها فوق تطبيق فلاتر
    ..style.display = 'flex'
    ..style.flexDirection = 'column'
    ..style.justifyContent = 'center'
    ..style.alignItems = 'center'
    ..style.fontFamily = 'Cairo, Arial, sans-serif';

  // إنشاء الزر الأساسي (وهو في الحقيقة رابط HTML أصلي)
  final openButton = html.AnchorElement(href: url)
    ..target = '_blank' // لفتح المرفق في صفحة جديدة
    ..rel = 'noopener noreferrer'
    ..text = 'فتح المرفق الآن'
    ..style.padding = '16px 32px'
    ..style.backgroundColor = '#1976D2' // لون أزرق احترافي
    ..style.color = 'white'
    ..style.fontSize = '18px'
    ..style.fontWeight = 'bold'
    ..style.borderRadius = '12px'
    ..style.textDecoration = 'none'
    ..style.boxShadow = '0 4px 12px rgba(0,0,0,0.3)'
    ..style.textAlign = 'center'
    ..style.marginBottom = '20px'
    ..style.width = '200px';

  // إنشاء زر الإلغاء
  final cancelButton = html.ButtonElement()
    ..text = 'إلغاء'
    ..style.padding = '12px 24px'
    ..style.backgroundColor = 'transparent'
    ..style.color = 'white'
    ..style.border = '2px solid white'
    ..style.borderRadius = '12px'
    ..style.fontSize = '16px'
    ..style.cursor = 'pointer'
    ..style.width = '200px';

  // تجميع العناصر وإضافتها لصفحة الويب
  overlay.children.addAll([openButton, cancelButton]);
  html.document.body?.children.add(overlay);

  // إخفاء الشاشة فوراً بمجرد أن يضغط المستخدم على "فتح المرفق"
  openButton.onClick.listen((_) {
    overlay.remove();
  });

  // إخفاء الشاشة عند الضغط على "إلغاء"
  cancelButton.onClick.listen((_) {
    overlay.remove();
  });
}
