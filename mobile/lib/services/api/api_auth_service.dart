import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/provider_session.dart';
import '../../models/provider_user.dart';
import '../../models/session.dart';
import '../../models/user.dart';
import '../interfaces/auth_service_interface.dart';
import '../interfaces/session_store.dart';

/// Real HTTP implementation of [AuthServiceInterface] (backend B2 + B-prov).
///
/// Both consumer and provider auth go to the backend. Each session is persisted
/// via its own [SessionStore] (distinct secure keys) exactly like the mock, so
/// cold-start restore and logout are unchanged and the two sessions never
/// overwrite each other. Wired in by DI only when `AppConfig.useApiBackend` is
/// true. No provider refresh flow yet (the backend returns only an access
/// token); the persisted provider session has no client-side expiry, mirroring
/// the consumer side until the refresh slice lands.
class ApiAuthService implements AuthServiceInterface {
  ApiAuthService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
    SessionStore? providerSessionStore,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _sessionStore = sessionStore ?? InMemorySessionStore(),
        _providerSessionStore = providerSessionStore ?? InMemorySessionStore();

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;
  final SessionStore _providerSessionStore;

  User? _currentUser;
  String? _accessToken;
  ProviderUser? _currentProvider;
  String? _providerToken;

  // ---- Consumer auth (real backend) ----------------------------------------

  @override
  Future<ApiResponse<String>> sendOtp(String phoneNumber) async {
    final res = await _post('/auth/otp/request', {'phoneNumber': phoneNumber});
    if (res == null) return _networkError();
    if (res.statusCode == 202) {
      final body = _decode(res.body);
      return ApiResponse.success(
        body['devCode'] as String? ?? '',
        message: 'Code OTP envoyé',
      );
    }
    return _errorFrom(res);
  }

  @override
  Future<ApiResponse<User>> verifyOtp(String phoneNumber, String otp) async {
    final res = await _post(
      '/auth/otp/verify',
      {'phoneNumber': phoneNumber, 'code': otp},
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);

    final body = _decode(res.body);
    final tokens = body['tokens'] as Map<String, dynamic>;
    final user = User.fromJson(body['user'] as Map<String, dynamic>);
    _currentUser = user;
    _accessToken = tokens['accessToken'] as String;
    await _persistSession(user, _accessToken!);
    return ApiResponse.success(user, message: 'Connexion réussie');
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
    _accessToken = null;
    await _sessionStore.clear();
  }

  @override
  Future<User?> getCurrentUser() async {
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
      _accessToken = session.token;
      return _currentUser;
    } catch (_) {
      await _sessionStore.clear();
      return null;
    }
  }

  @override
  Future<ApiResponse<User>> updateUser({
    String? name,
    String? email,
    String? avatarUrl,
  }) async {
    await getCurrentUser(); // hydrate the token after a cold start
    if (_accessToken == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }
    final res = await _patch('/me', {
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    });
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);

    final user = User.fromJson(_decode(res.body));
    _currentUser = user;
    await _persistSession(user, _accessToken!);
    return ApiResponse.success(user);
  }

  @override
  Future<ApiResponse<void>> deleteAccount() async {
    await getCurrentUser();
    if (_accessToken == null) {
      return ApiResponse.error('Utilisateur non connecté');
    }
    final res = await _send(
      () => _client.delete(_uri('/me'), headers: _authHeaders()),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204) return _errorFrom(res);
    await logout();
    return ApiResponse.success(null, message: 'Compte supprimé');
  }

  // ---- Provider auth (real backend) ----------------------------------------

  @override
  Future<ApiResponse<String>> sendOtpToProvider(String phoneNumber) async {
    final res =
        await _post('/auth/provider/otp/request', {'phoneNumber': phoneNumber});
    if (res == null) return _networkError();
    if (res.statusCode == 202) {
      final body = _decode(res.body);
      return ApiResponse.success(
        body['devCode'] as String? ?? '',
        message: 'Code OTP envoyé',
      );
    }
    return _errorFrom(res);
  }

  @override
  Future<ApiResponse<ProviderUser>> verifyOtpForProvider(
    String phoneNumber,
    String otp,
  ) async {
    final res = await _post(
      '/auth/provider/otp/verify',
      {'phoneNumber': phoneNumber, 'code': otp},
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);

    final body = _decode(res.body);
    final provider =
        ProviderUser.fromJson(body['provider'] as Map<String, dynamic>);
    _currentProvider = provider;
    _providerToken = body['accessToken'] as String;
    await _persistProviderSession(provider, _providerToken!);
    return ApiResponse.success(provider, message: 'Connexion réussie');
  }

  @override
  Future<ApiResponse<ProviderUser>> registerProvider({
    required String phoneNumber,
    required String businessName,
    required BusinessType businessType,
    String? address,
  }) async {
    // Creates the account and dispatches a code — the provider then verifies on
    // the OTP screen, which is where they actually log in. No session yet.
    final res = await _post('/auth/provider/register', {
      'phoneNumber': phoneNumber,
      'businessName': businessName,
      'businessType': businessType.name,
      if (address != null) 'address': address,
    });
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);

    final body = _decode(res.body);
    final provider =
        ProviderUser.fromJson(body['provider'] as Map<String, dynamic>);
    return ApiResponse.success(provider, message: 'Inscription réussie');
  }

  @override
  Future<ProviderUser?> getCurrentProvider() async {
    if (_currentProvider != null) return _currentProvider;
    final raw = await _providerSessionStore.read();
    if (raw == null) return null;
    try {
      final session =
          ProviderSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _currentProvider = session.provider;
      _providerToken = session.token;
      return _currentProvider;
    } catch (_) {
      await _providerSessionStore.clear();
      return null;
    }
  }

  @override
  Future<void> logoutProvider() async {
    _currentProvider = null;
    _providerToken = null;
    await _providerSessionStore.clear();
  }

  // ---- helpers --------------------------------------------------------------

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _authHeaders() => {
        'content-type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<http.Response?> _post(String path, Map<String, dynamic> body) =>
      _send(() => _client.post(
            _uri(path),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          ));

  Future<http.Response?> _patch(String path, Map<String, dynamic> body) =>
      _send(() => _client.patch(
            _uri(path),
            headers: _authHeaders(),
            body: jsonEncode(body),
          ));

  Future<http.Response?> _send(Future<http.Response> Function() run) async {
    try {
      return await run();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decode(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  Future<void> _persistSession(User user, String accessToken) async {
    // No client-side expiry: stay logged in until logout (the short-lived
    // access token is refreshed server-side in a later slice).
    final session = Session(token: accessToken, user: user);
    await _sessionStore.save(jsonEncode(session.toJson()));
  }

  Future<void> _persistProviderSession(
    ProviderUser provider,
    String accessToken,
  ) async {
    final session = ProviderSession(token: accessToken, provider: provider);
    await _providerSessionStore.save(jsonEncode(session.toJson()));
  }

  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Connexion au serveur impossible');

  /// Maps the backend error envelope to an [ApiResponse] error, preserving the
  /// machine `code` so callers branch exactly as they do with the mock.
  ApiResponse<T> _errorFrom<T>(http.Response res) {
    String? code;
    try {
      code = _decode(res.body)['error'] as String?;
    } catch (_) {
      code = null;
    }
    return ApiResponse.error(_messageFor(code), code: code);
  }

  String _messageFor(String? code) {
    switch (code) {
      case 'otp_none':
        return 'Aucun code actif. Demandez un nouveau code.';
      case 'otp_expired':
        return 'Code expiré. Demandez un nouveau code.';
      case 'otp_locked':
        return 'Trop de tentatives. Demandez un nouveau code.';
      case 'otp_invalid':
        return 'Code incorrect.';
      case 'otp_resend_limit':
        return 'Trop de demandes de code. Réessayez plus tard.';
      case 'invalid_phone':
      case 'invalid_input':
        return 'Numéro ou code invalide.';
      case 'provider_not_found':
        return 'Aucun compte professionnel pour ce numéro. Inscrivez-vous.';
      case 'provider_exists':
        return 'Un compte existe déjà pour ce numéro. Connectez-vous.';
      default:
        return 'Une erreur est survenue.';
    }
  }
}
