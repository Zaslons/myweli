import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'interfaces/session_store.dart';

/// Persists the auth session in the platform secure store (Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android) — never in
/// `shared_preferences` or logs.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage, String? key})
      : _storage = storage ?? const FlutterSecureStorage(),
        _key = key ?? 'myweli_session';

  final FlutterSecureStorage _storage;

  /// Storage key — distinct keys keep independent sessions side by side (e.g.
  /// the consumer session vs. the provider session on the same device).
  final String _key;

  @override
  Future<void> save(String value) => _storage.write(key: _key, value: value);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
