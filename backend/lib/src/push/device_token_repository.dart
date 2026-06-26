/// Registry of FCM device tokens. A token belongs to one user (re-register
/// reassigns it — handles device hand-off). Design:
/// docs/design/push-notifications-fcm.md §4.
abstract interface class DeviceTokenRepository {
  /// Insert or reassign [token] to [userId] (with [role]/[platform]).
  Future<void> upsert({
    required String token,
    required String userId,
    required String role,
    required String platform,
  });

  /// The user's current device tokens.
  Future<List<String>> tokensForUser(String userId);

  /// Remove [token] only if it belongs to [userId] (logout / self-scoped).
  Future<void> removeForUser(String userId, String token);

  /// Remove a token outright (pruning a provider-reported invalid token).
  Future<void> remove(String token);
}

class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final Map<String, Map<String, String>> _byToken = {}; // token → {userId,...}

  @override
  Future<void> upsert({
    required String token,
    required String userId,
    required String role,
    required String platform,
  }) async {
    _byToken[token] = {'userId': userId, 'role': role, 'platform': platform};
  }

  @override
  Future<List<String>> tokensForUser(String userId) async => [
    for (final e in _byToken.entries)
      if (e.value['userId'] == userId) e.key,
  ];

  @override
  Future<void> removeForUser(String userId, String token) async {
    if (_byToken[token]?['userId'] == userId) _byToken.remove(token);
  }

  @override
  Future<void> remove(String token) async => _byToken.remove(token);
}
