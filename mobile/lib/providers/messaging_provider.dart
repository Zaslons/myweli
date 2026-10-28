import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/formatters.dart';
import '../core/utils/salon_time.dart';
import '../models/messaging.dart';
import '../services/interfaces/messaging_service_interface.dart';

/// Thin wrapper over [MessagingServiceInterface] for outbound client comms
/// (WhatsApp-first, SMS fallback). The real backend owns template approval and
/// reminder scheduling; this just hands a message to the seam.
class MessagingProvider extends ChangeNotifier implements AccountScoped {
  final MessagingServiceInterface _service = serviceLocator.messagingService;

  List<OutboundMessage> _outbox = const [];
  List<OutboundMessage> get outbox => _outbox;

  /// Whose confirmations these are — a read sent before the account changed
  /// writes nothing when it answers after
  /// (docs/design/consumer-account-scope.md §2.3).
  int _account = 0;

  /// The account changed (B9.13): the outbox holds the previous account's
  /// confirmations — its phone number, its salons, its times.
  @override
  void resetForAccountChange() {
    _account++;
    _outbox = const [];
    notifyListeners();
  }

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
    final account = _account;
    final res = await _service.getOutbox();
    if (account != _account) return;
    if (res.success && res.data != null) {
      _outbox = res.data!;
      notifyListeners();
    }
  }
}
