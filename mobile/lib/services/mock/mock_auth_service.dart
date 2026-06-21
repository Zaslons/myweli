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
  Future<ApiResponse<User>> updateUser({String? name, String? email}) async {
    await Future.delayed(AppConstants.mockDelay);

    if (_currentUser == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }

    final updatedUser = _currentUser!.copyWith(
      name: (name != null && name.isNotEmpty) ? name : _currentUser!.name,
      email:
          email == null ? _currentUser!.email : (email.isEmpty ? null : email),
    );

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

  @override
  Future<ApiResponse<ProviderUser>> registerProvider({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    // Check if provider already exists
    if (MockData.providerUsers.any((p) => p.phoneNumber == phoneNumber)) {
      return ApiResponse.error('Un compte existe déjà avec ce numéro');
    }

    // Create new provider user
    final providerUser = ProviderUser(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: businessType,
      address: address,
      createdAt: DateTime.now(),
    );

    MockData.providerUsers.add(providerUser);

    // Send OTP
    const otp = '123456';
    _providerOtpStore[phoneNumber] = otp;

    return ApiResponse.success(providerUser,
        message: 'Inscription réussie. Code OTP envoyé.');
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
