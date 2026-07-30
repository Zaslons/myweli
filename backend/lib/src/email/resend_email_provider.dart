import 'dart:convert';

import 'package:http/http.dart' as http;

import 'email_provider.dart';

/// Resend adapter (https://resend.com) — JSON POST to `/emails` with a Bearer
/// API key. Credentials come from env (never the repo). Requires the sending
/// domain (myweli.com) to be verified in Resend (SPF/DKIM). Design:
/// docs/design/auth-social-email.md §13.
class ResendEmailProvider implements EmailProvider {
  ResendEmailProvider({
    required this.apiKey,
    required this.from,
    this.baseUrl = 'https://api.resend.com',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;

  /// Sender, e.g. `MyWeli <no-reply@myweli.com>`.
  final String from;
  final String baseUrl;
  final http.Client _client;

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    String? html,
  }) async {
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl/emails'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': from,
          'to': [to],
          'subject': subject,
          'text': text,
          if (html != null) 'html': html,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          ok: true,
          providerMessageId: json['id'] as String?,
          error: null,
        );
      }
      return (
        ok: false,
        providerMessageId: null,
        error: 'resend_${res.statusCode}',
      );
    } catch (_) {
      return (ok: false, providerMessageId: null, error: 'resend_unreachable');
    }
  }
}
