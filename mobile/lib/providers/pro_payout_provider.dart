import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/payment.dart';
import '../models/payout.dart';
import '../services/interfaces/pro_payout_service_interface.dart';

/// Holds the provider's payout balance + history and requests payouts through
/// [ProPayoutServiceInterface].
class ProPayoutProvider extends ChangeNotifier {
  final ProPayoutServiceInterface _service = serviceLocator.proPayoutService;

  bool _isLoading = false;
  bool _isRequesting = false;
  bool _loadFailed = false;
  String? _error;
  double _availableBalance = 0;
  double _pendingBalance = 0;
  List<Payout> _payouts = const [];

  bool get isLoading => _isLoading;
  bool get isRequesting => _isRequesting;
  bool get loadFailed => _loadFailed;
  String? get error => _error;
  double get availableBalance => _availableBalance;
  double get pendingBalance => _pendingBalance;
  List<Payout> get payouts => _payouts;
  bool get canRequest => _availableBalance > 0 && !_isRequesting;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _loadFailed = false;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.getPayoutAccount(providerId);
      if (res.success && res.data != null) {
        _availableBalance = res.data!.availableBalance;
        _pendingBalance = res.data!.pendingBalance;
        _payouts = res.data!.payouts;
        _loadFailed = false;
      } else {
        _loadFailed = true;
        _error = res.error ?? 'Erreur lors du chargement';
      }
    } catch (e) {
      _loadFailed = true;
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestPayout({
    required String providerId,
    required double amount,
    required MobileMoneyOperator operator,
  }) async {
    _isRequesting = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _service.requestPayout(
        providerId: providerId,
        amount: amount,
        operator: operator,
      );
      if (res.success && res.data != null) {
        _error = null;
        await load(providerId);
        return true;
      }
      _error = res.error ?? 'Erreur lors de la demande';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isRequesting = false;
      notifyListeners();
    }
  }
}
