import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../interfaces/device_registration_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [DeviceRegistrationServiceInterface]
/// (`POST/DELETE /me/devices`, self-scoped). Rides the consumer
/// [RefreshingHttpClient] (silent refresh on a 401). Wired in by DI when
/// `AppConfig.useApiBackend` is true. Design: docs/design/push-notifications-app.md.
class ApiDeviceRegistrationService
    implements DeviceRegistrationServiceInterface {
  ApiDeviceRegistrationService({
    http.Client? client,
    String? baseUrl,
    SessionStore? sessionStore,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _sessionStore = sessionStore ?? InMemorySessionStore();

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _sessionStore;

  late final RefreshingHttpClient _authed = RefreshingHttpClient(
    client: _client,
    baseUrl: _baseUrl,
    store: _sessionStore,
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
    if (res == null) return ApiResponse.error('Pas de connexion. Réessayez.');
    if (res.statusCode != 200) {
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return ApiResponse.error(
          body['message'] as String? ?? 'Erreur',
          code: body['error'] as String?,
        );
      } catch (_) {
        return ApiResponse.error('Erreur');
      }
    }
    return ApiResponse.success(true);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String token) =>
      {'Authorization': 'Bearer $token'};
}
