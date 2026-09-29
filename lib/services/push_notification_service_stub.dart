// class PushNotificationStatus {
//   final bool supported;
//   final bool enabled;
//   final String message;

//   const PushNotificationStatus({
//     required this.supported,
//     required this.enabled,
//     required this.message,
//   });
// }

// class HamaPushNotificationService {
//   Future<PushNotificationStatus> enable() async => const PushNotificationStatus(
//         supported: false,
//         enabled: false,
//         message: 'Browser push is available on Hama Work Web.',
//       );

//   Future<bool> isEnabled() async => false;
// }
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
  Future<PushNotificationStatus> enable() async {
    return const PushNotificationStatus(
      supported: false,
      enabled: false,
      message: 'Browser push is available on Hama Work Web.',
    );
  }

  Future<bool> isEnabled() async {
    return false;
  }

  Future<void> disable() async {
    // No browser push subscription on non-web platforms.
  }
}