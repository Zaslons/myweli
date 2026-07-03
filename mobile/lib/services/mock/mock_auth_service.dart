import 'dart:async';
import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/provider_user.dart';
import '../../models/session.dart';
import '../../models/user.dart';
import '../interfaces/auth_service_interface.dart';
import '../interfaces/session_store.dart';
import 'mock_data.dart';

/// Per-phone OTP state the mock uses to emulate real SMS-OTP behaviour: a code
/// with an expiry, a wrong-attempt budget, and a resend budget.
class _OtpState {
  _OtpState({
    required this.code,
    required this.expiresAt,
    required this.attemptsLeft,
    required this.resendsLeft,
  });

  final String code;
  final DateTime expiresAt;
  int attemptsLeft;
  int resendsLeft;
}

class MockAuthService implements AuthServiceInterface {
  MockAuthService({Duration? otpValidity, SessionStore? sessionStore})
      : _otpValidity = otpValidity ?? AppConstants.otpValidity,
        _sessionStore = sessionStore ?? InMemorySessionStore();

  /// Demo code (no real SMS) — surfaced only in debug builds.
  static const String demoOtp = '123456';

  final Duration _otpValidity;
  final SessionStore _sessionStore;
  User? _currentUser;
  ProviderUser? _currentProvider;
  final Map<String, _OtpState> _otpStates = {};
  final Map<String, _OtpState> _emailOtpStates = {}; // lowercased email
  final Map<String, String> _providerOtpStore = {}; // phone -> otp

  Future<void> _persistSession(User user) async {
    final session = Session(
      token: 'mock_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
      user: user,
    );
    await _sessionStore.save(jsonEncode(session.toJson()));
  }

  @override
  Future<ApiResponse<String>> sendOtp(String phoneNumber) async {
    await Future.delayed(AppConstants.mockDelay);

    final existing = _otpStates[phoneNumber];
    if (existing != null && existing.resendsLeft <= 0) {
      return ApiResponse.error(
        'Trop de demandes de code. Réessayez plus tard.',
        code: 'otp_resend_limit',
      );
    }
    final resendsLeft = existing == null
        ? AppConstants.otpMaxResends
        : existing.resendsLeft - 1;
    _otpStates[phoneNumber] = _OtpState(
      code: demoOtp,
      expiresAt: DateTime.now().add(_otpValidity),
      attemptsLeft: AppConstants.otpMaxAttempts,
      resendsLeft: resendsLeft,
    );

    return ApiResponse.success(demoOtp, message: 'Code OTP envoyé avec succès');
  }

  @override
  Future<ApiResponse<User>> verifyOtp(String phoneNumber, String otp) async {
    await Future.delayed(AppConstants.mockDelay);

    final state = _otpStates[phoneNumber];
    if (state == null) {
      return ApiResponse.error(
        'Aucun code actif. Demandez un nouveau code.',
        code: 'otp_none',
      );
    }
    if (DateTime.now().isAfter(state.expiresAt)) {
      _otpStates.remove(phoneNumber);
      return ApiResponse.error(
        'Code expiré. Demandez un nouveau code.',
        code: 'otp_expired',
      );
    }
    if (state.attemptsLeft <= 0) {
      return ApiResponse.error(
        'Trop de tentatives. Demandez un nouveau code.',
        code: 'otp_locked',
      );
    }
    if (state.code != otp) {
      state.attemptsLeft -= 1;
      if (state.attemptsLeft <= 0) {
        return ApiResponse.error(
          'Trop de tentatives. Demandez un nouveau code.',
          code: 'otp_locked',
        );
      }
      final n = state.attemptsLeft;
      return ApiResponse.error(
        'Code incorrect. $n ${n == 1 ? 'essai restant' : 'essais restants'}.',
        code: 'otp_invalid',
      );
    }

    final user = MockData.users.firstWhere(
      (u) => u.phoneNumber == phoneNumber,
      orElse: () => User(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
      ),
    );
    _currentUser = user;
    _otpStates.remove(phoneNumber);
    await _persistSession(user);

    return ApiResponse.success(user, message: 'Connexion réussie');
  }

  // ---- Auth overhaul (docs/design/app-auth-social.md) ----------------------

  @override
  Future<ApiResponse<User>> signInWithGoogle() async {
    await Future.delayed(AppConstants.mockDelay);
    return _socialLogin(email: 'mock.google@myweli.test', provider: 'google');
  }

  @override
  Future<ApiResponse<User>> signInWithApple() async {
    await Future.delayed(AppConstants.mockDelay);
    return _socialLogin(email: 'mock.apple@myweli.test', provider: 'apple');
  }

  /// Find-or-create by email — first login has NO phone, so the mandatory
  /// contact-phone step is exercised on mocks exactly like production.
  Future<ApiResponse<User>> _socialLogin({
    required String email,
    required String provider,
  }) async {
    final user = MockData.users.firstWhere(
      (u) => u.email?.toLowerCase() == email,
      orElse: () {
        final created = User(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          email: email,
          authProvider: provider,
          createdAt: DateTime.now(),
        );
        MockData.users.add(created);
        return created;
      },
    );
    _currentUser = user;
    await _persistSession(user);
    return ApiResponse.success(user, message: 'Connexion réussie');
  }

  @override
  Future<ApiResponse<String>> requestEmailOtp(String email) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    final existing = _emailOtpStates[key];
    final expired =
        existing != null && DateTime.now().isAfter(existing.expiresAt);
    if (existing != null && !expired && existing.resendsLeft <= 0) {
      return ApiResponse.error(
        'Trop de demandes de code. Réessayez plus tard.',
        code: 'otp_resend_limit',
      );
    }
    final resendsLeft = (existing == null || expired)
        ? AppConstants.otpMaxResends
        : existing.resendsLeft - 1;
    _emailOtpStates[key] = _OtpState(
      code: demoOtp,
      expiresAt: DateTime.now().add(_otpValidity),
      attemptsLeft: AppConstants.otpMaxAttempts,
      resendsLeft: resendsLeft,
    );
    return ApiResponse.success(demoOtp, message: 'Code envoyé par e-mail');
  }

  @override
  Future<ApiResponse<User>> verifyEmailOtp(String email, String code) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    final state = _emailOtpStates[key];
    if (state == null) {
      return ApiResponse.error(
        'Aucun code actif. Demandez un nouveau code.',
        code: 'otp_none',
      );
    }
    if (DateTime.now().isAfter(state.expiresAt)) {
      _emailOtpStates.remove(key);
      return ApiResponse.error(
        'Code expiré. Demandez un nouveau code.',
        code: 'otp_expired',
      );
    }
    if (state.attemptsLeft <= 0 || state.code != code) {
      state.attemptsLeft -= 1;
      final locked = state.attemptsLeft <= 0;
      return ApiResponse.error(
        locked
            ? 'Trop de tentatives. Demandez un nouveau code.'
            : 'Code incorrect.',
        code: locked ? 'otp_locked' : 'otp_invalid',
      );
    }
    _emailOtpStates.remove(key);
    // Inbox proven → find-or-create; a fresh account has no phone (the
    // mandatory phone step follows).
    final user = MockData.users.firstWhere(
      (u) => u.email?.toLowerCase() == key,
      orElse: () {
        final created = User(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          email: key,
          authProvider: 'email',
          createdAt: DateTime.now(),
        );
        MockData.users.add(created);
        return created;
      },
    );
    _currentUser = user;
    await _persistSession(user);
    return ApiResponse.success(user, message: 'Connexion réussie');
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentUser = null;
    await _sessionStore.clear();
  }

  @override
  Future<User?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (_currentUser != null) return _currentUser;

    final raw = await _sessionStore.read();
    if (raw == null) return null;
    try {
      final session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.isExpired(DateTime.now())) {
        await _sessionStore.clear();
        return null;
      }
      _currentUser = session.user;
      return _currentUser;
    } catch (_) {
      await _sessionStore.clear();
      return null;
    }
  }

  @override
  Future<ApiResponse<User>> updateUser(
      {String? name, String? email, String? avatarUrl, String? phone}) async {
    await Future.delayed(AppConstants.mockDelay);

    if (_currentUser == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }

    var updatedUser = _currentUser!.copyWith(
      name: (name != null && name.isNotEmpty) ? name : _currentUser!.name,
      email:
          email == null ? _currentUser!.email : (email.isEmpty ? null : email),
      avatarUrl: avatarUrl ?? _currentUser!.avatarUrl,
    );
    if (phone != null && phone != _currentUser!.phoneNumber) {
      // Contact phone: unverified until proven via SMS later. copyWith can't
      // null a field, so rebuild for the clear case.
      updatedUser = phone.isEmpty
          ? User(
              id: updatedUser.id,
              name: updatedUser.name,
              email: updatedUser.email,
              authProvider: updatedUser.authProvider,
              avatarUrl: updatedUser.avatarUrl,
              createdAt: updatedUser.createdAt,
            )
          : updatedUser.copyWith(phoneNumber: phone, phoneVerified: false);
    }

    _currentUser = updatedUser;

    final index = MockData.users.indexWhere((u) => u.id == _currentUser!.id);
    if (index != -1) {
      MockData.users[index] = updatedUser;
    }
    await _persistSession(updatedUser);

    return ApiResponse.success(updatedUser);
  }

  @override
  Future<ApiResponse<void>> deleteAccount() async {
    await Future.delayed(AppConstants.mockDelay);

    final user = _currentUser;
    if (user == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }

    MockData.users.removeWhere((u) => u.id == user.id);
    _otpStates.remove(user.phoneNumber);
    _currentUser = null;
    await _sessionStore.clear();

    return ApiResponse.success(null, message: 'Compte supprimé');
  }

  // Provider methods
  @override
  Future<ApiResponse<String>> sendOtpToProvider(String phoneNumber) async {
    await Future.delayed(AppConstants.mockDelay);
    const otp = '123456';
    _providerOtpStore[phoneNumber] = otp;
    return ApiResponse.success(otp, message: 'Code OTP envoyé avec succès');
  }

  @override
  Future<ApiResponse<ProviderUser>> verifyOtpForProvider(
      String phoneNumber, String otp) async {
    await Future.delayed(AppConstants.mockDelay);
    final storedOtp = _providerOtpStore[phoneNumber];
    if (storedOtp == null || storedOtp != otp) {
      return ApiResponse.error('Code OTP invalide');
    }

    // Find or create provider user
    var providerUser = MockData.providerUsers.firstWhere(
      (p) => p.phoneNumber == phoneNumber,
      orElse: () => ProviderUser(
        id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
        phoneNumber: phoneNumber,
        businessName: 'Business',
        businessType: BusinessType.other,
        createdAt: DateTime.now(),
      ),
    );

    _currentProvider = providerUser;
    _providerOtpStore.remove(phoneNumber);
    return ApiResponse.success(providerUser, message: 'Connexion réussie');
  }

  // ---- Pro auth overhaul (docs/design/pro-auth-social.md) -------------------

  /// Mock salon Google identity — LOGIN-ONLY (no auto-create).
  static const String mockProGoogleEmail = 'mock.google@salon.test';

  final Map<String, String> _providerEmailOtpStore = {}; // email -> otp

  ProviderUser? _providerByEmail(String email) {
    final key = email.trim().toLowerCase();
    for (final p in MockData.providerUsers) {
      if (p.email?.toLowerCase() == key) return p;
    }
    return null;
  }

  Future<ApiResponse<ProviderUser>> _providerLogin(String email) async {
    final account = _providerByEmail(email);
    if (account == null) {
      return ApiResponse.error(
        'Compte introuvable. Créez votre compte.',
        code: 'provider_not_found',
      );
    }
    _currentProvider = account;
    return ApiResponse.success(account, message: 'Connexion réussie');
  }

  @override
  Future<ApiResponse<ProviderUser>> signInProviderWithGoogle() async {
    await Future.delayed(AppConstants.mockDelay);
    return _providerLogin(mockProGoogleEmail);
  }

  @override
  Future<ApiResponse<ProviderUser>> signInProviderWithApple() async {
    await Future.delayed(AppConstants.mockDelay);
    return _providerLogin('mock.apple@salon.test');
  }

  @override
  Future<ApiResponse<String>> requestProviderEmailOtp(String email) async {
    await Future.delayed(AppConstants.mockDelay);
    _providerEmailOtpStore[email.trim().toLowerCase()] = demoOtp;
    return ApiResponse.success(demoOtp, message: 'Code envoyé par e-mail');
  }

  @override
  Future<ApiResponse<ProviderUser>> verifyProviderEmailOtp(
      String email, String code) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    if (_providerEmailOtpStore[key] != code) {
      return ApiResponse.error('Code incorrect.', code: 'otp_invalid');
    }
    // LOGIN-ONLY; a correct code with no salon keeps the code for register.
    final res = await _providerLogin(key);
    if (res.success) _providerEmailOtpStore.remove(key);
    return res;
  }

  ProviderUser _createProvider({
    required String email,
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) {
    final providerUser = ProviderUser(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: businessType,
      email: email.trim().toLowerCase(),
      address: address,
      createdAt: DateTime.now(),
    );
    MockData.providerUsers.add(providerUser);
    _currentProvider = providerUser;
    return providerUser;
  }

  @override
  Future<ApiResponse<ProviderUser>> registerProviderWithGoogle({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    if (_providerByEmail(mockProGoogleEmail) != null) {
      return ApiResponse.error(
        'Un compte existe déjà pour cette identité.',
        code: 'provider_exists',
      );
    }
    return ApiResponse.success(
      _createProvider(
        email: mockProGoogleEmail,
        phoneNumber: phoneNumber,
        businessName: businessName,
        businessType: businessType,
        address: address,
      ),
      message: 'Inscription réussie',
    );
  }

  @override
  Future<ApiResponse<ProviderUser>> registerProviderWithEmail({
    required String email,
    required String code,
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) async {
    await Future.delayed(AppConstants.mockDelay);
    final key = email.trim().toLowerCase();
    if (_providerEmailOtpStore[key] != code) {
      return ApiResponse.error('Code incorrect.', code: 'otp_invalid');
    }
    if (_providerByEmail(key) != null) {
      return ApiResponse.error(
        'Un compte existe déjà pour cette identité.',
        code: 'provider_exists',
      );
    }
    _providerEmailOtpStore.remove(key);
    return ApiResponse.success(
      _createProvider(
        email: key,
        phoneNumber: phoneNumber,
        businessName: businessName,
        businessType: businessType,
        address: address,
      ),
      message: 'Inscription réussie',
    );
  }

  @override
  Future<ProviderUser?> getCurrentProvider() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return _currentProvider;
  }

  @override
  Future<void> logoutProvider() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentProvider = null;
  }
}
