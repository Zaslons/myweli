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

  DashboardStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDashboardStats(String providerId) async {
    if (_currentProviderId == providerId && _stats != null && !_isLoading) {
      // Already loaded for this salon. If a booking was created since and the
      // quiet refetch failed, this — a pull-to-refresh — is the retry; it
      // stays quiet, because the loud path below ends on a text with no way
      // out when it fails.
      if (_stale) await _refetchQuietly();
      return;
    }

    // A fresh load: what it brings is not stale, and a quiet refetch still in
    // flight was asked before it — possibly for another salon.
    _stale = false;
    _quietRequest++;
    _isLoading = true;
    _error = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      final response = await _proService.getDashboardStats(providerId);
      if (response.success && response.data != null) {
        _stats = response.data;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des statistiques';
        ProAccessGuard.report(response.code);
        _stats = null;
      }
    } catch (e) {
      _error = e.toString();
      _stats = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // A booking was created while this was in flight: its answer may have
    // been computed before the booking existed.
    if (_stale && _stats != null) await _refetchQuietly();
  }

  /// The salon just created [booking]: the counts and the revenue it feeds
  /// are the server's to compute, so nothing is guessed here — the figures
  /// are asked for again, without a loader and without an error state.
  @override
  void bookingCreated(Appointment booking) {
    if (booking.providerId != _currentProviderId) return;
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
    _stale = false;
    _stats = null;
    _isLoading = false;
    _error = null;
    _currentProviderId = null;
    notifyListeners();
  }
}
