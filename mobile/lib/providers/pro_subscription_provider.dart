import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/subscription.dart';
import '../services/interfaces/subscription_service_interface.dart';

/// Drives the provider "Mon abonnement" screen (FR-PRO-SUB-001): loads the
/// derived plan & trial status.
class ProSubscriptionProvider extends ChangeNotifier {
  final SubscriptionServiceInterface _service =
      serviceLocator.subscriptionService;

  Subscription? _subscription;
  bool _isLoading = false;
  bool _loadFailed = false;
  String? _error;

  Subscription? get subscription => _subscription;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.getSubscription();
      if (res.success && res.data != null) {
        _subscription = res.data;
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
}
