import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/salon_subscription.dart';
import '../services/interfaces/subscription_service_interface.dart';

/// Drives « Mon abonnement » (pricing pivot, team access R3): the salon's
/// offer state — SETUP (no offer yet, `no_offer`) or trial/paid/grace/
/// expired. Read-only: the Pro app never chooses or switches an offer (the
/// server starts the trial at the first publish; offers are chosen on the
/// web). Design: docs/design/pro-companion-path.md §2.2.
class ProSubscriptionProvider extends ChangeNotifier implements SalonScoped {
  final SubscriptionServiceInterface _service =
      serviceLocator.subscriptionService;

  SalonSubscription? _salon;
  bool _isSetup = false;
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;

  SalonSubscription? get salon => _salon;

  /// True when the salon has no offer row yet (the free setup state, until
  /// the first publish starts the trial).
  bool get isSetup => _isSetup;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  String? get error => _error;

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

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _salon = null;
    _isSetup = false;
    _isLoading = false;
    _loadFailed = false;
    _error = null;
    notifyListeners();
  }
}
