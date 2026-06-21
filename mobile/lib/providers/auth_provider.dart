import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/user.dart';
import '../services/interfaces/auth_service_interface.dart';

class AuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await _authService.getCurrentUser();
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
      final response = await _authService.sendOtp(phoneNumber);
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
      final response = await _authService.verifyOtp(phoneNumber, otp);
      if (response.success && response.data != null) {
        _user = response.data;
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

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
      _user = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Permanently deletes the account. On success the local user is cleared.
  Future<bool> deleteAccount() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.deleteAccount();
      if (response.success) {
        _user = null;
        _error = null;
        return true;
      }
      _error = response.error ?? 'Erreur lors de la suppression';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUser({String? name, String? email}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.updateUser(name: name, email: email);
      if (response.success && response.data != null) {
        _user = response.data;
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
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
}
