import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/deposit.dart';
import '../core/utils/salon_id.dart';
import '../services/interfaces/pro_service_interface.dart';

/// Holds the editable deposit policy for the signed-in provider and persists it
/// through [ProServiceInterface].
class ProDepositSettingsProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _loadFailed = false;
  String? _error;
  String? _errorCode;
  bool _depositRequired = false;
  double _depositPercentage = kDefaultDepositPercentage;
  int _cancellationWindowHours = 24;
  String? _mobileMoneyOperator;
  String _mobileMoneyNumber = '';

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get loadFailed => _loadFailed;

  /// The policy is the salon's, not the defaults these fields start with:
  /// a read has answered since the last salon switch (B9.8). The form waits
  /// for it — on the first frame it showed the defaults.
  bool get loaded => _loaded;
  bool _loaded = false;
  String? get error => _error;

  /// Machine code of the last failed [save] (`invalid_phone`), so the form
  /// can put a number the server refused under the field (SYSTEM.md §14
  /// rule 1, phone-leftovers.md §2).
  String? get errorCode => _errorCode;

  bool get depositRequired => _depositRequired;
  double get depositPercentage => _depositPercentage;
  int get cancellationWindowHours => _cancellationWindowHours;
  String? get mobileMoneyOperator => _mobileMoneyOperator;
  String get mobileMoneyNumber => _mobileMoneyNumber;

  void setDepositRequired(bool value) {
    _depositRequired = value;
    notifyListeners();
  }

  void setMobileMoneyOperator(String value) {
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

  Future<void> load(SalonId providerId) async {
    final scope = _scope;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _proService.getDepositPolicy(providerId);
      if (scope != _scope) return;
      if (response.success && response.data != null) {
        _depositRequired = response.data!.depositRequired;
        // 0 % is « not chosen yet »: every new salon is stored with it, and
        // the server refuses it once deposits are on — the form proposes the
        // default instead (acompte-off-parity.md §2).
        final stored = response.data!.depositPercentage;
        _depositPercentage = stored > 0 ? stored : kDefaultDepositPercentage;
        _cancellationWindowHours = response.data!.cancellationWindowHours;
        _mobileMoneyOperator = response.data!.mobileMoneyOperator;
        _mobileMoneyNumber = response.data!.mobileMoneyNumber ?? '';
        _loaded = true;
        _loadFailed = false;
        _error = null;
      } else {
        _loadFailed = true;
        _error = response.error ?? kGenericErrorMessage;
      }
    } catch (e) {
      if (scope != _scope) return;
      _loadFailed = true;
      _error = kGenericErrorMessage;
    } finally {
      if (scope == _scope) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save(SalonId providerId) async {
    final scope = _scope;
    _isSaving = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    try {
      final trimmed = _mobileMoneyNumber.trim();
      // The PUT replaces the whole policy: the operator and the percentage go
      // out as held whatever the switch says — a `null` or a 0 in their place
      // erases them (acompte-off-parity.md §1, D1).
      final response = await _proService.updateDepositPolicy(
        providerId,
        depositRequired: _depositRequired,
        depositPercentage: _depositPercentage,
        cancellationWindowHours: _cancellationWindowHours,
        mobileMoneyOperator: _mobileMoneyOperator,
        mobileMoneyNumber: trimmed.isEmpty ? null : trimmed,
      );
      if (scope != _scope) return response.success;
      if (response.success && response.data != null) {
        _error = null;
        return true;
      }
      _error = response.error ?? 'Erreur lors de l’enregistrement';
      _errorCode = response.code;
      return false;
    } catch (e) {
      if (scope != _scope) return false;
      _error = kGenericErrorMessage;
      return false;
    } finally {
      if (scope == _scope) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only. A read or a write takes it before it awaits and writes nothing
  /// when it moved meanwhile: its answer is the previous salon's, or the
  /// previous account's (docs/design/pro-account-scope.md §2.2).
  int _scope = 0;

  @override
  void resetForSalonSwitch() {
    _scope++;
    _loaded = false;
    _isLoading = false;
    _isSaving = false;
    _loadFailed = false;
    _error = null;
    _errorCode = null;
    _depositRequired = false;
    _depositPercentage = kDefaultDepositPercentage;
    _cancellationWindowHours = 24;
    _mobileMoneyOperator = null;
    _mobileMoneyNumber = '';
    notifyListeners();
  }
}
