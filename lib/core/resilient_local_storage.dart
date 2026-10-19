import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth session storage that keeps the normal browser localStorage behavior,
/// but gracefully falls back to in-memory storage if the browser starts
/// denying access to localStorage (SecurityError).
///
/// This is especially useful for mobile browsers where storage access can
/// temporarily become unavailable because of browser/site storage state.
class ResilientLocalStorage extends LocalStorage {
  ResilientLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  late final SharedPreferencesLocalStorage _primary;
  bool _primaryAvailable = true;
  String? _memorySession;

  @override
  Future<void> initialize() async {
    _primary = SharedPreferencesLocalStorage(
      persistSessionKey: persistSessionKey,
    );

    try {
      await _primary.initialize();
    } catch (_) {
      _primaryAvailable = false;
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    if (_primaryAvailable) {
      try {
        final exists = await _primary.hasAccessToken();
        if (exists) return true;
      } catch (_) {
        _primaryAvailable = false;
      }
    }

    return _memorySession != null && _memorySession!.isNotEmpty;
  }

  @override
  Future<String?> accessToken() async {
    if (_primaryAvailable) {
      try {
        final value = await _primary.accessToken();
        if (value != null && value.isNotEmpty) {
          _memorySession = value;
          return value;
        }
      } catch (_) {
        _primaryAvailable = false;
      }
    }

    return _memorySession;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    // Always keep the latest session in memory first. If browser storage
    // becomes unavailable later, the current app session can continue.
    _memorySession = persistSessionString;

    if (!_primaryAvailable) return;

    try {
      await _primary.persistSession(persistSessionString);
    } catch (_) {
      _primaryAvailable = false;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    _memorySession = null;

    if (!_primaryAvailable) return;

    try {
      await _primary.removePersistedSession();
    } catch (_) {
      _primaryAvailable = false;
    }
  }
}
