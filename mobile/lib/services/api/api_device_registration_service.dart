import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../interfaces/device_registration_service_interface.dart';
import '../interfaces/session_store.dart';
import 'api_errors.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [DeviceRegistrationServiceInterface]
/// (`POST/DELETE /me/devices`, self-scoped). Rides a [RefreshingHttpClient]
/// (silent refresh on a 401). Wired in by DI when `AppConfig.useApiBackend` is
/// true. Design: docs/design/push-notifications-app.md.
///
/// The PRO app runs it on the provider session, and then [refreshPath] MUST be
/// `/auth/provider/refresh`: a provider refresh token sent to the consumer
/// `/auth/refresh` is refused, and a refused refresh ends the session — which
/// signed salon owners out on every cold start after the 15-minute access
/// token expired (production, 2026-10-11; docs/design/session-refresh.md).
class ApiDeviceRegistrationService
    implements DeviceRegistrationServiceInterface {
  ApiDeviceRegistrationService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
    this.refreshPath = '/auth/refresh',
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _sessionStore = sessionStore ?? InMemorySessionStore();

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;

  /// The refresh endpoint of [sessionStore]'s principal (see the class doc).
  final String refreshPath;

  late final RefreshingHttpClient _authed = RefreshingHttpClient(
    client: _client,
    baseUrl: _baseUrl,
    store: _sessionStore,
    refreshPath: refreshPath,
  );

  @override
  Future<ApiResponse<bool>> register(String token, String platform) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/me/devices'),
        headers: {..._bearer(t), 'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'platform': platform}),
      ),
    );
    return _boolFrom(res);
  }

  @override
  Future<ApiResponse<bool>> unregister(String token) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.delete(
        _uri('/me/devices'),
        headers: {..._bearer(t), 'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ),
    );
    return _boolFrom(res);
  }

  ApiResponse<bool> _boolFrom(http.Response? res) {
    if (res == null) return networkError();
    if (res.statusCode != 200) return errorFromResponse(res);
    return ApiResponse.success(true);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };
}
