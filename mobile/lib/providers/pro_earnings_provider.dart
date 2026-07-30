import 'package:flutter/foundation.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProEarningsProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

  EarningsData? _earnings;
  bool _isLoading = false;
  String? _error;

  EarningsData? get earnings => _earnings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadEarnings(
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.getEarnings(
        providerId,
        startDate: startDate,
        endDate: endDate,
      );
      if (response.success && response.data != null) {
        _earnings = response.data;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des revenus';
        _earnings = null;
      }
    } catch (e) {
      _error = e.toString();
      _earnings = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearEarnings() {
    _earnings = null;
    _error = null;
    notifyListeners();
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _earnings = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
