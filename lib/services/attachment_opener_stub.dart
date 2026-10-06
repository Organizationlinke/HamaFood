import 'package:url_launcher/url_launcher.dart';

/// Opens a private attachment after resolving its short-lived signed URL.
///
/// On non-web platforms the URL is handed to the operating system/browser.
Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
  try {
    final url = await resolveUrl();
    return launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
