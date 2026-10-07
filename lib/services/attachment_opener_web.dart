import 'dart:html' as html;

/// Opens an attachment in a browser tab while preserving the user's click
/// gesture. The blank tab is created synchronously; the signed URL is resolved
/// afterwards and assigned to that tab.
Future<bool> openAttachment(Future<String> Function() resolveUrl) async {
  html.WindowBase? tab;
  try {
    // Must happen synchronously in the click handler to avoid popup blockers.
    tab = html.window.open('about:blank', '_blank');
  } catch (_) {
    tab = null;
  }

  try {
    final url = (await resolveUrl()).trim();
    if (url.isEmpty) throw StateError('Empty attachment URL');

    if (tab != null) {
      // Preferred path: keep the application open in the original tab.
      tab.location.href = url;
    } else {
      // Last-resort fallback: some browsers block _blank even when the click
      // originated from the user. Top-level navigation is not a popup, so it
      // remains reliable. The browser Back button returns to the app.
      html.window.location.href = url;
    }
    return true;
  } catch (_) {
    try {
      tab?.close();
    } catch (_) {}
    return false;
  }
}
