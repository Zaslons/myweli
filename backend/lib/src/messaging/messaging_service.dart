import 'dart:math';

import 'messaging_models.dart';
import 'messaging_outbox_repository.dart';
import 'messaging_prefs_repository.dart';
import 'messaging_provider.dart';

/// Outbound messaging (design: docs/design/messaging-notifications.md).
/// WhatsApp-first with SMS fallback; transactional always sends, promotional only
/// to opted-in recipients. **Best-effort** — a messaging failure never breaks the
/// triggering flow. OTP is sent via [sendOtp] (no persistence, no body logging).
class MessagingService {
  MessagingService(this._provider, this._outbox, this._prefs);

  final MessagingProvider _provider;
  final MessagingOutboxRepository _outbox;
  final MessagingPrefsRepository _prefs;
  final _rand = Random();

  String _id() =>
      'msg_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 32)}';

  /// Sends a lifecycle [template] to [recipientPhone]. Promotional messages are
  /// skipped for opted-out recipients. Records the attempt in the outbox; returns
  /// the stored row, or null when skipped/failed-to-record (never throws).
  Future<Map<String, dynamic>?> sendTemplate({
    required String recipientPhone,
    required MessageTemplate template,
    Map<String, String> params = const {},
    MessageChannel preferred = MessageChannel.whatsApp,
  }) async {
    try {
      if (template.category == MessageCategory.promotional &&
          await _prefs.isOptedOut(recipientPhone)) {
        return null;
      }
      final body = renderTemplate(template, params);
      // WhatsApp-first; fall back to SMS if WhatsApp can't be delivered. (Until
      // approved templates land, WhatsApp is effectively SMS — see the adapter.)
      var channel = preferred;
      var res = await _provider.send(
        to: recipientPhone,
        channel: channel,
        body: body,
      );
      if (!res.ok && channel == MessageChannel.whatsApp) {
        channel = MessageChannel.sms;
        res = await _provider.send(
          to: recipientPhone,
          channel: channel,
          body: body,
        );
      }
      return _outbox.append(
        id: _id(),
        recipientPhone: recipientPhone,
        channel: channel,
        template: template,
        params: params,
        body: body,
        status: res.ok ? DeliveryStatus.sent : DeliveryStatus.failed,
        providerMessageId: res.providerMessageId,
      );
    } catch (_) {
      return null; // best-effort
    }
  }

  /// Sends an OTP [code] over SMS. The code is **never** persisted or logged.
  /// Returns whether the provider accepted it.
  Future<bool> sendOtp(String phone, String code) async {
    try {
      final res = await _provider.send(
        to: phone,
        channel: MessageChannel.sms,
        body: 'Votre code Myweli : $code',
      );
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  /// Advances delivery status from the provider's status webhook.
  Future<void> updateStatus(String providerMessageId, DeliveryStatus status) =>
      _outbox.updateStatus(providerMessageId, status);

  Future<void> setOptedOut(String phone, bool optedOut) =>
      _prefs.setOptedOut(phone, optedOut);

  Future<({List<Map<String, dynamic>> items, int total})> outbox({
    int page = 1,
    int pageSize = 50,
  }) => _outbox.list(page: page, pageSize: pageSize);
}
