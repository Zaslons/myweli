import '../../models/api_response.dart';
import '../../models/messaging.dart';

/// Outbound messaging (WhatsApp-first, SMS fallback). The real implementation
/// talks to a WhatsApp Business BSP (Meta Cloud / 360dialog / Twilio) with
/// approved templates; delivery status arrives via a status webhook.
abstract class MessagingServiceInterface {
  /// Sends [template] to [recipientPhone]. Transactional templates always go;
  /// promotional ones are skipped for opted-out recipients.
  Future<ApiResponse<OutboundMessage>> send({
    required String recipientPhone,
    required MessageTemplate template,
    Map<String, String> params,
    MessageChannel preferred,
  });

  /// Messages handed off so far (newest last) — for the in-app log / debugging.
  Future<ApiResponse<List<OutboundMessage>>> getOutbox();

  void setOptedOut(String phone, bool optedOut);
  bool isOptedOut(String phone);
}
