class PushNotificationStatus {
  final bool supported;
  final bool enabled;
  final String message;
  final String permission;

  const PushNotificationStatus({
    required this.supported,
    required this.enabled,
    required this.message,
    this.permission = 'unsupported',
  });

  bool get needsPermission => false;
  bool get permissionDenied => false;
}

class HamaPushNotificationService {
  Future<PushNotificationStatus> checkAtAppStart() async {
    return const PushNotificationStatus(
      supported: false,
      enabled: false,
      permission: 'unsupported',
      message: 'Browser push is available on HF Team Web.',
    );
  }

  Future<PushNotificationStatus> enable() async {
    return const PushNotificationStatus(
      supported: false,
      enabled: false,
      permission: 'unsupported',
      message: 'Browser push is available on HF Team Web.',
    );
  }

  Future<bool> isEnabled() async => false;

  Future<void> disable() async {}
}
