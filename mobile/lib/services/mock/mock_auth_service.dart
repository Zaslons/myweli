import 'dart:async';
import '../../models/user.dart';
import '../../models/provider_user.dart';
import '../../models/api_response.dart';
import '../../core/constants/app_constants.dart';
import '../interfaces/auth_service_interface.dart';
import 'mock_data.dart';

class MockAuthService implements AuthServiceInterface {
  User? _currentUser;
  ProviderUser? _currentProvider;
  final Map<String, String> _otpStore = {}; // phone -> otp
  final Map<String, String> _providerOtpStore = {}; // phone -> otp

  @override
  Future<ApiResponse<String>> sendOtp(String phoneNumber) async {
    // Simulate API delay
    await Future.delayed(AppConstants.mockDelay);

    // Generate a simple OTP (for demo: always "123456")
    final otp = '123456';
    _otpStore[phoneNumber] = otp;

    return ApiResponse.success(otp, message: 'Code OTP envoyé avec succès');
  }

  @override
  Future<ApiResponse<User>> verifyOtp(String phoneNumber, String otp) async {
    // Simulate API delay
    await Future.delayed(AppConstants.mockDelay);

    // Check if OTP is valid
    final storedOtp = _otpStore[phoneNumber];
    if (storedOtp == null || storedOtp != otp) {
      return ApiResponse.error('Code OTP invalide');
    }

    // Find or create user
    var user = MockData.users.firstWhere(
      (u) => u.phoneNumber == phoneNumber,
      orElse: () => User(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
      ),
    );

    _currentUser = user;
    _otpStore.remove(phoneNumber);

    return ApiResponse.success(user, message: 'Connexion réussie');
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentUser = null;
  }

  @override
  Future<User?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return _currentUser;
  }

  @override
  Future<ApiResponse<User>> updateUser({String? name, String? email}) async {
    await Future.delayed(AppConstants.mockDelay);

    if (_currentUser == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }

    final updatedUser = _currentUser!.copyWith(
      name: (name != null && name.isNotEmpty) ? name : _currentUser!.name,
      email: email == null
          ? _currentUser!.email
          : (email.isEmpty ? null : email),
    );

    _currentUser = updatedUser;

    final index = MockData.users.indexWhere((u) => u.id == _currentUser!.id);
    if (index != -1) {
      MockData.users[index] = updatedUser;
    }

    return ApiResponse.success(updatedUser);
  }

  // Provider methods
  @override
  Future<ApiResponse<String>> sendOtpToProvider(String phoneNumber) async {
    await Future.delayed(AppConstants.mockDelay);
    final otp = '123456';
    _providerOtpStore[phoneNumber] = otp;
    return ApiResponse.success(otp, message: 'Code OTP envoyé avec succès');
  }

  @override
  Future<ApiResponse<ProviderUser>> verifyOtpForProvider(String phoneNumber, String otp) async {
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
    final otp = '123456';
    _providerOtpStore[phoneNumber] = otp;

    return ApiResponse.success(providerUser, message: 'Inscription réussie. Code OTP envoyé.');
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



