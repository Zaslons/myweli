import 'package:flutter/foundation.dart';
import '../core/access/pro_access_guard.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProDashboardProvider extends ChangeNotifier {
  final ProServiceInterface _proService = serviceLocator.proService;

  DashboardStats? _stats;
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  DashboardStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDashboardStats(String providerId) async {
    if (_currentProviderId == providerId && _stats != null && !_isLoading) {
      return;
    }

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
  }

  void clearStats() {
    _stats = null;
    _currentProviderId = null;
    _error = null;
    notifyListeners();
  }
}
