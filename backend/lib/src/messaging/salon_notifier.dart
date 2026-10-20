import '../access/capabilities.dart';
import '../access/membership_repository.dart';
import '../notifications/notification_prefs_repository.dart';
import '../notifications/notifications_repository.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import '../salon_time.dart';

/// A booking event the SALON team cares about — the provider-directed mirror
/// of [BookingNotifier]'s consumer templates. Push + in-app feed only (no
/// WhatsApp/SMS to salons in this slice).
///
/// The Pro app promises exactly these (dashboard push prompt, blocked banner,
/// notifications empty state: « réserve, reporte, annule ou envoie son
/// acompte »), and `promise_honesty_pin_test.dart` reads this enum to hold
/// that promise to it.
/// Design: docs/design/push-notifications-fcm.md §10,
/// docs/design/salon-client-reschedule-notify.md.
enum SalonEvent {
  newBooking,
  clientRescheduled,
  clientCancelled,
  depositSubmitted,
}

/// Turns a client-driven booking event into salon-team notifications:
/// resolves the recipients from the salon's ACTIVE memberships (capability
/// scoped — see [_recipients]), then pushes to their devices (gated by each
/// account's `push` preference; all four events are transactional so the
/// reminders/marketing toggles don't apply) and always writes an in-app feed
/// row (the pro bell's fuel). Best-effort throughout: a notification failure
/// never affects the booking transition.
///
/// Manual salon bookings never reach this class — they ride
/// `POST /providers/{id}/appointments`, which has no hook (the salon isn't
/// notified about its own entries; pinned by test).
class SalonNotifier {
  SalonNotifier(
    this._members,
    this._push,
    this._notifications,
    this._prefs,
    this._providers,
  );

  final MembershipRepository _members;
  final PushService _push;
  final NotificationsRepository _notifications;
  final NotificationPrefsRepository _prefs;
  final ProvidersRepository _providers;

  /// Sends [event] for [appointment] (a no-op when null / unresolvable).
  ///
  /// [previousAppointmentDate] — the booking's date before a client moved it;
  /// read only by [SalonEvent.clientRescheduled], whose body names the slot
  /// that frees up (and does without it when absent or unreadable).
  Future<void> notify(
    Map<String, dynamic>? appointment,
    SalonEvent event, {
    String? previousAppointmentDate,
  }) async {
    if (appointment == null) return;
    try {
      final providerId = appointment['providerId'] as String?;
      if (providerId == null) return;

      final recipients = await _recipients(
        providerId,
        appointment['artistId'] as String?,
      );
      if (recipients.isEmpty) return;

      final p = await _providers.byId(providerId);
      final tzName = p?['timezone'] as String?;
      final title = _title(event);
      final body = _body(event, appointment, tzName, previousAppointmentDate);
      final id = appointment['id'];
      // The route carries its SALON (`?salon=`): a multi-salon owner may be
      // signed in on another one, and the pro app switches before opening the
      // booking (R6). The push `data` also carries `providerId`; the in-app
      // FEED row has only this route, which is why the salon rides IN it.
      final route = id != null
          ? '/pro/appointment/$id?salon=$providerId'
          : '/pro/appointments';

      for (final accountId in recipients) {
        // The push channel honours the account's opt-out; the feed row is a
        // passive history log and is always written (threat T24 posture).
        final prefs = await _prefs.get(accountId);
        if (prefs.push) {
          await _push.sendToUser(
            accountId,
            title: title,
            body: body,
            data: {
              'event': _eventName(event),
              if (id != null) 'appointmentId': '$id',
              // The pro app may be signed in on another salon: the tap
              // handler switches to this one before deep-linking (R6).
              'providerId': providerId,
              'route': route,
            },
          );
        }
        await _notifications.add(
          userId: accountId,
          type: _feedType(event),
          title: title,
          body: body,
          route: route,
        );
      }
    } catch (_) {
      // best-effort — a notification failure never affects the transition.
    }
  }

  /// The recipient rule (design §10, stated once): every ACTIVE member with a
  /// linked account whose role can see the whole journal
  /// ([Cap.journalViewAll] — owner/manager/reception); an own-scope member
  /// (Collaborateur) only when the booking is assigned to THEIR artist. An
  /// unassigned booking therefore reaches view-all members only. Deduped by
  /// account.
  Future<List<String>> _recipients(String providerId, String? artistId) async {
    final rows = await _members.listForProvider(providerId);
    final out = <String>[];
    for (final m in rows) {
      final accountId = m.accountId;
      if (m.status != 'active' || accountId == null) continue;
      final caps = capabilitiesFor(m.role);
      final viewAll = caps.contains(Cap.journalViewAll);
      final ownMatch =
          caps.contains(Cap.journalViewOwn) &&
          artistId != null &&
          m.artistId == artistId;
      if ((viewAll || ownMatch) && !out.contains(accountId)) {
        out.add(accountId);
      }
    }
    return out;
  }

  String _eventName(SalonEvent e) => switch (e) {
    SalonEvent.newBooking => 'new_booking',
    SalonEvent.clientRescheduled => 'client_rescheduled',
    SalonEvent.clientCancelled => 'client_cancelled',
    SalonEvent.depositSubmitted => 'deposit_submitted',
  };

  /// Maps an event to the app's `AppNotificationType.name` (in-app feed).
  String _feedType(SalonEvent e) => switch (e) {
    SalonEvent.newBooking => 'general',
    SalonEvent.clientRescheduled => 'reschedule',
    SalonEvent.clientCancelled => 'cancellation',
    SalonEvent.depositSubmitted => 'depositReceived',
  };

  String _title(SalonEvent e) => switch (e) {
    SalonEvent.newBooking => 'Nouvelle réservation',
    SalonEvent.clientRescheduled => 'Réservation reportée',
    SalonEvent.clientCancelled => 'Réservation annulée',
    SalonEvent.depositSubmitted => 'Justificatif d’acompte reçu',
  };

  /// French body with the SALON wall-clock (multi-pays §3). No client PII —
  /// name/phone stay in the app behind auth (threat T58).
  String _body(
    SalonEvent e,
    Map<String, dynamic> a,
    String? tzName,
    String? previousDate,
  ) {
    DateTime? wallOf(Object? iso) {
      final dt = DateTime.tryParse('${iso ?? ''}')?.toUtc();
      return dt == null ? null : salonWallClock(dt, tzName);
    }

    final wall = wallOf(a['appointmentDate']);
    final when = wall == null ? '' : ' du ${_date(wall)} à ${_time(wall)}';
    return switch (e) {
      SalonEvent.newBooking =>
        wall == null
            ? 'Nouvelle demande de réservation.'
            : 'Nouvelle demande de réservation le ${_date(wall)} '
                  'à ${_time(wall)}.',
      SalonEvent.clientRescheduled => _rescheduled(
        to: wall,
        from: wallOf(previousDate),
      ),
      SalonEvent.clientCancelled => 'Le client a annulé le rendez-vous$when.',
      SalonEvent.depositSubmitted =>
        'Un justificatif d’acompte a été envoyé pour le rendez-vous$when.',
    };
  }

  /// N2 (spec salon-client-reschedule-notify §3.1): the slot it leaves and
  /// the one it takes; without a readable old date, the new one alone;
  /// without a new date, the event alone.
  String _rescheduled({DateTime? to, DateTime? from}) {
    if (to == null) return 'Le client a reporté un rendez-vous.';
    final at = 'au ${_date(to)} à ${_time(to)}';
    if (from == null) return 'Le client a reporté le rendez-vous $at.';
    return 'Le client a reporté le rendez-vous du ${_date(from)} à '
        '${_time(from)} $at.';
  }

  String _date(DateTime d) => '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
  String _time(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');
}
