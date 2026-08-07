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

/// **Messaging deliberately switched off** — a supported production posture,
/// not a fallback (G1).
///
/// MyWeli launches before company registration, and SMS/WhatsApp both require a
/// registered entity: Termii's branded sender needs ARTCI, and a WhatsApp
/// business number needs a Meta business verification. So at launch there is no
/// SMS channel to configure, and production must be able to say that out loud
/// instead of being handed credentials that do not exist.
///
/// **The one thing that separates this from [LogMessagingProvider]** — and the
/// reason `MESSAGING_PROVIDER=log` is refused in production — is that this
/// reports `ok: false`. The log provider answers `ok: true`, so the outbox
/// records a phantom `sent` for a message nobody received. This one leaves an
/// honest, queryable trail of undelivered messages, which is what you want the
/// day the channel is switched on and someone asks what was missed.
///
/// It is never a default. It is selected only by an explicit
/// `MESSAGING_PROVIDER=disabled`, so "nothing configured" still fails fast.
class DisabledMessagingProvider implements MessagingProvider {
  @override
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  }) async => (ok: false, providerMessageId: null, error: 'messaging_disabled');
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
