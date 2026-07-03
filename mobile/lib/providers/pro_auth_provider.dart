import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/provider_user.dart';
import '../services/interfaces/auth_service_interface.dart';

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
      if (_provider != null) _syncPush();
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
      final response =
          await _authService.verifyOtpForProvider(phoneNumber, otp);
      if (response.success && response.data != null) {
        _provider = response.data;
        _error = null;
        _syncPush();
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

  // ---- Pro auth overhaul (docs/design/pro-auth-social.md) -------------------

  /// devCode from the last email-OTP request (dev backends only).
  String? _emailDevCode;
  String? get emailDevCode => _emailDevCode;

  /// Machine code of the last auth failure (e.g. `provider_not_found` → the
  /// login screen offers « Créer un compte »).
  String? _errorCode;
  String? get errorCode => _errorCode;

  /// Shared login/registration handling — a signed-in provider comes back.
  /// A user-cancelled Google sheet fails silently.
  Future<bool> _login(Future<ApiResponse<ProviderUser>> Function() run) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await run();
      if (response.success && response.data != null) {
        _provider = response.data;
        _syncPush();
        return true;
      }
      _errorCode = response.code;
      _error = _errorCode == 'cancelled'
          ? null
          : (response.error ?? 'Connexion impossible.');
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() =>
      _login(_authService.signInProviderWithGoogle);

  Future<bool> signInWithApple() =>
      _login(_authService.signInProviderWithApple);

  Future<bool> requestEmailOtp(String email) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final response = await _authService.requestProviderEmailOtp(email);
      if (response.success) {
        _emailDevCode =
            (response.data?.isNotEmpty ?? false) ? response.data : null;
        return true;
      }
      _error = response.error ?? 'Envoi du code impossible.';
      _errorCode = response.code;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String email, String code) =>
      _login(() => _authService.verifyProviderEmailOtp(email, code));

  Future<bool> registerWithGoogle({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) =>
      _login(() => _authService.registerProviderWithGoogle(
            phoneNumber: phoneNumber,
            businessName: businessName,
            businessType: businessType,
            address: address,
          ));

  Future<bool> registerWithEmail({
    required String email,
    required String code,
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) =>
      _login(() => _authService.registerProviderWithEmail(
            email: email,
            code: code,
            phoneNumber: phoneNumber,
            businessName: businessName,
            businessType: businessType,
            address: address,
          ));

  /// Best-effort: register this device under the provider session if push
  /// permission is already granted. Never throws into the auth flow.
  void _syncPush() {
    try {
      unawaited(serviceLocator.proPushRegistration.registerIfGranted());
    } catch (_) {/* best-effort */}
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Unregister this device first — the call needs the live provider session.
      try {
        await serviceLocator.proPushRegistration.unregister();
      } catch (_) {/* best-effort */}
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
