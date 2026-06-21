/// Abstraction over where the auth session is persisted, so the storage detail
/// (secure storage in production, in-memory in tests) stays swappable.
abstract class SessionStore {
  Future<void> save(String value);
  Future<String?> read();
  Future<void> clear();
}

/// In-memory store — used in tests and as a safe default; not persisted across
/// app launches.
class InMemorySessionStore implements SessionStore {
  String? _value;

  @override
  Future<void> save(String value) async => _value = value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> clear() async => _value = null;
}
