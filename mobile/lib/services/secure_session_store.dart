import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'interfaces/session_store.dart';

/// Persists the auth session in the platform secure store (Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android) — never in
/// `shared_preferences` or logs.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'myweli_session';

  @override
  Future<void> save(String value) => _storage.write(key: _key, value: value);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
