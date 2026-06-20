import 'package:flutter/foundation.dart';
import '../models/provider_user.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/auth_service_interface.dart';
import '../models/api_response.dart';

class ProAuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;

  ProviderUser? _provider;
  bool _isLoading = false;
  String? _error;

  ProviderUser? get provider => _provider;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _provider != null;

  ProAuthProvider() {
    loadCurrentProvider();
  }

  Future<void> loadCurrentProvider() async {
    _isLoading = true;
    notifyListeners();

    try {
      _provider = await _authService.getCurrentProvider();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.sendOtpToProvider(phoneNumber);
      if (response.success) {
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'envoi du code';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.verifyOtpForProvider(phoneNumber, otp);
      if (response.success && response.data != null) {
        _provider = response.data;
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Code OTP invalide';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.registerProvider(
        phoneNumber: phoneNumber,
        businessName: businessName,
        businessType: businessType,
        address: address,
      );
      if (response.success && response.data != null) {
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'inscription';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logoutProvider();
      _provider = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
