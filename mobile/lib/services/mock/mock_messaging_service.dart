import '../../core/constants/app_constants.dart';
import '../../core/utils/message_templates.dart';
import '../../models/api_response.dart';
import '../../models/messaging.dart';
import '../interfaces/messaging_service_interface.dart';

class MockMessagingService implements MessagingServiceInterface {
  final List<OutboundMessage> _outbox = [];
  final Set<String> _optedOut = {};

  @override
  void setOptedOut(String phone, bool optedOut) {
    if (optedOut) {
      _optedOut.add(phone);
    } else {
      _optedOut.remove(phone);
    }
  }

  @override
  bool isOptedOut(String phone) => _optedOut.contains(phone);

  // Mock heuristic for the fallback path: pretend numbers whose digits end in
  // '0' have no WhatsApp, so they fall back to SMS.
  bool _hasWhatsApp(String phone) =>
      !phone.replaceAll(RegExp(r'\D'), '').endsWith('0');

  @override
  Future<ApiResponse<OutboundMessage>> send({
    required String recipientPhone,
    required MessageTemplate template,
    Map<String, String> params = const {},
    MessageChannel preferred = MessageChannel.whatsApp,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    if (recipientPhone.trim().isEmpty) {
      return ApiResponse.error('Numéro du destinataire manquant');
    }
    // Marketing messages require opt-in; transactional ones always send.
    if (template.category == MessageCategory.promotional &&
        isOptedOut(recipientPhone)) {
      return ApiResponse.error(
          'Destinataire désinscrit des messages marketing');
    }

    // WhatsApp-first, with SMS fallback when WhatsApp isn't available.
    final channel =
        (preferred == MessageChannel.whatsApp && !_hasWhatsApp(recipientPhone))
            ? MessageChannel.sms
            : preferred;

    final message = OutboundMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      recipientPhone: recipientPhone,
      channel: channel,
      template: template,
      params: params,
      body: renderTemplate(template, params),
      status: DeliveryStatus.delivered,
      createdAt: DateTime.now(),
    );
    _outbox.add(message);
    return ApiResponse.success(message, message: 'Message envoyé');
  }

  @override
  Future<ApiResponse<List<OutboundMessage>>> getOutbox() async {
    await Future.delayed(AppConstants.mockDelay);
    return ApiResponse.success(List.unmodifiable(_outbox));
  }
}
