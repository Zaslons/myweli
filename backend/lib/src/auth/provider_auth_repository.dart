import 'dart:math';

import 'auth_repository.dart' show OtpRequestResult;
import 'tokens.dart';

/// Public-facing provider-account fields. Mirrors the app's `ProviderUser` DTO
/// (and the OpenAPI `ProviderUser` schema) field-for-field. `kycDocs` is empty
/// here — KYC submission is its own slice.
class ProviderAccount {
  ProviderAccount({
    required this.id,
    required this.phoneNumber,
    required this.businessName,
    required this.businessType,
    required this.createdAt,
    this.name,
    this.email,
    this.address,
    this.verificationStatus = 'pending',
    this.rejectionReason,
    this.providerId,
  });

  final String id;
  final String phoneNumber;
  final String businessName;
  final String businessType;
  final DateTime createdAt;
  String? name;
  String? email;
  String? address;
  String verificationStatus;
  String? rejectionReason;
  String? providerId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'name': name,
    'businessName': businessName,
    'businessType': businessType,
    'email': email,
    'address': address,
    'verificationStatus': verificationStatus,
    'rejectionReason': rejectionReason,
    'kycDocs': const <Map<String, dynamic>>[],
    'createdAt': createdAt.toIso8601String(),
    'providerId': providerId,
  };
}

/// Register + send-OTP outcome (`devCode` only outside production).
typedef ProviderRegisterResult = ({
  bool ok,
  String? error,
  ProviderAccount? provider,
  String? devCode,
  int expiresInSeconds,
});

/// Verify outcome: the provider account + a signed access token (role
/// `provider`). No refresh flow yet — added with the provider write slice.
typedef ProviderVerifyResult = ({
  bool ok,
  String? error,
  ProviderAccount? provider,
  String? accessToken,
});

/// Provider auth store + security logic (docs/BACKEND.md §3): hashed OTP with an
/// attempt/resend budget, mirroring the consumer flow. In-memory now; a Postgres
/// impl satisfies the same interface in a follow-up.
abstract interface class ProviderAuthRepository {
  Future<OtpRequestResult> requestOtp(String phoneNumber);
  Future<ProviderRegisterResult> register({
    required String phoneNumber,
    required String businessName,
    required String businessType,
    String? address,
  });
  Future<ProviderVerifyResult> verifyOtp(String phoneNumber, String code);
}

class _Otp {
  _Otp({
    required this.codeHash,
    required this.expiresAt,
    required this.attemptsLeft,
    required this.resendsLeft,
  });
  final String codeHash;
  final DateTime expiresAt;
  int attemptsLeft;
  int resendsLeft;
}

class InMemoryProviderAuthRepository implements ProviderAuthRepository {
  InMemoryProviderAuthRepository({
    required TokenService tokens,
    required bool isProd,
    Duration otpValidity = const Duration(minutes: 5),
    int maxAttempts = 5,
    int maxResends = 3,
  }) : _tokens = tokens,
       _isProd = isProd,
       _otpValidity = otpValidity,
       _maxAttempts = maxAttempts,
       _maxResends = maxResends;

  final TokenService _tokens;
  final bool _isProd;
  final Duration _otpValidity;
  final int _maxAttempts;
  final int _maxResends;
  final Random _random = Random.secure();

  final Map<String, ProviderAccount> _byPhone = {};
  final Map<String, _Otp> _otps = {};

  @override
  Future<OtpRequestResult> requestOtp(String phoneNumber) async {
    final issued = _issueOtp(phoneNumber);
    if (issued == null) {
      return (
        ok: false,
        error: 'otp_resend_limit',
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    return (
      ok: true,
      error: null,
      devCode: issued.devCode,
      expiresInSeconds: issued.expiresInSeconds,
    );
  }

  @override
  Future<ProviderRegisterResult> register({
    required String phoneNumber,
    required String businessName,
    required String businessType,
    String? address,
  }) async {
    if (_byPhone.containsKey(phoneNumber)) {
      return (
        ok: false,
        error: 'provider_exists',
        provider: null,
        devCode: null,
        expiresInSeconds: 0,
      );
    }
    final account = ProviderAccount(
      id: _newId('provider'),
      phoneNumber: phoneNumber,
      businessName: businessName,
      businessType: businessType,
      address: address,
      createdAt: DateTime.now().toUtc(),
    );
    _byPhone[phoneNumber] = account;
    final otp = _issueOtp(phoneNumber)!; // fresh phone → always issues
    return (
      ok: true,
      error: null,
      provider: account,
      devCode: otp.devCode,
      expiresInSeconds: otp.expiresInSeconds,
    );
  }

  @override
  Future<ProviderVerifyResult> verifyOtp(
    String phoneNumber,
    String code,
  ) async {
    final otp = _otps[phoneNumber];
    if (otp == null) {
      return (ok: false, error: 'otp_none', provider: null, accessToken: null);
    }
    if (DateTime.now().toUtc().isAfter(otp.expiresAt)) {
      _otps.remove(phoneNumber);
      return (
        ok: false,
        error: 'otp_expired',
        provider: null,
        accessToken: null,
      );
    }
    if (otp.attemptsLeft <= 0) {
      return (
        ok: false,
        error: 'otp_locked',
        provider: null,
        accessToken: null,
      );
    }
    if (otp.codeHash != _tokens.hashToken(code)) {
      otp.attemptsLeft -= 1;
      return (
        ok: false,
        error: otp.attemptsLeft <= 0 ? 'otp_locked' : 'otp_invalid',
        provider: null,
        accessToken: null,
      );
    }
    final account = _byPhone[phoneNumber];
    if (account == null) {
      // Must register before logging in (unlike the lax mock).
      return (
        ok: false,
        error: 'provider_not_found',
        provider: null,
        accessToken: null,
      );
    }
    _otps.remove(phoneNumber);
    final access = _tokens.issueAccessToken(
      subject: account.id,
      role: 'provider',
    );
    return (
      ok: true,
      error: null,
      provider: account,
      accessToken: access.token,
    );
  }

  ({String? devCode, int expiresInSeconds})? _issueOtp(String phoneNumber) {
    final existing = _otps[phoneNumber];
    if (existing != null && existing.resendsLeft <= 0) return null;
    final resendsLeft = existing == null
        ? _maxResends
        : existing.resendsLeft - 1;
    final code = (100000 + _random.nextInt(900000)).toString();
    _otps[phoneNumber] = _Otp(
      codeHash: _tokens.hashToken(code),
      expiresAt: DateTime.now().toUtc().add(_otpValidity),
      attemptsLeft: _maxAttempts,
      resendsLeft: resendsLeft,
    );
    return (
      devCode: _isProd ? null : code,
      expiresInSeconds: _otpValidity.inSeconds,
    );
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
