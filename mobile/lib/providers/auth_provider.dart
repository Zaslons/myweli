import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/user.dart';
import '../services/interfaces/auth_service_interface.dart';
import '../services/interfaces/image_upload_service_interface.dart';

class AuthProvider extends ChangeNotifier {
  final AuthServiceInterface _authService = serviceLocator.authService;
  // Resolved lazily so constructing AuthProvider doesn't require the upload
  // service to be registered (only uploadAvatar needs it).
  ImageUploadServiceInterface get _uploadService =>
      serviceLocator.avatarImageUploadService;

  User? _user;
  bool _isLoading = false;
  bool _isUploadingAvatar = false;
  double _avatarProgress = 0;
  String? _error;
  String? _otpErrorCode;
  String? _updateErrorCode;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isUploadingAvatar => _isUploadingAvatar;
  double get avatarProgress => _avatarProgress;
  String? get error => _error;

  /// Machine-readable code for the last OTP failure (e.g. `otp_locked`,
  /// `otp_expired`), so the OTP screen can render the right state.
  String? get otpErrorCode => _otpErrorCode;

  /// Machine-readable code for the last failed [updateUser] (e.g.
  /// `invalid_phone`), so a form can put a field's fault under the field
  /// (SYSTEM.md §14 rule 1) rather than in the form-level slot.
  String? get updateErrorCode => _updateErrorCode;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _sessionEnds = _authService.sessionEnded.listen((_) => _onSessionEnded());
    _loadCurrentUser();
  }

  late final StreamSubscription<void> _sessionEnds;

  @override
  void dispose() {
    _sessionEnds.cancel();
    super.dispose();
  }

  /// **Every change of WHO is signed in goes through here** (B9.13 —
  /// docs/design/consumer-account-scope.md §2.2). When the account's id
  /// changes — A → nobody, nobody → B — every account-scoped store is reset
  /// in this same synchronous block, before the caller's `notifyListeners`:
  /// no frame sees the new account with the old one's bookings. The same
  /// account (a profile edit) resets nothing.
  void _setUser(User? next) {
    final changed = next?.id != _user?.id;
    _user = next;
    if (!changed) return;
    _updateErrorCode = null;
    _emailDevCode = null;
    _sessionEndedNotice = false;
    AccountScope.resetAll();
  }

  /// A « Déconnexion » or a deletion is under way: it clears the session
  /// itself, so a refusal heard meanwhile is that same way out (§3) — unless
  /// it fails: a deletion whose own request was the one refused leaves no
  /// session behind it, and then [_endedWhileLeaving] ends the account.
  bool _leaving = false;
  bool _endedWhileLeaving = false;

  bool _sessionEndedNotice = false;

  /// True ONCE after the server ended the session (§2.5): the root's
  /// `SessionEndedNotice` says it, then it is spent.
  bool consumeSessionEndedNotice() {
    final notice = _sessionEndedNotice;
    _sessionEndedNotice = false;
    return notice;
  }

  /// The server refused to renew the session (`AuthServiceInterface
  /// .sessionEnded`): the account ends here, as a sign-out ends it — minus the
  /// device unregistration, which needs the session that is gone.
  void _onSessionEnded() {
    if (_user == null) return;
    if (_leaving) {
      _endedWhileLeaving = true;
      return;
    }
    _setUser(null);
    _error = null;
    _sessionEndedNotice = true;
    notifyListeners();
  }

  /// The end of a « Déconnexion » or a deletion, whatever it answered: one
  /// that left the account signed in while the server ended its session
  /// ends it now, with the notice. The caller notifies.
  void _doneLeaving() {
    _leaving = false;
    final ended = _endedWhileLeaving;
    _endedWhileLeaving = false;
    if (ended && _user != null) {
      _setUser(null);
      _sessionEndedNotice = true;
    }
  }

  Future<void> _loadCurrentUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      _setUser(await _authService.getCurrentUser());
      _error = null;
      if (_user != null) _syncPush();
    } catch (e) {
      _error = kGenericErrorMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Best-effort: register this device's push token if permission is already
  /// granted. Never throws into the auth flow.
  void _syncPush() {
    try {
      unawaited(serviceLocator.pushRegistration.registerIfGranted());
    } catch (_) {
      /* best-effort */
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
        _error = response.error ?? 'Erreur lors de l’envoi du code';
        _otpErrorCode = response.code;
        return false;
      }
    } catch (e) {
      _error = kGenericErrorMessage;
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
        _setUser(response.data);
        _error = null;
        _otpErrorCode = null;
        _syncPush();
        return true;
      } else {
        _error = response.error ?? 'Code OTP invalide';
        _otpErrorCode = response.code;
        return false;
      }
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---- Auth overhaul (docs/design/app-auth-social.md) ----------------------

  /// devCode returned by the last email-OTP request (dev backends only) so the
  /// code screen can hint it — mirrors the web flow.
  String? _emailDevCode;
  String? get emailDevCode => _emailDevCode;

  /// Shared login handling: Google/Apple/email all land here. A user-cancelled
  /// sheet (`cancelled`) fails silently (no error banner).
  Future<bool> _login(Future<ApiResponse<User>> Function() run) async {
    _isLoading = true;
    _error = null;
    _otpErrorCode = null;
    notifyListeners();
    try {
      final response = await run();
      if (response.success && response.data != null) {
        _setUser(response.data);
        _error = null;
        _otpErrorCode = null;
        _syncPush();
        return true;
      }
      _otpErrorCode = response.code;
      _error = _otpErrorCode == 'cancelled'
          ? null
          : (response.error ?? 'Connexion impossible.');
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() => _login(_authService.signInWithGoogle);

  Future<bool> signInWithApple() => _login(_authService.signInWithApple);

  Future<bool> requestEmailOtp(String email) async {
    _isLoading = true;
    _error = null;
    // A new attempt: the last one's code would place this one's sentence
    // (sign_in_refusal.dart), so it goes with it, as on ProAuthProvider.
    _otpErrorCode = null;
    notifyListeners();
    try {
      final response = await _authService.requestEmailOtp(email);
      if (response.success) {
        _emailDevCode = (response.data?.isNotEmpty ?? false)
            ? response.data
            : null;
        _otpErrorCode = null;
        return true;
      }
      _error = response.error ?? 'Envoi du code impossible.';
      _otpErrorCode = response.code;
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String email, String code) =>
      _login(() => _authService.verifyEmailOtp(email, code));

  Future<void> logout() async {
    _isLoading = true;
    _leaving = true;
    notifyListeners();

    try {
      // Unregister this device first — the call needs the live session.
      try {
        await serviceLocator.pushRegistration.unregister();
      } catch (_) {
        /* best-effort */
      }
      await _authService.logout();
      _setUser(null);
      _error = null;
    } catch (e) {
      // Still signed in: the account keeps its data too.
      _error = kGenericErrorMessage;
    } finally {
      _doneLeaving();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Permanently deletes the account. On success the local user is cleared.
  Future<bool> deleteAccount() async {
    _isLoading = true;
    _leaving = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.deleteAccount();
      if (response.success) {
        _setUser(null);
        _error = null;
        return true;
      }
      _error = response.error ?? 'Erreur lors de la suppression';
      return false;
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _doneLeaving();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Uploads a new avatar through the image pipeline, then saves it on the
  /// user. Returns true on success.
  Future<bool> uploadAvatar(String source) async {
    final account = _user?.id;
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
      // Signed out — or another account in — while the file went up: the
      // photo was A's, and saving it now would put it on B's profile (§1).
      if (_user?.id != account) return false;
      if (!res.success || res.data == null) {
        _error = res.error ?? 'Échec de l’envoi';
        return false;
      }
      return await updateUser(avatarUrl: res.data);
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isUploadingAvatar = false;
      notifyListeners();
    }
  }

  Future<bool> updateUser({
    String? name,
    String? email,
    String? avatarUrl,
    String? phone,
  }) async {
    final account = _user?.id;
    _isLoading = true;
    _error = null;
    _updateErrorCode = null;
    notifyListeners();

    try {
      final response = await _authService.updateUser(
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        phone: phone,
      );
      // The account changed while the edit was out: its answer is the
      // previous account's — taking it would sign A back in under B.
      if (_user?.id != account) return false;
      if (response.success && response.data != null) {
        _setUser(response.data);
        _error = null;
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la mise à jour';
        _updateErrorCode = response.code;
        return false;
      }
    } catch (e) {
      _error = kGenericErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
