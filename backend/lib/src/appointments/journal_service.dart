import '../access/capabilities.dart';
import '../access/membership_service.dart';
import '../clients/clients_service.dart';
import '../providers_repository.dart';
import 'appointment_repository.dart';

typedef JournalResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// The journal day view (module `journal` J1 — docs/design/journal-j1-grid.md
/// §2.1): ONE payload renders the whole grid — opening hours + breaks for the
/// weekday, the artist columns, and the day's appointments (all statuses)
/// enriched with `salonClientId` / `clientNoShowCount` / `arrivedAt`.
///
/// Ownership: the caller's account must manage [providerId] (threat T41 —
/// deny by default; a day of client names+phones is exactly what a cross-salon
/// attacker would want). Day boundaries are UTC — Côte d'Ivoire runs on
/// Africa/Abidjan = UTC+0 today; revisit when MyWeli leaves that zone.
class JournalService {
  JournalService(
    this._members,
    this._providers,
    this._appointments,
    this._clients,
  );

  final MembershipService _members;
  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final ClientsService _clients;

  Future<JournalResult> dayFor(
    String accountId,
    String providerId,
    DateTime date,
  ) async {
    if (!await _members.can(accountId, providerId, Cap.journalViewAll)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'not_found', data: null);
    }

    final day = DateTime.utc(date.year, date.month, date.day);
    final availability =
        (provider['availability'] as Map?)?.cast<String, dynamic>() ?? {};

    // The day's appointments (every status — the web toggles cancelled
    // ghosts client-side), enriched for the grid + panel.
    final all = await _appointments.listForProvider(providerId);
    final todays =
        [
          for (final a in all)
            if (_sameUtcDay(a['appointmentDate'] as String?, day)) a,
        ]..sort(
          (a, b) => (a['appointmentDate'] as String).compareTo(
            b['appointmentDate'] as String,
          ),
        );
    final enriched = await _clients.enrichForProvider(providerId, todays);

    return (
      ok: true,
      error: null,
      data: {
        'date':
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
        'hours': _hoursFor(availability, day),
        'artists': [
          for (final a
              in ((provider['artists'] as List?) ?? const [])
                  .cast<Map<String, dynamic>>())
            {'id': a['id'], 'name': a['name'], 'imageUrl': a['imageUrl']},
        ],
        'appointments': enriched,
      },
    );
  }

  /// `{open, close, breaks[]}` for the weekday, or null when the salon is
  /// closed (no available template slots, or the date is blocked) — the grid
  /// then renders a neutral axis (spec §2.1).
  Map<String, dynamic>? _hoursFor(
    Map<String, dynamic> availability,
    DateTime day,
  ) {
    final blocked = ((availability['blockedDates'] as List?) ?? const []).any(
      (d) => _sameUtcDay(d as String?, day),
    );
    if (blocked) return null;

    final weekday = '${day.weekday - 1}'; // Mon=1..Sun=7 → '0'..'6'
    final template =
        (((availability['weeklySchedule'] as Map?)?[weekday] as List?) ??
                const [])
            .cast<Map<String, dynamic>>();
    int? openMin;
    int? closeMin;
    for (final slot in template) {
      if (slot['isAvailable'] == false) continue;
      final s = DateTime.tryParse(slot['startTime'] as String? ?? '');
      final e = DateTime.tryParse(slot['endTime'] as String? ?? '');
      if (s == null) continue;
      final sMin = s.hour * 60 + s.minute;
      final eMin = e == null ? sMin + 30 : e.hour * 60 + e.minute;
      openMin = openMin == null || sMin < openMin ? sMin : openMin;
      closeMin = closeMin == null || eMin > closeMin ? eMin : closeMin;
    }
    if (openMin == null || closeMin == null) return null;

    final breaks =
        (((availability['breaks'] as Map?)?[weekday] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    return {
      'open': _hhmm(openMin),
      'close': _hhmm(closeMin),
      'breaks': [
        for (final b in breaks)
          (() {
            final s = DateTime.tryParse(b['startTime'] as String? ?? '');
            final e = DateTime.tryParse(b['endTime'] as String? ?? '');
            return {
              'start': s == null ? '00:00' : _hhmm(s.hour * 60 + s.minute),
              'end': e == null ? '00:00' : _hhmm(e.hour * 60 + e.minute),
            };
          })(),
      ],
    };
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static bool _sameUtcDay(String? iso, DateTime day) {
    final t = iso == null ? null : DateTime.tryParse(iso)?.toUtc();
    return t != null &&
        t.year == day.year &&
        t.month == day.month &&
        t.day == day.day;
  }
}
