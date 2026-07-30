import '../providers_repository.dart';
import '../salon_time.dart';
import 'appointment_repository.dart';

typedef SlotResult = ({bool ok, String? error, List<DateTime>? slots});

/// Server-authoritative availability (docs/BACKEND.md §3.4 + the capacity
/// model of docs/design/booking-capacity-web-hub.md). Computes bookable start
/// times for a provider on a date from its weekly schedule, honouring blocked
/// dates, breaks, a setup/cleanup buffer, the requested duration, existing
/// (non-cancelled) bookings — and, when the salon has artists, **per-artist
/// capacity**:
///
/// - [artistId] given → the slot must be free for THAT artist: capable of the
///   selected services, inside their working hours (when defined), no
///   overlapping booking assigned to them, and the unassigned load must still
///   leave a chair.
/// - No [artistId] (« Sans préférence ») → the slot is free while at least
///   one capable artist remains after subtracting artists busy with assigned
///   bookings AND one chair per overlapping unassigned booking. **When every
///   chair is taken, « Sans préférence » is NOT bookable either.**
/// - A salon with no artists keeps the v1 single-chair behaviour.
///
/// Instants are UTC; the `?date=` calendar day, the today/past gates and the
/// weekly-hour wall-clocks are interpreted in the SALON's timezone
/// (multi-pays MP1 — salon_time.dart; Abidjan = UTC+0 keeps Wave-0 salons
/// bit-identical).
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
    String? artistId,
  }) async {
    final provider = await _providers.byId(providerId);
    if (provider == null) {
      return (ok: false, error: 'provider_not_found', slots: null);
    }

    final artists = ((provider['artists'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final wantedArtist = (artistId == null || artistId.isEmpty)
        ? null
        : artistId;
    if (wantedArtist != null && !artists.any((a) => a['id'] == wantedArtist)) {
      return (ok: false, error: 'invalid_artist', slots: null);
    }

    final tzName = provider['timezone'] as String?;
    // The requested calendar day + « today », both as SALON days.
    final dayBounds = salonCalendarDayBoundsUtc(date, tzName);
    final now = DateTime.now().toUtc();
    final todayBounds = salonDayBoundsUtc(now, tzName);
    if (dayBounds.startUtc.isBefore(todayBounds.startUtc)) {
      return (ok: true, error: null, slots: const <DateTime>[]);
    }

    final availability = (provider['availability'] as Map)
        .cast<String, dynamic>();

    // Blocked dates name SALON calendar days.
    final isBlocked = (availability['blockedDates'] as List? ?? const [])
        .map((d) => salonWallClock(DateTime.parse(d as String), tzName))
        .any(
          (d) =>
              d.year == date.year && d.month == date.month && d.day == date.day,
        );
    if (isBlocked) return (ok: true, error: null, slots: const <DateTime>[]);

    // Weekday of the requested calendar date (pure field math).
    final weekday =
        '${DateTime.utc(date.year, date.month, date.day).weekday - 1}';
    final open = _openMinutes(availability['weeklySchedule'], weekday);
    if (open.isEmpty) return (ok: true, error: null, slots: const <DateTime>[]);

    final duration = durationMinutes ?? _durationFor(provider, serviceIds);
    final blocks = (duration / _step).ceil().clamp(1, 48);
    final buffer = (availability['bufferMinutes'] as num?)?.toInt() ?? 0;
    final breaks = _windowsFor(availability['breaks'], weekday);
    final busy = await _busyWindows(provider, date, tzName, buffer, providerId);

    // Capacity inputs. Capable = can do every selected service (a selection
    // containing an unrestricted service is open to all — the app's rule).
    final capable = [
      for (final a in artists)
        if (_artistCapable(provider, a, serviceIds)) a,
    ];
    if (wantedArtist != null && !capable.any((a) => a['id'] == wantedArtist)) {
      // The requested artist can't perform the selection → no slots.
      return (ok: true, error: null, slots: const <DateTime>[]);
    }

    // For today, only offer starts ≥ 1h from now (minutes past SALON midnight).
    final minStartMinute =
        dayBounds.startUtc.isAtSameMomentAs(todayBounds.startUtc)
        ? now.difference(dayBounds.startUtc).inMinutes + 60
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

      // Wall-clock minutes on the SALON's calendar day → UTC instants.
      final start = salonWallClockToUtc(
        date.year,
        date.month,
        date.day,
        startMin,
        tzName,
      );
      final end = salonWallClockToUtc(
        date.year,
        date.month,
        date.day,
        endMin,
        tzName,
      );
      bool overlaps(({DateTime start, DateTime end, String? artistId}) w) =>
          start.isBefore(w.end) && end.isAfter(w.start);

      if (artists.isEmpty) {
        // v1 single-chair salon: any overlap blocks the slot.
        if (busy.any(overlaps)) continue;
        slots.add(start);
        continue;
      }

      // The capable artists whose hours cover [start,end) and who have no
      // ASSIGNED overlapping booking…
      final freeCapable = [
        for (final a in capable)
          if (_hoursCover(a, weekday, startMin, endMin) &&
              !busy.any((w) => w.artistId == a['id'] && overlaps(w)))
            a,
      ];
      // …minus one chair per overlapping UNASSIGNED booking (someone must
      // serve them). Every chair spoken for → nothing bookable, including
      // « Sans préférence ».
      final unassignedOverlap = busy
          .where((w) => w.artistId == null && overlaps(w))
          .length;
      if (freeCapable.length - unassignedOverlap < 1) continue;
      if (wantedArtist != null &&
          !freeCapable.any((a) => a['id'] == wantedArtist)) {
        continue; // the requested artist specifically isn't free
      }

      slots.add(start);
    }
    return (ok: true, error: null, slots: slots);
  }

  /// Mirrors the app's `_artistCanDoServices`: empty selection → capable; a
  /// selection containing an unrestricted service (no `artistIds`) → capable;
  /// else the artist must be listed on every selected service.
  bool _artistCapable(
    Map<dynamic, dynamic> provider,
    Map<String, dynamic> artist,
    List<String>? serviceIds,
  ) {
    if (serviceIds == null || serviceIds.isEmpty) return true;
    final services = (provider['services'] as List)
        .cast<Map<String, dynamic>>()
        .where((s) => serviceIds.contains(s['id']))
        .toList();
    if (services.isEmpty) return true;
    final unrestricted = services.any(
      (s) => ((s['artistIds'] as List?) ?? const []).isEmpty,
    );
    if (unrestricted) return true;
    final id = artist['id'];
    return services.every(
      (s) => ((s['artistIds'] as List?) ?? const []).contains(id),
    );
  }

  /// Does the artist's own schedule cover [startMin, endMin) on [weekday]?
  /// An artist whose `workingHours` is entirely empty inherits the salon's
  /// hours (the salon template already gated the slot). An artist WITH hours
  /// but none on this weekday is off that day.
  bool _hoursCover(
    Map<String, dynamic> artist,
    String weekday,
    int startMin,
    int endMin,
  ) {
    final hours = (artist['workingHours'] as Map?)?.cast<String, dynamic>();
    if (hours == null || hours.isEmpty) return true;
    final windows = _mergedWindows(hours[weekday]);
    return windows.any((w) => startMin >= w.$1 && endMin <= w.$2);
  }

  /// Merges the weekday's available windows (adjacent/overlapping template
  /// slots union into continuous coverage).
  List<(int, int)> _mergedWindows(Object? entries) {
    final list = ((entries as List?) ?? const []).cast<Map<String, dynamic>>();
    final raw = <(int, int)>[];
    for (final s in list) {
      if (s['isAvailable'] == false) continue;
      final st = DateTime.parse(s['startTime'] as String);
      final en = DateTime.parse(s['endTime'] as String);
      raw.add((st.hour * 60 + st.minute, en.hour * 60 + en.minute));
    }
    raw.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final w in raw) {
      if (merged.isNotEmpty && w.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, w.$2 > last.$2 ? w.$2 : last.$2));
      } else {
        merged.add(w);
      }
    }
    return merged;
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

  /// Buffer-padded busy windows from existing non-cancelled bookings on the
  /// requested SALON calendar [date], each tagged with its assigned artist
  /// (null = « Sans préférence », consuming one chair from the pool). Uses
  /// the booking's stored `durationMinutes` when present (variant-accurate),
  /// else recomputes.
  Future<List<({DateTime start, DateTime end, String? artistId})>> _busyWindows(
    Map<dynamic, dynamic> provider,
    DateTime date,
    String? tzName,
    int buffer,
    String providerId,
  ) async {
    final appts = await _appointments.listForProvider(providerId);
    final windows = <({DateTime start, DateTime end, String? artistId})>[];
    for (final a in appts) {
      if (a['status'] == 'cancelled') continue;
      final start = DateTime.parse(a['appointmentDate'] as String).toUtc();
      final wall = salonWallClock(start, tzName);
      if (wall.year != date.year ||
          wall.month != date.month ||
          wall.day != date.day) {
        continue;
      }
      final dur =
          (a['durationMinutes'] as num?)?.toInt() ??
          _durationFor(provider, (a['serviceIds'] as List?)?.cast<String>());
      windows.add((
        start: start.subtract(Duration(minutes: buffer)),
        end: start.add(Duration(minutes: dur + buffer)),
        artistId: a['artistId'] as String?,
      ));
    }
    return windows;
  }
}
