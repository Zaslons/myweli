/// A consumer's saved providers. In-memory now; a Postgres impl satisfies the
/// same interface (selected by `DATABASE_URL`). Design:
/// docs/design/consumer-favorites.md.
abstract interface class FavoritesRepository {
  /// The user's favorite provider ids, newest first.
  Future<List<String>> listForUser(String userId);

  /// Add a favorite (idempotent — favoriting twice is a no-op).
  Future<void> add(String userId, String providerId);

  /// Remove a favorite (idempotent — removing a non-favorite is a no-op).
  Future<void> remove(String userId, String providerId);
}

class InMemoryFavoritesRepository implements FavoritesRepository {
  // user_id → ordered provider ids (newest first).
  final Map<String, List<String>> _byUser = {};

  @override
  Future<List<String>> listForUser(String userId) async =>
      List<String>.from(_byUser[userId] ?? const []);

  @override
  Future<void> add(String userId, String providerId) async {
    final list = _byUser.putIfAbsent(userId, () => []);
    if (!list.contains(providerId)) list.insert(0, providerId);
  }

  @override
  Future<void> remove(String userId, String providerId) async {
    _byUser[userId]?.remove(providerId);
  }
}
