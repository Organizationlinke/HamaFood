import 'dart:html' as html;
import 'dart:js_util' as js_util;

import '../core/supabase_client.dart';

class PushNotificationStatus {
  final bool supported;
  final bool enabled;
  final String message;
  final String permission;

  const PushNotificationStatus({
    required this.supported,
    required this.enabled,
    required this.message,
    this.permission = 'default',
  });

  bool get needsPermission => permission == 'default' && !enabled;
  bool get permissionDenied => permission == 'denied';
}

class HamaPushNotificationService {
  static const _vapidPublicKey = String.fromEnvironment(
    'HAMA_VAPID_PUBLIC_KEY',
  );

  Future<PushNotificationStatus> checkAtAppStart() async {
    if (_vapidPublicKey.trim().isEmpty) {
      return const PushNotificationStatus(
        supported: false,
        enabled: false,
        permission: 'unsupported',
        message: 'HAMA_VAPID_PUBLIC_KEY is not configured in the web build.',
      );
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      return const PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'default',
        message: 'Please sign in first.',
      );
    }

    try {
      final permission = await _browserPermission();

      if (permission == 'denied') {
        return const PushNotificationStatus(
          supported: true,
          enabled: false,
          permission: 'denied',
          message: 'Notifications are blocked for HF Team in this browser.',
        );
      }

      if (permission != 'granted') {
        return const PushNotificationStatus(
          supported: true,
          enabled: false,
          permission: 'default',
          message: 'HF Team needs notification permission.',
        );
      }

      // Permission is already granted. Repair/re-create the subscription if
      // the browser lost it or the database no longer has the active row.
      final raw = await _call('getSubscription', []);
      if (raw != null) {
        // Permission may survive a deployment while the database row is
        // inactive/stale. Upsert it on every app start so the current device
        // is active again without asking the user for permission a second time.
        await _saveSubscription(user.id, raw);
        return const PushNotificationStatus(
          supported: true,
          enabled: true,
          permission: 'granted',
          message: 'Browser notifications enabled.',
        );
      }

      // The browser still grants notification permission, but the Push
      // subscription itself may have disappeared. Re-create it silently;
      // no permission prompt is required when permission is already granted.
      final created = await _call('subscribe', [_vapidPublicKey]);
      if (created != null) {
        await _saveSubscription(user.id, created);
        return const PushNotificationStatus(
          supported: true,
          enabled: true,
          permission: 'granted',
          message: 'Browser notifications enabled.',
        );
      }

      return const PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'granted',
        message: 'Browser push subscription could not be created.',
      );
    } catch (e) {
      // If the browser already granted permission, do NOT downgrade the
      // status back to `default`. That made the app show the permission
      // dialog again even though the browser had already allowed it.
      return PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'granted',
        message: 'Notifications are allowed, but the browser push subscription could not be restored: $e',
      );
    }
  }

  Future<bool> isEnabled() async {
    final status = await checkAtAppStart();
    return status.enabled;
  }

  Future<PushNotificationStatus> enable() async {
    if (_vapidPublicKey.trim().isEmpty) {
      return const PushNotificationStatus(
        supported: false,
        enabled: false,
        permission: 'unsupported',
        message: 'HAMA_VAPID_PUBLIC_KEY is not configured in the web build.',
      );
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      return const PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'default',
        message: 'Please sign in first.',
      );
    }

    try {
      var permission = await _browserPermission();

      if (permission == 'denied') {
        return const PushNotificationStatus(
          supported: true,
          enabled: false,
          permission: 'denied',
          message:
              'Notifications are blocked. Open your browser/site notification settings and allow HF Team notifications.',
        );
      }

      if (permission == 'default') {
        permission = await _requestBrowserPermission();
      }

      if (permission != 'granted') {
        return PushNotificationStatus(
          supported: true,
          enabled: false,
          permission: permission,
          message: permission == 'denied'
              ? 'Notifications are blocked. Open your browser/site notification settings and allow HF Team notifications.'
              : 'Notification permission was not granted.',
        );
      }

      final raw = await _call('subscribe', [_vapidPublicKey]);
      if (raw == null) {
        return const PushNotificationStatus(
          supported: true,
          enabled: false,
          permission: 'granted',
          message: 'Browser push subscription could not be created.',
        );
      }

      await _saveSubscription(user.id, raw);

      return const PushNotificationStatus(
        supported: true,
        enabled: true,
        permission: 'granted',
        message: 'Browser notifications enabled.',
      );
    } catch (e) {
      // Preserve the actual browser permission. A setup/network error must
      // never be reported as `default`, otherwise the UI asks for permission
      // again even when the browser already shows it as Allowed.
      final currentPermission = (await _safePermission()).toString();
      return PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: currentPermission,
        message: 'Could not enable browser notifications: $e',
      );
    }
  }

  Future<void> _saveSubscription(String userId, dynamic raw) async {
    if (raw is! Map) {
      throw StateError('Browser push returned an invalid subscription object.');
    }

    final data = Map<String, dynamic>.from(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
    final rawKeys = data['keys'];
    if (rawKeys is! Map) {
      throw StateError('Browser push subscription is missing encryption keys.');
    }

    final keys = Map<String, dynamic>.from(
      rawKeys.map((key, value) => MapEntry(key.toString(), value)),
    );
    final endpoint = data['endpoint']?.toString();
    final p256dh = keys['p256dh']?.toString();
    final auth = keys['auth']?.toString();

    if (endpoint == null || endpoint.isEmpty ||
        p256dh == null || p256dh.isEmpty ||
        auth == null || auth.isEmpty) {
      throw StateError('Browser push subscription is incomplete.');
    }

    try {
      await supabase.from('user_push_subscriptions').upsert(
        {
          'user_id': userId,
          'endpoint': endpoint,
          'p256dh': p256dh,
          'auth': auth,
          'expiration_time': data['expirationTime'],
          'platform': 'web',
          'user_agent': data['userAgent']?.toString(),
          'active': true,
          'last_seen_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'endpoint',
      );
    } catch (e) {
      throw StateError('Could not save the push subscription to Supabase: $e');
    }
  }

  // Read browser notification permission directly from the Web Notification API.
  // Do not route this through window.hamaPush: older cached push_bridge.js files
  // can expose the object without exposing every method, which caused the
  // `undefined (reading 'apply')` error.
  Future<String> _browserPermission() async {
    try {
      final notification = js_util.getProperty(js_util.globalThis, 'Notification');
      if (notification == null) return 'unsupported';
      return js_util.getProperty(notification, 'permission')?.toString() ?? 'default';
    } catch (_) {
      return 'unsupported';
    }
  }

  Future<String> _requestBrowserPermission() async {
    final notification = js_util.getProperty(js_util.globalThis, 'Notification');
    if (notification == null) {
      throw StateError('Notifications are not supported by this browser.');
    }
    final result = js_util.callMethod(notification, 'requestPermission', const []);
    final resolved = await js_util.promiseToFuture<Object?>(result);
    return resolved?.toString() ?? 'default';
  }

  Future<String> _safePermission() async {
    try {
      return await _browserPermission();
    } catch (_) {
      return 'default';
    }
  }

  Future<void> disable() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final raw = await _call('getSubscription', []);
      if (raw is Map && raw['endpoint'] != null) {
        await supabase
            .from('user_push_subscriptions')
            .update({
              'active': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('endpoint', raw['endpoint'].toString());
      }
      await _call('unsubscribe', []);
    } catch (_) {}
  }

  Future<void> _ensureBridge({String? requiredMethod}) async {
    bool bridgeReady() {
      final bridge = js_util.getProperty(js_util.globalThis, 'hamaPush');
      if (bridge == null) return false;
      if (requiredMethod == null) return true;
      final method = js_util.getProperty(bridge, requiredMethod);
      return method != null;
    }

    // A stale/partial bridge object can exist after a cached deployment.
    // Checking only `window.hamaPush` is not enough: callMethod() will throw
    // `undefined.apply` if the requested function is missing.
    if (bridgeReady()) return;

    final version = DateTime.now().millisecondsSinceEpoch.toString();
    final scripts = html.document.querySelectorAll('script[src*="push_bridge.js"]');
    for (final node in scripts) {
      node.remove();
    }

    final script = html.ScriptElement()
      ..src = Uri.base.resolve('push_bridge.js?v=$version').toString()
      ..type = 'text/javascript';

    final loadFuture = script.onLoad.first;
    final errorFuture = script.onError.first.then((_) {
      throw StateError('Could not load push_bridge.js.');
    });

    final head = html.document.head;
    if (head == null) {
      throw StateError('Browser document head is unavailable.');
    }
    head.append(script);

    await Future.any([loadFuture, errorFuture]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError('Timed out loading push_bridge.js.'),
    );

    // The script load event fires after execution in normal browsers, but
    // keep a short verification loop for slow mobile WebViews/browsers.
    for (var i = 0; i < 50; i++) {
      if (bridgeReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (!bridgeReady()) {
      throw StateError(
        requiredMethod == null
            ? 'Hama Push bridge is unavailable.'
            : 'Hama Push bridge method "$requiredMethod" is unavailable. Please reload HF Team.',
      );
    }
  }

  Future<dynamic> _call(String method, List<dynamic> args) async {
    await _ensureBridge(requiredMethod: method);
    final bridge = js_util.getProperty(js_util.globalThis, 'hamaPush');
    if (bridge == null) {
      throw StateError('Hama Push bridge is unavailable.');
    }

    try {
      final value = js_util.callMethod(bridge, method, args);
      final resolved = await js_util.promiseToFuture<Object?>(value);
      return js_util.dartify(resolved);
    } catch (e) {
      // Do not try to dartify the rejected Promise itself. Doing so can hide
      // the real browser error and turn a push setup failure into a misleading
      // null-related exception.
      throw StateError('Hama Push bridge "$method" failed: $e');
    }
  }
}
