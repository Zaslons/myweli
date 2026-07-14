import '../auth/auth_repository.dart';
import '../notifications/notification_prefs_repository.dart';
import '../notifications/notifications_repository.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import '../salon_time.dart';
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
    this._prefs,
  );

  final MessagingService _messaging;
  final AuthRepository _users;
  final ProvidersRepository _providers;
  final PushService _push;
  final NotificationsRepository _notifications;
  final NotificationPrefsRepository _prefs;

  /// Sends [template] for [appointment] (a no-op when null / unresolvable).
  Future<void> notify(
    Map<String, dynamic>? appointment,
    MessageTemplate template,
  ) async {
    if (appointment == null) return;
    try {
      final salon = await _salon(appointment['providerId'] as String?);
      final params = _params(appointment, salon);

      // Per-user opt-out prefs (FR-NOTIF-004). Manual bookings (no app user) →
      // all-true defaults, unchanged behaviour.
      final userId = appointment['userId'] as String?;
      final prefs = userId != null
          ? await _prefs.get(userId)
          : const NotificationPrefs();

      final allowCategory = _allowCategory(template, prefs);

      final phone = await _recipient(appointment);
      if (phone != null && phone.isNotEmpty && allowCategory) {
        await _messaging.sendTemplate(
          recipientPhone: phone,
          template: template,
          params: params,
        );
      }

      // Consumer-app touches (app bookings only — manual bookings have no app
      // user): push to devices (when the push channel is on AND the category is
      // allowed) + an in-app notification-center entry (always — a passive
      // history log, not a proactive notification).
      if (userId != null) {
        final body = renderTemplate(template, params);
        if (prefs.push && allowCategory) {
          final id = appointment['id'];
          await _push.sendToUser(
            userId,
            title: _pushTitle(template),
            body: body,
            data: {
              'template': template.name,
              if (id != null) 'appointmentId': '$id',
              // Where a tap lands in the consumer app (design §9). The feed
              // row keeps '/bookings' — the web center maps that path.
              'route': id != null ? '/appointment/$id' : '/bookings',
            },
          );
        }
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

  /// Whether [template]'s **category** is allowed under [prefs] (applies to both
  /// the WhatsApp/SMS message and the device push): reminders gate the 24h/2h
  /// templates, marketing gates promotional ones, all other (transactional)
  /// service messages always pass. (The push channel is additionally gated by
  /// `prefs.push`.)
  bool _allowCategory(MessageTemplate t, NotificationPrefs prefs) {
    if (t == MessageTemplate.reminder24h || t == MessageTemplate.reminder2h) {
      return prefs.reminders;
    }
    if (t.category == MessageCategory.promotional) return prefs.marketing;
    return true;
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

  /// The salon's name + market facts in ONE lookup (multi-pays MP1): message
  /// times render the SALON's wall-clock, amounts its currency.
  Future<({String name, String? tzName, String currency})> _salon(
    String? providerId,
  ) async {
    final p = providerId == null ? null : await _providers.byId(providerId);
    return (
      name: (p?['name'] as String?) ?? 'votre salon',
      tzName: p?['timezone'] as String?,
      currency: (p?['currency'] as String?) ?? 'XOF',
    );
  }

  Map<String, String> _params(
    Map<String, dynamic> a,
    ({String name, String? tzName, String currency}) salon,
  ) {
    final dt = DateTime.tryParse('${a['appointmentDate'] ?? ''}')?.toUtc();
    final wall = dt == null ? null : salonWallClock(dt, salon.tzName);
    final deposit = a['depositAmount'] as num?;
    final total = a['totalPrice'] as num?;
    return {
      'provider': salon.name,
      if (wall != null) 'date': _date(wall),
      if (wall != null) 'time': _time(wall),
      if (deposit != null) 'deposit': _money(deposit, salon.currency),
      if (total != null) 'amount': _money(total, salon.currency),
    };
  }

  String _date(DateTime d) => '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
  String _time(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');

  /// « FCFA » is the display name for both CFA francs (multi-pays §4);
  /// other ISO codes render as themselves.
  String _money(num n, String currency) {
    final suffix = (currency == 'XOF' || currency == 'XAF') ? 'FCFA' : currency;
    return '${n.round()} $suffix';
  }
}
