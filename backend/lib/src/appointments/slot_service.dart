import '../providers_repository.dart';
import 'appointment_repository.dart';

typedef SlotResult = ({bool ok, String? error, List<DateTime>? slots});

/// Server-authoritative availability (docs/BACKEND.md §3.4). Computes bookable
/// start times for a provider on a date from its weekly schedule, honouring
/// blocked dates, breaks, a setup/cleanup buffer, the requested duration, and
/// existing (non-cancelled) bookings — so the server, not the client, decides
/// what's free. All times are UTC (Côte d'Ivoire is UTC+0).
///
/// v1 is **provider-level** (one chair): per-artist working hours + eligible-
/// artist-by-service resolution is a follow-up. Mirrors the app's mock engine.
class SlotService {
  SlotService(this._providers, this._appointments);

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;

  static const int _step = 30; // opening-slot granularity, minutes

  Future<SlotResult> availableSlots({
    required String providerId,
    required DateTime date,
    List<String>? serviceIds,
    int? durationMinutes,
  }) async {
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'provider_not_found', slots: null);
    }

    final day = DateTime.utc(date.year, date.month, date.day);
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    if (day.isBefore(today)) {
      return (ok: true, error: null, slots: const <DateTime>[]);
    }

    final availability = (provider['availability'] as Map)
        .cast<String, dynamic>();

    final isBlocked = (availability['blockedDates'] as List? ?? const [])
        .map((d) => DateTime.parse(d as String).toUtc())
        .any(
          (d) => d.year == day.year && d.month == day.month && d.day == day.day,
        );
    if (isBlocked) return (ok: true, error: null, slots: const <DateTime>[]);

    final weekday = '${day.weekday - 1}'; // Mon=1..Sun=7 → '0'..'6'
    final open = _openMinutes(availability['weeklySchedule'], weekday);
    if (open.isEmpty) return (ok: true, error: null, slots: const <DateTime>[]);

    final duration = durationMinutes ?? _durationFor(provider, serviceIds);
    final blocks = (duration / _step).ceil().clamp(1, 48);
    final buffer = (availability['bufferMinutes'] as num?)?.toInt() ?? 0;
    final breaks = _windowsFor(availability['breaks'], weekday);
    final busy = await _busyWindows(provider, day, buffer, providerId);

    // For today, only offer starts ≥ 1h from now.
    final minStartMinute = day.isAtSameMomentAs(today)
        ? now.difference(day).inMinutes + 60
        : -1;

    final slots = <DateTime>[];
    for (final startMin in open.toList()..sort()) {
      if (startMin < minStartMinute) continue;
      final endMin = startMin + duration;

      // The whole duration must be covered by consecutive open 30-min slots.
      var covered = true;
      for (var i = 0; i < blocks; i++) {
        if (!open.contains(startMin + _step * i)) {
          covered = false;
          break;
        }
      }
      if (!covered) continue;

      // Not inside a break.
      if (breaks.any((b) => startMin < b.$2 && endMin > b.$1)) continue;

      final start = day.add(Duration(minutes: startMin));
      final end = day.add(Duration(minutes: endMin));
      // Not overlapping an existing (buffer-padded) booking.
      if (busy.any((w) => start.isBefore(w.$2) && end.isAfter(w.$1))) continue;

      slots.add(start);
    }
    return (ok: true, error: null, slots: slots);
  }

  /// Open 30-min start minutes-of-day for [weekday].
  Set<int> _openMinutes(Object? weeklySchedule, String weekday) {
    final schedule = (weeklySchedule as Map?)?.cast<String, dynamic>() ?? {};
    final template = (schedule[weekday] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final open = <int>{};
    for (final s in template) {
      if (s['isAvailable'] == false) continue;
      final t = DateTime.parse(s['startTime'] as String);
      open.add(t.hour * 60 + t.minute);
    }
    return open;
  }

  /// `(startMinute, endMinute)` windows for [weekday] (used for breaks).
  List<(int, int)> _windowsFor(Object? schedule, String weekday) {
    final map = (schedule as Map?)?.cast<String, dynamic>() ?? {};
    final list = (map[weekday] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final w in list)
        (() {
          final s = DateTime.parse(w['startTime'] as String);
          final e = DateTime.parse(w['endTime'] as String);
          return (s.hour * 60 + s.minute, e.hour * 60 + e.minute);
        }()),
    ];
  }

  int _durationFor(Map<dynamic, dynamic> provider, List<String>? serviceIds) {
    if (serviceIds == null || serviceIds.isEmpty) return _step;
    final services = (provider['services'] as List)
        .cast<Map<String, dynamic>>();
    var total = 0;
    for (final id in serviceIds) {
      for (final s in services) {
        if (s['id'] == id) {
          total += (s['durationMinutes'] as num?)?.toInt() ?? 0;
          break;
        }
      }
    }
    return total == 0 ? _step : total;
  }

  /// Buffer-padded busy windows from existing non-cancelled bookings on [day].
  Future<List<(DateTime, DateTime)>> _busyWindows(
    Map<dynamic, dynamic> provider,
    DateTime day,
    int buffer,
    String providerId,
  ) async {
    final appts = await _appointments.listForProvider(providerId);
    final windows = <(DateTime, DateTime)>[];
    for (final a in appts) {
      if (a['status'] == 'cancelled') continue;
      final start = DateTime.parse(a['appointmentDate'] as String).toUtc();
      if (start.year != day.year ||
          start.month != day.month ||
          start.day != day.day) {
        continue;
      }
      final dur = _durationFor(
        provider,
        (a['serviceIds'] as List?)?.cast<String>(),
      );
      windows.add((
        start.subtract(Duration(minutes: buffer)),
        start.add(Duration(minutes: dur + buffer)),
      ));
    }
    return windows;
  }
}
