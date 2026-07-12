import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/availability.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProAvailabilityProvider extends ChangeNotifier implements SalonScoped {
  final ProServiceInterface _proService = serviceLocator.proService;

  Availability? _availability;
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  Availability? get availability => _availability;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAvailability(String providerId) async {
    if (_currentProviderId == providerId &&
        _availability != null &&
        !_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      final response = await _proService.getProviderAvailability(providerId);
      if (response.success && response.data != null) {
        _availability = response.data;
        _error = null;
      } else {
        _error =
            response.error ?? 'Erreur lors du chargement de la disponibilité';
        _availability = null;
      }
    } catch (e) {
      _error = e.toString();
      _availability = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateAvailability(
      String providerId, Availability availability) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response =
          await _proService.updateAvailability(providerId, availability);
      if (response.success && response.data != null) {
        _availability = response.data;
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _availability = null;
    _isLoading = false;
    _error = null;
    _currentProviderId = null;
    notifyListeners();
  }
}
