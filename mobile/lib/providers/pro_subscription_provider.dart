import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/salon_subscription.dart';
import '../services/interfaces/subscription_service_interface.dart';

/// Drives « Mon abonnement » (pricing pivot, team access R3): the salon's
/// offer state — SETUP (no offer yet, `no_offer`) or trial/paid/grace/
/// expired — and the offer choice/switch.
class ProSubscriptionProvider extends ChangeNotifier implements SalonScoped {
  final SubscriptionServiceInterface _service =
      serviceLocator.subscriptionService;

  SalonSubscription? _salon;
  bool _isSetup = false;
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;

  bool _isChoosing = false;
  String? _chooseError;
  String? _chooseErrorCode;

  SalonSubscription? get salon => _salon;

  /// True when the salon hasn't picked an offer yet (free setup state).
  bool get isSetup => _isSetup;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  String? get error => _error;

  bool get isChoosing => _isChoosing;
  String? get chooseError => _chooseError;
  String? get chooseErrorCode => _chooseErrorCode;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.getSalonSubscription(providerId);
      if (res.success && res.data != null) {
        _salon = res.data;
        _isSetup = false;
        _loadFailed = false;
      } else if (res.code == 'no_offer') {
        _salon = null;
        _isSetup = true;
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

  /// Pick or switch the offer (the FIRST choice starts the salon's ONE
  /// 3-month trial; switches keep the clock).
  Future<bool> choose(String providerId, SalonTier tier) async {
    _isChoosing = true;
    _chooseError = null;
    _chooseErrorCode = null;
    notifyListeners();
    try {
      final res = await _service.chooseOffer(providerId, tier);
      if (res.success && res.data != null) {
        _salon = res.data;
        _isSetup = false;
        return true;
      }
      _chooseError = res.error ?? 'Choix impossible. Réessayez.';
      _chooseErrorCode = res.code;
      return false;
    } catch (e) {
      _chooseError = e.toString();
      return false;
    } finally {
      _isChoosing = false;
      notifyListeners();
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _salon = null;
    _isSetup = false;
    _isLoading = false;
    _loadFailed = false;
    _error = null;
    _isChoosing = false;
    _chooseError = null;
    _chooseErrorCode = null;
    notifyListeners();
  }
}
