import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/appointment.dart';
import '../services/interfaces/pro_service_interface.dart';

/// The home figures — « Aujourd’hui · N · Rendez-vous », the revenue cards.
///
/// « Accueil » is the root of the stack and these figures are fetched once per
/// salon, so they are told when the salon creates a booking ([bookingCreated],
/// docs/design/pro-journal-shows-new-booking.md §2.5).
class ProDashboardProvider extends ChangeNotifier
    implements ShowsSalonBookings {
  final ProServiceInterface _proService = serviceLocator.proService;

  DashboardStats? _stats;
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  /// A booking was created after [_stats] was fetched and the figures have not
  /// been confirmed by the server since.
  bool _stale = false;

  /// The newest quiet refetch; an older one's answer is dropped.
  int _quietRequest = 0;

  /// The newest ordinary load; an older one's answer — another salon's, after
  /// a switch — is dropped, its loader flag included (B1.3,
  /// docs/design/app-pro-home-journal-fresh.md §2.4).
  int _loadRequest = 0;

  /// The last failed pull's sentence, said once by the screen.
  String? _refreshFailure;

  /// The error state's load got no answer at all (vs. a refusal).
  bool _errorIsOffline = false;

  /// The service's own sentence when nothing answered, and the generic one
  /// (docs/design/app-pro-home-journal-fresh.md §9 — owner Q4).
  static const noConnection = 'Pas de connexion. Réessayez.';
  static const failedRetry = 'Une erreur est survenue. Réessayez.';

  DashboardStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The error state says « Pas de connexion. Réessayez. » under its title
  /// only when nothing answered — never the failure's own text.
  bool get errorIsOffline => _errorIsOffline;

  /// The last failed pull's sentence — once: a second read is null.
  String? takeRefreshFailure() {
    final f = _refreshFailure;
    _refreshFailure = null;
    return f;
  }

  /// Entering « Accueil »: what is loaded for this salon is used as it is —
  /// unless a booking created since was never confirmed by the server. Only
  /// the pull ([refresh]) always asks.
  Future<void> loadDashboardStats(String providerId) async {
    if (_currentProviderId == providerId && _stats != null && !_isLoading) {
      if (_stale) await _refetchQuietly();
      return;
    }
    await _load(providerId);
  }

  /// The pull (owner decision 9): it always asks the server. With figures on
  /// screen, quietly — the answer replaces them; a failure KEEPS them and
  /// leaves the reason for the screen to say once. Without figures, the
  /// ordinary load.
  Future<void> refresh(String providerId) async {
    if (_currentProviderId != providerId || _stats == null || _isLoading) {
      await _load(providerId);
      return;
    }
    final request = ++_quietRequest;
    try {
      final response = await _proService.getDashboardStats(providerId);
      if (request != _quietRequest) return;
      if (response.success && response.data != null) {
        _stats = response.data;
        _stale = false;
        notifyListeners();
        return;
      }
      ProAccessGuard.report(response.code);
      _refreshFailure = response.code == 'network' ? noConnection : failedRetry;
    } catch (_) {
      if (request != _quietRequest) return;
      _refreshFailure = failedRetry;
    }
    notifyListeners();
  }

  Future<void> _load(String providerId) async {
    // A fresh load: what it brings is not stale, and a quiet refetch still in
    // flight was asked before it — possibly for another salon.
    _stale = false;
    _quietRequest++;
    final request = ++_loadRequest;
    _isLoading = true;
    _error = null;
    _errorIsOffline = false;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      final response = await _proService.getDashboardStats(providerId);
      // Outdated: a newer load — or a salon switch — owns the state, its
      // loader flag included.
      if (request != _loadRequest) return;
      if (response.success && response.data != null) {
        _stats = response.data;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des statistiques';
        _errorIsOffline = response.code == 'network';
        ProAccessGuard.report(response.code);
        _stats = null;
      }
    } catch (e) {
      if (request != _loadRequest) return;
      _error = e.toString();
      _stats = null;
    }
    _isLoading = false;
    notifyListeners();
    // A booking was created while this was in flight: its answer may have
    // been computed before the booking existed.
    if (_stale && _stats != null) await _refetchQuietly();
  }

  /// The salon just created [booking]: the counts and the revenue it feeds
  /// are the server's to compute, so nothing is guessed here — the figures
  /// are asked for again, without a loader and without an error state.
  @override
  void bookingCreated(Appointment booking) => _figuresMoved(booking.providerId);

  /// A booking changed elsewhere (docs/design/app-pro-home-journal-fresh.md
  /// §2.1): the same quiet refetch — a confirmed request leaves « Demandes »,
  /// a refusal leaves the day's count.
  @override
  void bookingChanged(BookingChange change) => _figuresMoved(change.providerId);

  void _figuresMoved(String providerId) {
    if (providerId != _currentProviderId) return;
    if (_stats == null && !_isLoading) return; // nothing shown, nothing stale
    _stale = true;
    // A loud load in flight refetches when it lands (above).
    if (!_isLoading) unawaited(_refetchQuietly());
  }

  /// Keeps the cards on screen while it runs; on failure they keep their
  /// numbers and [_stale] stays set for the next pull-to-refresh.
  Future<void> _refetchQuietly() async {
    final providerId = _currentProviderId;
    if (providerId == null) return;
    final request = ++_quietRequest;
    try {
      final response = await _proService.getDashboardStats(providerId);
      if (request != _quietRequest) return;
      if (response.success && response.data != null) {
        _stats = response.data;
        _stale = false;
        notifyListeners();
      } else {
        ProAccessGuard.report(response.code);
      }
    } catch (_) {
      /* offline — the figures stay; the next pull-to-refresh asks again */
    }
  }

  void clearStats() {
    _quietRequest++;
    _loadRequest++;
    _refreshFailure = null;
    _errorIsOffline = false;
    _stale = false;
    _stats = null;
    _currentProviderId = null;
    _error = null;
    notifyListeners();
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _quietRequest++; // a refetch in flight was for the previous salon
    _loadRequest++; // …and so was a load: its late answer is dropped (B1.3)
    _refreshFailure = null;
    _errorIsOffline = false;
    _stale = false;
    _stats = null;
    _isLoading = false;
    _error = null;
    _currentProviderId = null;
    notifyListeners();
  }
}
