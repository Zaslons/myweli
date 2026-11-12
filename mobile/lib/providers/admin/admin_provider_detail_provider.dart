import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';
import 'admin_salon_validation_count_provider.dart';

/// Salon support view: the provider entity + its recent bookings, plus the
/// suspend / restore / feature actions. Design: docs/design/admin-console-ui.md §3.
class AdminProviderDetailProvider extends ChangeNotifier {
  AdminProviderDetailProvider({AdminService? service, this._validationCount})
    : _service = service ?? adminService;

  final AdminService _service;

  /// Re-read after a suspension or a lift, which take a pending request out
  /// of « Salons à valider » and bring it back (B0.18 §3.5).
  final AdminSalonValidationCountProvider? _validationCount;

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _provider;
  List<Map<String, dynamic>> _appointments = [];
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get provider => _provider;
  List<Map<String, dynamic>> get appointments => _appointments;
  bool get acting => _acting;
  String? get actionError => _actionError;

  /// What the last successful « Lever la suspension » answered (B0.18 §4.4).
  RestoreOutcome? _lastRestore;
  RestoreOutcome? get lastRestore => _lastRestore;

  /// Whose entity this is. The provider is app-wide and outlives the screen,
  /// so without it the way to B showed A — A's name, A's status, and an
  /// action bar acting on B's id — until B answered, and for good when B's
  /// read failed (B9.8, docs/design/hygiene-batch9.md §14).
  String? _id;
  String? get id => _id;

  Future<void> load(SalonId id) async {
    if (id != _id) {
      _id = id;
      _provider = null;
      _appointments = [];
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.providerDetail(id);
    // Another entity was asked for while this read was out: the answer is
    // no longer anybody's.
    if (id != _id) return;
    if (res.success && res.data != null) {
      final d = res.data!;
      _appointments = (d['recentAppointments'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _provider = {...d}..remove('recentAppointments');
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> suspend(SalonId id, String reason) async {
    final ok = await _act(_service.suspendProvider(id, reason), _whole);
    if (ok) unawaited(_validationCount?.load());
    return ok;
  }

  /// « Lever la suspension ». Only the returned `status` enters the salon:
  /// the B0.18 answer is `{ status, reason }`, not a salon.
  Future<bool> restore(SalonId id) async {
    _lastRestore = null;
    final ok = await _act(_service.restoreProvider(id), (outcome) {
      _lastRestore = outcome;
      return {'status': outcome.status};
    });
    if (ok) unawaited(_validationCount?.load());
    return ok;
  }

  Future<bool> feature(SalonId id, bool featured) =>
      _act(_service.featureProvider(id, featured), _whole);

  Future<bool> markPaid(SalonId id, int months) =>
      _act(_service.markSubscriptionPaid(id, months), _whole);

  static Map<String, dynamic> _whole(Map<String, dynamic> updated) => updated;

  /// [patch] turns the answer into the fields the salon takes.
  Future<bool> _act<T extends Object>(
    Future<ApiResponse<T>> call,
    Map<String, dynamic> Function(T data) patch,
  ) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success && res.data != null && _provider != null) {
        _provider = {..._provider!, ...patch(res.data as T)};
        return true;
      }
      _actionError = res.error ?? 'Action impossible';
      return false;
    } finally {
      _acting = false;
      notifyListeners();
    }
  }
}
