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
      final permission = (await _call('getPermission', []))?.toString() ?? 'default';

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
      return PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'default',
        message: 'Could not check browser notifications: $e',
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
      var permission = (await _call('getPermission', []))?.toString() ?? 'default';

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
        permission = (await _call('requestPermission', []))?.toString() ?? 'default';
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
      return PushNotificationStatus(
        supported: true,
        enabled: false,
        permission: 'default',
        message: 'Could not enable browser notifications: $e',
      );
    }
  }

  Future<void> _saveSubscription(String userId, dynamic raw) async {
    final data = Map<String, dynamic>.from(
      (raw as Map).map((key, value) => MapEntry(key.toString(), value)),
    );
    final keys = Map<String, dynamic>.from(
      (data['keys'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );

    await supabase.from('user_push_subscriptions').upsert(
      {
        'user_id': userId,
        'endpoint': data['endpoint'],
        'p256dh': keys['p256dh'],
        'auth': keys['auth'],
        'expiration_time': data['expirationTime'],
        'platform': 'web',
        'user_agent': data['userAgent'],
        'active': true,
        'last_seen_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'endpoint',
    );
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

  Future<dynamic> _call(String method, List<dynamic> args) async {
    final bridge = js_util.getProperty(js_util.globalThis, 'hamaPush');
    if (bridge == null) {
      throw StateError(
        'Hama Push bridge is not loaded. Add web/push_bridge.js to web/index.html.',
      );
    }
    final value = js_util.callMethod(bridge, method, args);
    try {
      final resolved = await js_util.promiseToFuture<Object?>(value);
      return js_util.dartify(resolved);
    } catch (_) {
      return js_util.dartify(value);
    }
  }
}
