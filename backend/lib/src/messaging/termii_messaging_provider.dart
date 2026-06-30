import 'dart:convert';

import 'package:http/http.dart' as http;

import 'messaging_models.dart';
import 'messaging_provider.dart';

/// Termii SMS adapter — a West-Africa BSP, ~14 FCFA (~$0.023) per SMS to Côte
/// d'Ivoire vs Twilio's ~$0.49. JSON-POSTs to `/api/sms/send` with the API key
/// in the body. We send our **own** OTP text via the *plain* SMS API (never
/// Termii's Token API) so the OTP lifecycle stays server-owned — generated,
/// hashed, rate-limited, dev-code inline only off-prod. Credentials come from
/// env (never the repo). Design: docs/design/messaging-termii.md.
///
/// SMS only for now: WhatsApp over Termii needs separate setup, so WhatsApp
/// sends return `whatsapp_not_configured` and the service falls back to SMS
/// (parity with [TwilioMessagingProvider]).
class TermiiMessagingProvider implements MessagingProvider {
  TermiiMessagingProvider({
    required this.apiKey,
    required this.senderId,
    this.baseUrl = 'https://api.ng.termii.com',
    this.route = 'generic',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;

  /// Sender ID shown to the recipient. A branded ID (e.g. `Myweli`) needs
  /// operator/ARTCI registration; a generic/shared sender works pre-registration.
  final String senderId;

  /// Termii API base (region endpoint); override via `TERMII_BASE_URL`.
  final String baseUrl;

  /// Termii delivery route — their request `channel` field (`generic` | `dnd`).
  /// Named `route` here to avoid clashing with [MessageChannel].
  final String route;

  final http.Client _client;

  Uri get _endpoint => Uri.parse('$baseUrl/api/sms/send');

  @override
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  }) async {
    if (channel == MessageChannel.whatsApp) {
      // No WhatsApp route configured — signal not-ok so the service falls back
      // to SMS, without a wasted API call (parity with the Twilio adapter).
      return (
        ok: false,
        providerMessageId: null,
        error: 'whatsapp_not_configured',
      );
    }
    // Termii expects the MSISDN without the leading '+'.
    final dest = to.startsWith('+') ? to.substring(1) : to;
    final payload = jsonEncode({
      'to': dest,
      'from': senderId,
      'sms': body,
      'type': 'plain',
      'channel': route,
      'api_key': apiKey,
    });
    try {
      final res = await _client.post(
        _endpoint,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        // Termii returns `message_id` on a real send; a 2xx without it is a soft
        // rejection (balance/sender/recipient issues) → treat as failed.
        final id = json['message_id'];
        if (id is String && id.isNotEmpty) {
          return (ok: true, providerMessageId: id, error: null);
        }
        return (ok: false, providerMessageId: null, error: 'termii_rejected');
      }
      return (
        ok: false,
        providerMessageId: null,
        error: 'termii_${res.statusCode}',
      );
    } catch (_) {
      return (ok: false, providerMessageId: null, error: 'termii_unreachable');
    }
  }
}
