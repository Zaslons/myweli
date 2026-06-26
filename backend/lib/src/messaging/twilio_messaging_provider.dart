import 'dart:convert';

import 'package:http/http.dart' as http;

import 'messaging_models.dart';
import 'messaging_provider.dart';

/// Twilio Programmable Messaging adapter (WhatsApp + SMS). Form-POSTs to the
/// Messages API with Basic auth; WhatsApp uses the `whatsapp:` address prefix.
/// Credentials come from env (never the repo). Design:
/// docs/design/messaging-notifications.md §3.
///
/// NOTE: approved-template (`ContentSid`) sends are a follow-up — until templates
/// are approved, WhatsApp degrades to SMS at the service layer.
class TwilioMessagingProvider implements MessagingProvider {
  TwilioMessagingProvider({
    required this.accountSid,
    required this.authToken,
    required this.smsFrom,
    required this.whatsAppFrom,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String accountSid;
  final String authToken;
  final String smsFrom;
  final String whatsAppFrom;
  final http.Client _client;

  Uri get _endpoint => Uri.parse(
    'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
  );

  @override
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  }) async {
    final isWhatsApp = channel == MessageChannel.whatsApp;
    final from = isWhatsApp ? 'whatsapp:$whatsAppFrom' : smsFrom;
    final dest = isWhatsApp ? 'whatsapp:$to' : to;
    final auth = base64Encode(utf8.encode('$accountSid:$authToken'));
    try {
      final res = await _client.post(
        _endpoint,
        headers: {
          'Authorization': 'Basic $auth',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'To': dest, 'From': from, 'Body': body},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          ok: true,
          providerMessageId: json['sid'] as String?,
          error: null,
        );
      }
      return (
        ok: false,
        providerMessageId: null,
        error: 'twilio_${res.statusCode}',
      );
    } catch (_) {
      return (ok: false, providerMessageId: null, error: 'twilio_unreachable');
    }
  }
}
