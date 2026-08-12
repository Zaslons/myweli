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
      if (res.error != null) {
        // The caller only gets a count, and 0 is indistinguishable from "no
        // devices". This is the line that turns a silent outage into something
        // greppable in the container log.
        // ignore: avoid_print
        print(
          'WARNING: push to user failed (${res.error}) — '
          '${tokens.length} token(s), 0 delivered',
        );
      }
      // **Pruning happens after the error report, and says so.** It deletes
      // rows, and it used to do that first and in silence — so when a
      // misclassified payload rejection emptied the table, the only trace was a
      // count that looked like "this user has no devices". A deletion of user
      // data should be at least as loud as a failed send.
      if (res.invalidTokens.isNotEmpty) {
        // ignore: avoid_print
        print(
          'INFO: push_tokens_pruned — removing ${res.invalidTokens.length} of '
          '${tokens.length} token(s) FCM reported as unregistered',
        );
        for (final dead in res.invalidTokens) {
          await _tokens.remove(dead);
        }
      }
      return res.sent;
    } catch (_) {
      return 0; // best-effort
    }
  }
}
