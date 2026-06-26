import 'package:flutter/foundation.dart';

import '../../services/admin/admin_service.dart';

/// Loads the read-only marketplace-health KPI snapshot for the dashboard.
class AdminDashboardProvider extends ChangeNotifier {
  AdminDashboardProvider({AdminService? service})
      : _service = service ?? adminService;

  final AdminService _service;

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _overview;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get overview => _overview;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final res = await _service.overview();
    if (res.success && res.data != null) {
      _overview = res.data;
    } else {
      _error = res.error ?? 'Erreur lors du chargement';
    }
    _isLoading = false;
    notifyListeners();
  }
}
