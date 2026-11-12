import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/api_response.dart';
import '../../services/admin/admin_service.dart';
import 'admin_salon_validation_count_provider.dart';

/// Salon (provider) management state: filterable/searchable list + suspend /
/// restore / feature. Design: docs/design/admin-console-ui.md §3.
class AdminProvidersProvider extends ChangeNotifier {
  AdminProvidersProvider({AdminService? service, this._validationCount})
    : _service = service ?? adminService;

  final AdminService _service;

  /// « Salons à valider » counts pending requests of salons that are NOT
  /// suspended (B0.18 §3.5): a suspension takes one out, a lift brings it
  /// back — so both re-read the sidebar's count.
  final AdminSalonValidationCountProvider? _validationCount;

  static const _statuses = [null, 'active', 'suspended']; // Tous/Actifs/Susp.

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _filter = 0;
  String _query = '';
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get items => _items;
  int get filter => _filter;
  bool get acting => _acting;
  String? get actionError => _actionError;

  /// What the last successful « Lever la suspension » answered — the
  /// snackbar's words (`ValidationLabels.restoreMessage`): live, or offline
  /// with its reason (B0.18 §4.4).
  RestoreOutcome? _lastRestore;
  RestoreOutcome? get lastRestore => _lastRestore;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.providers(status: _statuses[_filter], q: _query);
    if (res.success && res.data != null) {
      _items = (res.data!['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setFilter(int i) {
    if (_filter == i) return;
    _filter = i;
    load();
  }

  void search(String q) {
    _query = q;
    load();
  }

  Future<bool> suspend(SalonId id, String reason) async {
    final ok = await _act(_service.suspendProvider(id, reason), id, _whole);
    if (ok) unawaited(_validationCount?.load());
    return ok;
  }

  /// « Lever la suspension » (B0.18 §4.4). Only the returned `status` enters
  /// the row: the B0.18 answer is `{ status, reason }`, and a `reason` key
  /// spread into a salon row is a field no salon has.
  Future<bool> restore(SalonId id) async {
    _lastRestore = null;
    final ok = await _act(_service.restoreProvider(id), id, (outcome) {
      _lastRestore = outcome;
      return {'status': outcome.status};
    });
    if (ok) unawaited(_validationCount?.load());
    return ok;
  }

  Future<bool> feature(SalonId id, bool featured) =>
      _act(_service.featureProvider(id, featured), id, _whole);

  static Map<String, dynamic> _whole(Map<String, dynamic> updated) => updated;

  /// [patch] turns the answer into the fields the row takes.
  Future<bool> _act<T extends Object>(
    Future<ApiResponse<T>> call,
    String id,
    Map<String, dynamic> Function(T data) patch,
  ) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await call;
      if (res.success && res.data != null) {
        // Replace the row with the returned (updated) provider; drop it if the
        // active status filter no longer matches.
        final updated = patch(res.data as T);
        final keep =
            _statuses[_filter] == null ||
            updated['status'] == _statuses[_filter];
        final next = <Map<String, dynamic>>[];
        for (final r in _items) {
          if (r['id'] != id) {
            next.add(r);
          } else if (keep) {
            next.add({...r, ...updated});
          }
        }
        _items = next;
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
