import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Holds the editable deposit policy for the signed-in provider and persists it
/// through [ProServiceInterface].
class ProDepositSettingsProvider extends ChangeNotifier {
  final ProServiceInterface _proService = serviceLocator.proService;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _loadFailed = false;
  String? _error;
  bool _depositRequired = true;
  double _depositPercentage = 0.30;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  bool get depositRequired => _depositRequired;
  double get depositPercentage => _depositPercentage;

  void setDepositRequired(bool value) {
    _depositRequired = value;
    notifyListeners();
  }

  void setDepositPercentage(double value) {
    _depositPercentage = value;
    notifyListeners();
  }

  Future<void> load(String providerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.getDepositPolicy(providerId);
      if (response.success && response.data != null) {
        _depositRequired = response.data!.depositRequired;
        _depositPercentage = response.data!.depositPercentage;
        _loadFailed = false;
        _error = null;
      } else {
        _loadFailed = true;
        _error = response.error ?? 'Erreur lors du chargement';
      }
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save(String providerId) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.updateDepositPolicy(
        providerId,
        depositRequired: _depositRequired,
        depositPercentage: _depositPercentage,
      );
      if (response.success && response.data != null) {
        _error = null;
        return true;
      }
      _error = response.error ?? "Erreur lors de l'enregistrement";
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
