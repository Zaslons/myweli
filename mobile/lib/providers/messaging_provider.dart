import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../core/utils/formatters.dart';
import '../core/utils/salon_time.dart';
import '../models/messaging.dart';
import '../services/interfaces/messaging_service_interface.dart';

/// Thin wrapper over [MessagingServiceInterface] for outbound client comms
/// (WhatsApp-first, SMS fallback). The real backend owns template approval and
/// reminder scheduling; this just hands a message to the seam.
class MessagingProvider extends ChangeNotifier {
  final MessagingServiceInterface _service = serviceLocator.messagingService;

  List<OutboundMessage> _outbox = const [];
  List<OutboundMessage> get outbox => _outbox;

  /// Fired after a booking is confirmed. Best-effort: never blocks the booking
  /// UX, so failures are swallowed (the backend retries/queues for real).
  Future<void> sendBookingConfirmation({
    required String recipientPhone,
    required String providerName,
    required DateTime dateTime,
    required double depositAmount,
    String? tz,
    String? currency,
  }) async {
    // The message renders the SALON's wall-clock + currency (multi-pays).
    final wall = toSalonTime(dateTime, tz: tz);
    await _service.send(
      recipientPhone: recipientPhone,
      template: MessageTemplate.bookingConfirmed,
      params: {
        'provider': providerName,
        'date': Formatters.formatDateShort(wall),
        'time': Formatters.formatTime(wall),
        'deposit': Formatters.formatCurrency(depositAmount, currency: currency),
      },
    );
    await refreshOutbox();
  }

  Future<void> refreshOutbox() async {
    final res = await _service.getOutbox();
    if (res.success && res.data != null) {
      _outbox = res.data!;
      notifyListeners();
    }
  }
}
