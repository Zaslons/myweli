import 'device_token_repository.dart';
import 'push_provider.dart';

/// Device registration + push fan-out (design:
/// docs/design/push-notifications-fcm.md). Best-effort: a push failure never
/// affects the triggering flow. Prunes tokens the provider reports invalid.
class PushService {
  PushService(this._provider, this._tokens);

  final PushProvider _provider;
  final DeviceTokenRepository _tokens;

  Future<void> register({
    required String userId,
    required String role,
    required String token,
    required String platform,
  }) => _tokens.upsert(
    token: token,
    userId: userId,
    role: role,
    platform: platform,
  );

  Future<void> unregister(String userId, String token) =>
      _tokens.removeForUser(userId, token);

  /// Pushes to all of [userId]'s devices (no-op when none). Returns the count
  /// accepted by the provider.
  Future<int> sendToUser(
    String userId, {
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      final tokens = await _tokens.tokensForUser(userId);
      if (tokens.isEmpty) return 0;
      final res = await _provider.send(
        tokens: tokens,
        title: title,
        body: body,
        data: data,
      );
      for (final dead in res.invalidTokens) {
        await _tokens.remove(dead);
      }
      return res.sent;
    } catch (_) {
      return 0; // best-effort
    }
  }
}
