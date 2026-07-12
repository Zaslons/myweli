import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/payment.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Holds the editable deposit policy for the signed-in provider and persists it
/// through [ProServiceInterface].
class ProDepositSettingsProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _loadFailed = false;
  String? _error;
  bool _depositRequired = false;
  double _depositPercentage = 0.30;
  int _cancellationWindowHours = 24;
  MobileMoneyOperator? _mobileMoneyOperator;
  String _mobileMoneyNumber = '';

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  bool get depositRequired => _depositRequired;
  double get depositPercentage => _depositPercentage;
  int get cancellationWindowHours => _cancellationWindowHours;
  MobileMoneyOperator? get mobileMoneyOperator => _mobileMoneyOperator;
  String get mobileMoneyNumber => _mobileMoneyNumber;

  void setDepositRequired(bool value) {
    _depositRequired = value;
    notifyListeners();
  }

  void setMobileMoneyOperator(MobileMoneyOperator value) {
    _mobileMoneyOperator = value;
    notifyListeners();
  }

  void setMobileMoneyNumber(String value) {
    _mobileMoneyNumber = value;
  }

  void setDepositPercentage(double value) {
    _depositPercentage = value;
    notifyListeners();
  }

  void setCancellationWindowHours(int value) {
    _cancellationWindowHours = value;
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
        _cancellationWindowHours = response.data!.cancellationWindowHours;
        _mobileMoneyOperator = response.data!.mobileMoneyOperator;
        _mobileMoneyNumber = response.data!.mobileMoneyNumber ?? '';
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
      final trimmed = _mobileMoneyNumber.trim();
      final response = await _proService.updateDepositPolicy(
        providerId,
        depositRequired: _depositRequired,
        depositPercentage: _depositPercentage,
        cancellationWindowHours: _cancellationWindowHours,
        mobileMoneyOperator: _mobileMoneyOperator,
        mobileMoneyNumber: trimmed.isEmpty ? null : trimmed,
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

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _isLoading = false;
    _isSaving = false;
    _loadFailed = false;
    _error = null;
    _depositRequired = false;
    _depositPercentage = 0.30;
    _cancellationWindowHours = 24;
    _mobileMoneyOperator = null;
    _mobileMoneyNumber = '';
    notifyListeners();
  }
}
