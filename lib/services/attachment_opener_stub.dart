// import 'package:url_launcher/url_launcher.dart';

// /// Opens a private attachment after resolving its short-lived signed URL.
// ///
// /// On non-web platforms the URL is handed to the operating system/browser.
// Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
//   try {
//     final url = await resolveUrl();
//     return launchUrl(
//       Uri.parse(url),
//       mode: LaunchMode.externalApplication,
//     );
//   } catch (_) {
//     return false;
//   }
// }
// lib/services/attachment_opener_stub.dart

import 'package:url_launcher/url_launcher.dart';

Future<bool> openAttachment(Future<String> Function() fetchUrl) async {
  try {
    final urlString = await fetchUrl();
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      return await launchUrl(
        url,
        mode: LaunchMode.externalApplication, // لفتح التطبيق الخارجي على الموبايل
      );
    }
    return false;
  } catch (e) {
    print('Error opening attachment: $e');
    return false;
  }
}