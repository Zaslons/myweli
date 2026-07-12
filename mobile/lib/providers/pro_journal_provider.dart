import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/appointment.dart';
import '../models/journal_day.dart';
import '../services/interfaces/pro_service_interface.dart';

/// State for « Ma journée » — the pro-app day timeline (module `journal` J1b,
/// docs/design/journal-j1b-app.md). One journal fetch per day; the artist
/// filter, cancelled toggle and week-count dots are in-memory.
class ProJournalProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _service = serviceLocator.proService;

  String _providerId = '';

  JournalDay? _day;
  JournalDay? get day => _day;

  DateTime _selectedDate = _todayUtc();
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

  /// Booking counts per 'YYYY-MM-DD' for the week strip's load dots.
  final Map<String, int> _weekCounts = {};
  Map<String, int> get weekCounts => Map.unmodifiable(_weekCounts);

  static DateTime _todayUtc() {
    final n = DateTime.now().toUtc();
    return DateTime.utc(n.year, n.month, n.day);
  }

  static String keyOf(DateTime d) =>
      d.toUtc().toIso8601String().substring(0, 10);

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
    }).toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  bool get hasUnassigned =>
      (_day?.appointments ?? const []).any((a) => a.artistId == null);

  Future<void> load(String providerId, {DateTime? date}) async {
    _providerId = providerId;
    if (date != null) _selectedDate = date;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final r = await _service.getJournalDay(providerId, _selectedDate);
      if (r.success && r.data != null) {
        _day = r.data;
      } else {
        _error = r.error ?? 'Erreur lors du chargement.';
        ProAccessGuard.report(r.code);
        _day = null;
      }
    } catch (e) {
      _error = e.toString();
      _day = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    unawaited(_prefetchWeekCounts());
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

  // ---- Actions (optimistic-ish: act then refetch the day) ------------------

  Future<bool> accept(String id) => _act(() => _service.acceptAppointment(id));
  Future<bool> complete(String id) =>
      _act(() => _service.markAppointmentComplete(id));
  Future<bool> noShow(String id) => _act(() => _service.markNoShow(id));
  Future<bool> arrive(String id) => _act(() => _service.markArrived(id));

  Future<bool> reschedule(String id, DateTime newDateTime) => _act(
        () => _service.rescheduleAppointment(id, newDateTime),
      );

  Future<bool> _act(Future<ApiResponse<bool>> Function() run) async {
    try {
      final res = await run();
      final ok = res.success;
      if (ok) {
        await refresh();
      } else {
        _error = res.error ?? 'Action impossible.';
        ProAccessGuard.report(res.code);
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// One light 7-day prefetch (module decision §8.2) — fills the week-strip
  /// dots. Best-effort; never blocks the timeline.
  Future<void> _prefetchWeekCounts() async {
    try {
      final monday = _selectedDate.subtract(
        Duration(days: (_selectedDate.weekday - 1)),
      );
      for (var i = 0; i < 7; i++) {
        final d = monday.add(Duration(days: i));
        final key = keyOf(d);
        if (key == keyOf(_selectedDate) && _day != null) {
          _weekCounts[key] = _day!.appointments.length;
          continue;
        }
        final r = await _service.getJournalDay(_providerId, d);
        if (r.success && r.data != null) {
          _weekCounts[key] = r.data!.appointments.length;
        }
      }
      notifyListeners();
    } catch (_) {/* best-effort — dots are non-critical */}
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _providerId = '';
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
