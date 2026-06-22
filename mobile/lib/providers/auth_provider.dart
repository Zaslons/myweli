import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/user.dart';
import '../services/interfaces/auth_service_interface.dart';
import '../services/interfaces/image_upload_service_interface.dart';

class AuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;
  // Resolved lazily so constructing AuthProvider doesn't require the upload
  // service to be registered (only uploadAvatar needs it).
  ImageUploadServiceInterface get _uploadService =>
      serviceLocator.imageUploadService;

  User? _user;
  bool _isLoading = false;
  bool _isUploadingAvatar = false;
  double _avatarProgress = 0;
  String? _error;
  String? _otpErrorCode;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isUploadingAvatar => _isUploadingAvatar;
  double get avatarProgress => _avatarProgress;
  String? get error => _error;

  /// Machine-readable code for the last OTP failure (e.g. `otp_locked`,
  /// `otp_expired`), so the OTP screen can render the right state.
  String? get otpErrorCode => _otpErrorCode;
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
        _otpErrorCode = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de l\'envoi du code';
        _otpErrorCode = response.code;
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
        _otpErrorCode = null;
        return true;
      } else {
        _error = response.error ?? 'Code OTP invalide';
        _otpErrorCode = response.code;
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

  /// Uploads a new avatar through the image pipeline, then saves it on the
  /// user. Returns true on success.
  Future<bool> uploadAvatar(String source) async {
    _isUploadingAvatar = true;
    _avatarProgress = 0;
    _error = null;
    notifyListeners();
    try {
      final res = await _uploadService.uploadImage(
        source: source,
        onProgress: (p) {
          _avatarProgress = p;
          notifyListeners();
        },
      );
      if (!res.success || res.data == null) {
        _error = res.error ?? 'Échec de l’envoi';
        return false;
      }
      return await updateUser(avatarUrl: res.data);
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isUploadingAvatar = false;
      notifyListeners();
    }
  }

  Future<bool> updateUser(
      {String? name, String? email, String? avatarUrl}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.updateUser(
          name: name, email: email, avatarUrl: avatarUrl);
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
