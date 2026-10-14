import 'dart:async';
import 'dart:convert';
import 'dart:js_util' as js_util;

import '../core/supabase_client.dart';

class PushNotificationStatus {
  final bool supported;
  final bool enabled;
  final String message;

  const PushNotificationStatus({
    required this.supported,
    required this.enabled,
    required this.message,
  });
}

class HamaPushNotificationService {
  static const _vapidPublicKey = String.fromEnvironment(
    'HAMA_VAPID_PUBLIC_KEY',
  );

  Future<bool> isEnabled() async {
    if (_vapidPublicKey.trim().isEmpty) return false;
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    try {
      // The database flag is the user's HF Team preference.
      // The browser subscription is then checked separately so the switch
      // stays ON across page reloads without blindly re-enabling a user who
      // explicitly turned notifications OFF.
      final rows = await supabase
          .from('user_push_subscriptions')
          .select('endpoint, active')
          .eq('user_id', user.id)
          .eq('platform', 'web')
          .eq('active', true)
          .limit(1);
      if (rows.isEmpty) return false;

      final browserSubscription = await _call('getSubscription', []);
      if (browserSubscription is Map && browserSubscription['endpoint'] != null) {
        return rows.any((row) =>
            row['endpoint']?.toString() == browserSubscription['endpoint'].toString());
      }

      // Permission may still be granted after a browser/service-worker restart.
      // Re-create the subscription only when the user had already enabled it.
      final raw = await _call('subscribe', [_vapidPublicKey]);
      if (raw != null) {
        await _saveSubscription(user.id, raw);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<PushNotificationStatus> enable() async {
    if (_vapidPublicKey.trim().isEmpty) {
      return const PushNotificationStatus(
        supported: true,
        enabled: false,
        message:
            'HAMA_VAPID_PUBLIC_KEY is not configured in the web build.',
      );
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      return const PushNotificationStatus(
        supported: true,
        enabled: false,
        message: 'Please sign in first.',
      );
    }

    try {
      final permission = await _call('requestPermission', []);
      if (permission != 'granted') {
        return PushNotificationStatus(
          supported: true,
          enabled: false,
          message: 'Browser notification permission: $permission',
        );
      }

      final raw = await _call('subscribe', [_vapidPublicKey]);
      if (raw == null) {
        return const PushNotificationStatus(
          supported: true,
          enabled: false,
          message: 'Browser push subscription could not be created.',
        );
      }

      final data = Map<String, dynamic>.from(
        (raw as Map).map((key, value) => MapEntry(key.toString(), value)),
      );

      final keys = Map<String, dynamic>.from(
        (data['keys'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );

      await _saveSubscription(user.id, data);

      return const PushNotificationStatus(
        supported: true,
        enabled: true,
        message: 'Browser notifications enabled.',
      );
    } catch (e) {
      return PushNotificationStatus(
        supported: true,
        enabled: false,
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
    final bridge = js_util.getProperty(
      js_util.globalThis,
      'hamaPush',
    );
    if (bridge == null) {
      throw StateError(
        'Hama Push bridge is not loaded. Add web/push_bridge.js to web/index.html.',
      );
    }
    final value = js_util.callMethod(bridge, method, args);
    if (value is Future) return value;
    try {
      final resolved = await js_util.promiseToFuture<Object?>(value);
      return js_util.dartify(resolved);
    } catch (_) {
      return js_util.dartify(value);
    }
  }
}
