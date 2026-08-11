/// Result of a push fan-out: how many were accepted, which tokens the provider
/// reported as permanently invalid (so the caller can prune them), and — when
/// something went wrong that is NOT about a specific token — a machine code.
///
/// **[error] exists because its absence hid a total outage.** `FCM_PRIVATE_KEY`
/// held a key for a retired Firebase project, so OAuth failed on every send and
/// push had never worked. The result was `(sent: 0, invalidTokens: [])` —
/// byte-identical to "there was nobody to send to". No log, no signal, nothing
/// to notice. Codes: `push_auth_failed`, `push_send_failed`.
typedef PushSendResult = ({
  int sent,
  List<String> invalidTokens,
  String? error,
});

/// The FCM adapter seam. Implementations: [LogPushProvider] (dev/CI) and
/// `FcmV1PushProvider` (prod). Design: docs/design/push-notifications-fcm.md.
abstract interface class PushProvider {
  /// Sends [title]/[body] (+ optional [data]) to each of [tokens]. Must not
  /// throw — failures come back via the result.
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data,
  });
}

/// The supported way to run a guarded environment with **no push channel at
/// all**, mirroring `DisabledMessagingProvider`.
///
/// Staging needs this. Its FCM project does not exist until the app gets its
/// own bundle ids (docs/design/infra-staging.md §4), and the alternatives are
/// both bad: pointing staging at production's Firebase project puts test pushes
/// on real phones, and letting the guard fall through to [LogPushProvider]
/// means an unconfigured **production** deploy also silently succeeds.
///
/// Unlike [LogPushProvider] it reports `sent: 0` and an error, so the caller
/// records the truth rather than a phantom delivery. It is never auto-detected
/// — only `PUSH_PROVIDER=disabled` selects it — so "nothing configured" still
/// hits the fail-fast.
class DisabledPushProvider implements PushProvider {
  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async =>
      (sent: 0, invalidTokens: const <String>[], error: 'push_disabled');
}

/// Dev/CI provider: no network, reports everything sent. The outbound record is
/// the app's in-app notification centre, not this.
class LogPushProvider implements PushProvider {
  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async =>
      (sent: tokens.length, invalidTokens: const <String>[], error: null);
}
