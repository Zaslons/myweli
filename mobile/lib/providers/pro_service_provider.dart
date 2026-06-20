import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/service.dart';
import '../services/interfaces/pro_service_interface.dart';

class ProServiceProvider extends ChangeNotifier {
  final ProServiceInterface _proService = serviceLocator.proService;

  List<Service> _services = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProviderId;

  List<Service> get services => _services;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadServices(String providerId) async {
    if (_currentProviderId == providerId &&
        _services.isNotEmpty &&
        !_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    _currentProviderId = providerId;
    notifyListeners();

    try {
      final response = await _proService.getProviderServices(providerId);
      if (response.success && response.data != null) {
        _services = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des services';
        _services = [];
      }
    } catch (e) {
      _error = e.toString();
      _services = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createService(
      String providerId, Map<String, dynamic> serviceData) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.createService(providerId, serviceData);
      if (response.success && response.data != null) {
        _services.add(response.data!);
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la création';
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

  Future<bool> updateService(
      String serviceId, Map<String, dynamic> serviceData) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.updateService(serviceId, serviceData);
      if (response.success && response.data != null) {
        final index = _services.indexWhere((s) => s.id == serviceId);
        if (index != -1) {
          _services[index] = response.data!;
        }
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

  Future<bool> deleteService(String serviceId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _proService.deleteService(serviceId);
      if (response.success) {
        _services.removeWhere((s) => s.id == serviceId);
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la suppression';
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
}
