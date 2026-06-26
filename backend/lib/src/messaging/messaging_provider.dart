import 'messaging_models.dart';

/// Result of handing a message to a BSP. [providerMessageId] is the BSP's id
/// (used to correlate the delivery-status webhook).
typedef ProviderSendResult = ({
  bool ok,
  String? providerMessageId,
  String? error,
});

/// The BSP adapter seam. Implementations: [LogMessagingProvider] (dev/CI) and
/// `TwilioMessagingProvider` (prod). Design: docs/design/messaging-notifications.md.
abstract interface class MessagingProvider {
  /// Hands a fully-rendered [body] to the channel for [to] (E.164). Must not
  /// throw — network/credential failures come back as `ok: false`.
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  });
}

/// Dev/CI provider: never touches the network, always "sends". It deliberately
/// **does not log the body** (OTP-safe) — the outbox is the audit record.
class LogMessagingProvider implements MessagingProvider {
  var _seq = 0;

  @override
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  }) async => (ok: true, providerMessageId: 'log_${_seq++}', error: null);
}
