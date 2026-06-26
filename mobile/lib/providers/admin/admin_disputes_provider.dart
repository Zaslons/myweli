import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// Dispute case list state: filterable list + open-a-dispute (invoked from a
/// booking row in the support views). Design: docs/design/admin-console-ui.md §3.
class AdminDisputesProvider extends ChangeNotifier {
  AdminDisputesProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  static const _statuses = ['open', 'resolved', null]; // Ouverts/Résolus/Tous

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _filter = 0;
  bool _acting = false;
  String? _actionError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get items => _items;
  int get filter => _filter;
  bool get acting => _acting;
  String? get actionError => _actionError;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.disputes(status: _statuses[_filter]);
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

  /// Open a dispute on a booking (from a support-view booking row).
  Future<bool> open(String appointmentId, String reason) async {
    _acting = true;
    _actionError = null;
    notifyListeners();
    try {
      final res = await _service.openDispute(appointmentId, reason);
      if (res.success) return true;
      _actionError = res.error ?? 'Action impossible';
      return false;
    } finally {
      _acting = false;
      notifyListeners();
    }
  }
}
