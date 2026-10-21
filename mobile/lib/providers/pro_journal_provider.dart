import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/app_clock.dart';
import '../core/utils/salon_time.dart';
import '../models/api_response.dart';
import '../models/appointment.dart';
import '../models/journal_day.dart';
import '../services/interfaces/pro_service_interface.dart';

/// State for « Ma journée » — the pro-app day timeline (module `journal` J1b,
/// docs/design/journal-j1b-app.md). One journal fetch per day; the artist
/// filter, cancelled toggle and week-count dots are in-memory.
///
/// It is told when the salon creates a booking ([bookingCreated],
/// docs/design/pro-journal-shows-new-booking.md): the day shows it at once,
/// then reloads quietly, and the server's answer wins.
class ProJournalProvider extends ChangeNotifier implements ShowsSalonBookings {
  final ProServiceInterface _service = serviceLocator.proService;

  String _providerId = '';

  /// The ACTIVE salon's IANA timezone (multi-pays MP2) — set by [load] from
  /// `ProAuthProvider.salonTimezone`; null = Africa/Abidjan (Wave 0).
  String? _tz;
  bool _loadedOnce = false;

  JournalDay? _day;
  JournalDay? get day => _day;

  /// The salon day [_day] was loaded FOR — [keyOf] the selected date when its
  /// answer was applied. It differs from the selected date only while a day
  /// CHANGE is in flight: the date has moved and the rows on screen are still
  /// the previous day's. Held here rather than read from `JournalDay.date`, so
  /// that where a created booking goes never depends on how a server spells
  /// a date. Read only while [_day] is non-null, and written with it.
  String? _dayKey;

  // Abidjan seed; re-derived with the real salon tz on the first [load].
  DateTime _selectedDate = salonToday();
  DateTime get selectedDate => _selectedDate;

  /// Artist filter: null = « Tous »; '' = « Sans artiste ».
  String? _artistFilter;
  String? get artistFilter => _artistFilter;

  /// Collaborateur own-mode (access R4b): the filter is LOCKED to the
  /// member's linked artist — [setArtistFilter] no-ops while locked
  /// (belt-and-braces; the server already own-filters, T40).
  bool _locked = false;
  bool get isLocked => _locked;

  void lockToArtist(String artistId) {
    _locked = true;
    if (_artistFilter != artistId) {
      _artistFilter = artistId;
      notifyListeners();
    }
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    _artistFilter = null;
    notifyListeners();
  }

  bool _showCancelled = false;
  bool get showCancelled => _showCancelled;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String? _error;
  String? get error => _error;

  /// The sequence number of the newest day request — a loud [load], the quiet
  /// reload after [bookingCreated], or a salon switch, which asks for nothing
  /// but must outdate whatever is in flight.
  ///
  /// **Only the newest request's answer is applied** (the booking hub's
  /// `slotsRequestId` idea). Without it an answer computed BEFORE a booking
  /// existed — a pull-to-refresh still in flight, say — could land after the
  /// booking was shown and erase it; and two quick day changes could leave
  /// the slower day's rows under the faster day's date, which was already
  /// possible before this field existed.
  int _request = 0;

  /// Booking counts per 'YYYY-MM-DD' for the week strip's load dots.
  final Map<String, int> _weekCounts = {};
  Map<String, int> get weekCounts => Map.unmodifiable(_weekCounts);

  DateTime _todayUtc() => salonToday(tz: _tz);

  /// The salon day key of an instant — also applied to date-only MARKERS
  /// (selected date, week-strip days), which is safe for the UTC+0/+1
  /// francophone-Africa scope (a midnight-UTC marker stays inside its salon
  /// day) but would shift west of UTC.
  String keyOf(DateTime d) => salonDayKey(d, tz: _tz);

  /// Today's salon day key (the « Aujourd'hui » header check).
  String get todayKey => keyOf(AppClock.now());

  /// The visible (filtered) bookings, time-ascending; cancelled hidden unless
  /// [showCancelled].
  List<Appointment> get visibleAppointments {
    final all = _day?.appointments ?? const <Appointment>[];
    return all.where((a) {
      if (!_showCancelled && a.status == AppointmentStatus.cancelled) {
        return false;
      }
      if (_artistFilter == null) return true;
      return (a.artistId ?? '') == _artistFilter;
    }).toList()..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  bool get hasUnassigned =>
      (_day?.appointments ?? const []).any((a) => a.artistId == null);

  Future<void> load(String providerId, {DateTime? date, String? tz}) async {
    _providerId = providerId;
    if (tz != null) _tz = tz;
    if (date != null) {
      _selectedDate = date;
    } else if (!_loadedOnce) {
      // First load only: anchor « aujourd'hui » in the REAL salon tz. A
      // no-date reload after an error must NOT jump the date back to today.
      _selectedDate = _todayUtc();
    }
    _loadedOnce = true;
    final request = ++_request;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final r = await _service.getJournalDay(providerId, _selectedDate);
      // Outdated: a newer request owns the state, `isLoading` included.
      if (request != _request) return;
      if (r.success && r.data != null) {
        _day = r.data;
        _dayKey = keyOf(_selectedDate);
      } else {
        _error = r.error ?? 'Erreur lors du chargement.';
        ProAccessGuard.report(r.code);
        _day = null;
      }
    } catch (e) {
      if (request != _request) return;
      _error = kGenericErrorMessage;
      _day = null;
    }
    _isLoading = false;
    notifyListeners();
    unawaited(_prefetchWeekCounts(request));
  }

  Future<void> refresh() => load(_providerId, date: _selectedDate);

  void setDate(DateTime date) => load(_providerId, date: date);

  void setArtistFilter(String? artistId) {
    if (_locked) return; // own-mode: the lock wins
    _artistFilter = artistId;
    notifyListeners();
  }

  void toggleCancelled() {
    _showCancelled = !_showCancelled;
    notifyListeners();
  }

  // ---- Actions: act, then the change everywhere ---------------------------
  //
  // docs/design/app-pro-home-journal-fresh.md §2.1 (owner decision 8): once
  // the server accepts a gesture, the row changes at once and the day is read
  // again quietly — it used to be read again the ordinary way, and a failed
  // read then dropped the whole day for « Une erreur est survenue » although
  // the gesture had succeeded. The other stores (« Accueil », the client card,
  // the « Rendez-vous » list) hear it through [ProSalonScope.bookingChanged].

  Future<bool> accept(String id) => _act(
    id,
    BookingChangeKind.accepted,
    () => _service.acceptAppointment(id),
  );

  /// Refuse a PENDING request — the server's `reject` (→ `cancelled`, and the
  /// client is told « Réservation refusée »). Never `noShow`: « Refuser » used
  /// to call it, recording the request as the client's absence
  /// (docs/design/app-journal-refuser.md).
  Future<bool> reject(String id) => _act(
    id,
    BookingChangeKind.rejected,
    () => _service.rejectAppointment(id, null),
  );
  Future<bool> complete(String id) => _act(
    id,
    BookingChangeKind.completed,
    () => _service.markAppointmentComplete(id),
  );
  Future<bool> noShow(String id) =>
      _act(id, BookingChangeKind.noShow, () => _service.markNoShow(id));
  Future<bool> arrive(String id) => _act(
    id,
    BookingChangeKind.arrived,
    () => _service.markArrived(id),
    // The server's own time replaces it with the quiet read.
    arrivedAt: AppClock.now(),
  );

  Future<bool> reschedule(String id, DateTime newDateTime) => _act(
    id,
    BookingChangeKind.rescheduled,
    () => _service.rescheduleAppointment(id, newDateTime),
    newDate: newDateTime,
  );

  Future<bool> _act(
    String id,
    BookingChangeKind kind,
    Future<ApiResponse<bool>> Function() run, {
    DateTime? newDate,
    DateTime? arrivedAt,
  }) async {
    try {
      final res = await run();
      if (!res.success) {
        _error = res.error ?? 'Action impossible.';
        ProAccessGuard.report(res.code);
        notifyListeners();
        return false;
      }
      final row = _day?.appointments.where((a) => a.id == id).firstOrNull;
      final change = BookingChange(
        appointmentId: id,
        providerId: _providerId,
        kind: kind,
        newDate: newDate,
        arrivedAt: arrivedAt,
        clientPhone: row?.clientPhone,
      );
      bookingChanged(change); // this day, at once — then a quiet read
      ProSalonScope.bookingChanged(change, except: this);
      return true;
    } catch (e) {
      _error = kGenericErrorMessage;
      notifyListeners();
      return false;
    }
  }

  // ---- A booking changed (HearsBookingChanges) -----------------------------

  /// [change] was accepted by the server — here or anywhere else in the app
  /// (docs/design/app-pro-home-journal-fresh.md §2.1). The row and its day's
  /// dot change at once; the day is then read again quietly, and the server's
  /// day replaces the local one. A failed read keeps the change.
  @override
  void bookingChanged(BookingChange change) {
    if (_providerId.isEmpty || change.providerId != _providerId) return;
    final day = _day;
    final selected = keyOf(_selectedDate);
    if (day == null || _dayKey != selected) {
      // No rows of the selected date to change (first load in flight, failed,
      // or a day change in flight): ask again the ordinary way — a request
      // sent now is answered after the change, and it outdates the one in
      // flight.
      notifyListeners();
      unawaited(load(_providerId, date: _selectedDate));
      return;
    }
    final i = day.appointments.indexWhere((a) => a.id == change.appointmentId);
    if (i != -1) {
      final before = day.appointments[i];
      final after = change.applyTo(before);
      final beforeKey = keyOf(before.appointmentDate);
      final afterKey = keyOf(after.appointmentDate);
      // The dots count what is not cancelled (`_load`): a refusal takes one
      // away, a move carries one to its new day.
      if (before.status != AppointmentStatus.cancelled) {
        final n = (_weekCounts[beforeKey] ?? 0) - 1;
        _weekCounts[beforeKey] = n < 0 ? 0 : n;
      }
      if (after.status != AppointmentStatus.cancelled) {
        _weekCounts[afterKey] = (_weekCounts[afterKey] ?? 0) + 1;
      }
      final rows = [...day.appointments];
      if (afterKey == selected) {
        rows[i] = after;
      } else {
        rows.removeAt(i); // moved to another day
      }
      _day = JournalDay(
        date: day.date,
        hours: day.hours,
        artists: day.artists,
        appointments: rows,
      );
    } else if (change.kind == BookingChangeKind.rescheduled &&
        change.newDate != null &&
        keyOf(change.newDate!) == selected) {
      // Moved INTO this day from another: its row is not here — the quiet
      // read brings it; its dot now.
      _weekCounts[selected] = (_weekCounts[selected] ?? 0) + 1;
    }
    // As for a creation: a refresh of this same day may be in flight, and its
    // answer may predate the change — the quiet read below outdates it, and
    // nobody else would lower the flag it raised.
    _isLoading = false;
    notifyListeners();
    unawaited(_reloadQuietly());
  }

  // ---- A booking was created (ShowsSalonBookings) --------------------------

  /// The salon just created [booking] — from « Ma journée » or from anywhere
  /// else in the app (docs/design/pro-journal-shows-new-booking.md §2).
  ///
  /// The booking is added to the DAY, not to the visible list: the artist
  /// filter and « Voir les annulés » apply to it like to any other row, so a
  /// booking the filter excludes is not shown.
  @override
  void bookingCreated(Appointment booking) {
    // Never opened, or another salon's: there is no day here to keep right.
    if (_providerId.isEmpty || booking.providerId != _providerId) return;

    final key = keyOf(booking.appointmentDate);
    final day = _day;
    if (day != null && day.appointments.any((a) => a.id == booking.id)) {
      return; // announced twice — it is already there, and already counted
    }
    // Its day's dot, at once — also when that day is not the displayed one.
    // The week prefetch that follows the reload replaces it with the
    // server's count.
    _weekCounts[key] = (_weekCounts[key] ?? 0) + 1;

    final selected = keyOf(_selectedDate);
    if (day == null || _dayKey != selected) {
      // No rows of the selected date to add one to: its first load is still
      // in flight, it failed, or a day CHANGE is in flight and the rows on
      // screen are another date's. Ask again the ordinary way — a request
      // sent now is answered after the booking exists, and it outdates the
      // one in flight. When it fails, the error state is the ordinary one:
      // there is no day of that date to keep.
      notifyListeners();
      unawaited(load(_providerId, date: _selectedDate));
      return;
    }

    if (key == selected) {
      _day = JournalDay(
        date: day.date,
        hours: day.hours,
        artists: day.artists,
        appointments: [...day.appointments, booking],
      );
    }
    // A refresh of this same day may be in flight — a pull-to-refresh, the
    // refetch behind a swipe action, « Ma journée » reopened. Its answer may
    // have been computed before the booking existed, and its FAILURE would
    // drop the day: the quiet reload below outdates it. Nobody else will
    // lower the flag it raised.
    _isLoading = false;
    notifyListeners();
    unawaited(_reloadQuietly());
  }

  /// The reload behind a booking that is already on screen: no loader, no
  /// error state, and the rows stay where they are while it runs.
  ///
  /// It never touches [_isLoading] or [_error], so the screen cannot fall back
  /// to its loader or to « Une erreur est survenue » because of it. On success
  /// the server's day REPLACES the local one — including when the booking is
  /// no longer in it. On failure nothing changes.
  Future<void> _reloadQuietly() async {
    final request = ++_request;
    try {
      final r = await _service.getJournalDay(_providerId, _selectedDate);
      if (request != _request) return;
      if (!r.success || r.data == null) {
        // Quiet for the salon, not for the access seam: a member revoked
        // meanwhile is still signed out.
        ProAccessGuard.report(r.code);
        return;
      }
      _day = r.data;
      notifyListeners();
    } catch (_) {
      return; // offline — the booking stays; the next visit reconciles
    }
    unawaited(_prefetchWeekCounts(request));
  }

  /// A day's dot: its bookings that are not cancelled. The day hides those
  /// by default, so counting them left a dot on a day that opens empty
  /// (docs/design/web-pro-week-strip.md §6, owner Q2 — the web counts alike).
  static int _load(List<Appointment> appointments) =>
      appointments.where((a) => a.status != AppointmentStatus.cancelled).length;

  /// One light 7-day prefetch (module decision §8.2) — fills the week-strip
  /// dots. Best-effort; never blocks the timeline.
  ///
  /// It belongs to the day request numbered [request] and stops as soon as a
  /// newer one starts: otherwise a count asked for before a booking existed
  /// could be written over the dot that booking just received.
  Future<void> _prefetchWeekCounts(int request) async {
    try {
      final monday = _selectedDate.subtract(
        Duration(days: (_selectedDate.weekday - 1)),
      );
      for (var i = 0; i < 7; i++) {
        final d = monday.add(Duration(days: i));
        final key = keyOf(d);
        if (key == keyOf(_selectedDate) && _day != null) {
          _weekCounts[key] = _load(_day!.appointments);
          continue;
        }
        final r = await _service.getJournalDay(_providerId, d);
        if (request != _request) return;
        if (r.success && r.data != null) {
          _weekCounts[key] = _load(r.data!.appointments);
        }
      }
      notifyListeners();
    } catch (_) {
      /* best-effort — dots are non-critical */
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _request++; // whatever is in flight was asked for the previous salon
    _providerId = '';
    _tz = null; // the next salon's tz arrives with its first load
    _loadedOnce = false;
    _day = null;
    _selectedDate = _todayUtc();
    _artistFilter = null;
    _locked = false;
    _showCancelled = false;
    _isLoading = false;
    _error = null;
    _weekCounts.clear();
    notifyListeners();
  }
}
