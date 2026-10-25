import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
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

  /// The load's own failure — today the only one [error] holds here, kept
  /// apart as on the other Pro lists, so a write added later cannot become
  /// the list's load error (B9.8).
  String? get loadError => _loadError;
  String? _loadError;

  Future<void> loadEarnings(
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isLoading = true;
    _error = null;
    _loadError = null;
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
        _loadError = _error;
        _earnings = null;
      }
    } catch (e) {
      _error = kGenericErrorMessage;
      _loadError = _error;
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
    _loadError = null;
    _earnings = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
