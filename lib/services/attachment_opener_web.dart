import 'dart:html' as html;

/// Opens the browser tab synchronously from the user's click, then assigns the
/// signed URL after it has been fetched. This avoids popup blockers that can
/// reject a new tab when launchUrl() is called only after an async await.
Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
  final tab = html.window.open('about:blank', '_blank');

  // A null WindowBase normally means the browser blocked the popup.
  if (tab == null) return false;

  try {
    final url = await resolveUrl();
    tab.location.href = url;
    return true;
  } catch (_) {
    try {
      tab.close();
    } catch (_) {}
    return false;
  }
}
