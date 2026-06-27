import '../auth/auth_repository.dart';
import '../notifications/notifications_repository.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import 'messaging_models.dart';
import 'messaging_service.dart';

/// Turns a booking transition into a notification: resolves the recipient
/// (manual `clientPhone`, else the consumer's phone) + the salon name, builds the
/// template params, and hands off to [MessagingService] (WhatsApp/SMS),
/// [PushService] (FCM), **and** the in-app feed ([NotificationsRepository]) — all
/// best-effort. Keeps the transition services pure.
/// Design: docs/design/messaging-notifications.md + notification-center.md.
class BookingNotifier {
  BookingNotifier(
    this._messaging,
    this._users,
    this._providers,
    this._push,
    this._notifications,
  );

  final MessagingService _messaging;
  final AuthRepository _users;
  final ProvidersRepository _providers;
  final PushService _push;
  final NotificationsRepository _notifications;

  /// Sends [template] for [appointment] (a no-op when null / unresolvable).
  Future<void> notify(
    Map<String, dynamic>? appointment,
    MessageTemplate template,
  ) async {
    if (appointment == null) return;
    try {
      final providerName = await _providerName(
        appointment['providerId'] as String?,
      );
      final params = _params(appointment, providerName);

      final phone = await _recipient(appointment);
      if (phone != null && phone.isNotEmpty) {
        await _messaging.sendTemplate(
          recipientPhone: phone,
          template: template,
          params: params,
        );
      }

      // Consumer-app touches (app bookings only — manual bookings have no app
      // user): push to devices + an in-app notification-center entry.
      final userId = appointment['userId'] as String?;
      if (userId != null) {
        final body = renderTemplate(template, params);
        await _push.sendToUser(
          userId,
          title: _pushTitle(template),
          body: body,
          data: {
            'template': template.name,
            if (appointment['id'] != null)
              'appointmentId': '${appointment['id']}',
          },
        );
        await _notifications.add(
          userId: userId,
          type: _notificationType(template),
          title: _pushTitle(template),
          body: body,
          route: '/bookings',
        );
      }
    } catch (_) {
      // best-effort — a notification failure never affects the transition.
    }
  }

  /// Maps a template to the app's `AppNotificationType.name` (in-app feed).
  String _notificationType(MessageTemplate t) => switch (t) {
    MessageTemplate.bookingConfirmed ||
    MessageTemplate.bookingAccepted => 'bookingConfirmed',
    MessageTemplate.depositReceived => 'depositReceived',
    MessageTemplate.reminder24h || MessageTemplate.reminder2h => 'reminder',
    MessageTemplate.rescheduled => 'reschedule',
    MessageTemplate.bookingDeclined ||
    MessageTemplate.cancelled => 'cancellation',
    MessageTemplate.refund || MessageTemplate.rebookReminder => 'general',
  };

  String _pushTitle(MessageTemplate t) => switch (t) {
    MessageTemplate.bookingConfirmed => 'Réservation confirmée',
    MessageTemplate.bookingAccepted => 'Réservation acceptée',
    MessageTemplate.bookingDeclined => 'Réservation refusée',
    MessageTemplate.depositReceived => 'Acompte reçu',
    MessageTemplate.reminder24h || MessageTemplate.reminder2h => 'Rappel',
    MessageTemplate.rescheduled => 'Rendez-vous reporté',
    MessageTemplate.cancelled => 'Rendez-vous annulé',
    MessageTemplate.refund => 'Remboursement',
    MessageTemplate.rebookReminder => 'Reprenez rendez-vous',
  };

  Future<String?> _recipient(Map<String, dynamic> a) async {
    final clientPhone = a['clientPhone'] as String?;
    if (clientPhone != null && clientPhone.isNotEmpty) return clientPhone;
    final userId = a['userId'] as String?;
    if (userId == null) return null;
    return (await _users.userById(userId))?.phoneNumber;
  }

  Future<String> _providerName(String? providerId) async {
    if (providerId == null) return 'votre salon';
    final p = await _providers.byId(providerId);
    return (p?['name'] as String?) ?? 'votre salon';
  }

  Map<String, String> _params(Map<String, dynamic> a, String providerName) {
    final dt = DateTime.tryParse('${a['appointmentDate'] ?? ''}')?.toUtc();
    final deposit = a['depositAmount'] as num?;
    final total = a['totalPrice'] as num?;
    return {
      'provider': providerName,
      if (dt != null) 'date': _date(dt),
      if (dt != null) 'time': _time(dt),
      if (deposit != null) 'deposit': _fcfa(deposit),
      if (total != null) 'amount': _fcfa(total),
    };
  }

  // Côte d'Ivoire is UTC, so UTC == local — no timezone conversion needed.
  String _date(DateTime d) => '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
  String _time(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fcfa(num n) => '${n.round()} XOF';
}
