import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../interfaces/favorites_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [FavoritesServiceInterface] (backend
/// B-favorites). Favorites are stored per **account** server-side, so they
/// follow the user across devices. Authenticated calls go through the consumer
/// [RefreshingHttpClient] (silent refresh on a 401); the user is the token's
/// `sub`, so the `userId` arguments are ignored — the server self-scopes.
/// `isFavorite` is derived from the list (no dedicated endpoint). Wired in by
/// DI when `AppConfig.useApiBackend` is true. Design:
/// docs/design/consumer-favorites.md.
class ApiFavoritesService implements FavoritesServiceInterface {
  ApiFavoritesService({
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
  Future<ApiResponse<List<String>>> getFavoriteProviderIds(
    String userId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/favorites'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final ids = ((body['providerIds'] as List?) ?? const [])
        .map((e) => e as String)
        .toList();
    return ApiResponse.success(ids);
  }

  @override
  Future<ApiResponse<bool>> addFavorite(String userId, String providerId) =>
      _toggle('POST', providerId);

  @override
  Future<ApiResponse<bool>> removeFavorite(String userId, String providerId) =>
      _toggle('DELETE', providerId);

  Future<ApiResponse<bool>> _toggle(String method, String providerId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final uri = _uri('/me/favorites/$providerId');
    final res = await _authed.send(
      (t) => method == 'POST'
          ? _client.post(uri, headers: _bearer(t))
          : _client.delete(uri, headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204 && res.statusCode != 200) {
      return _errorFrom(res);
    }
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> isFavorite(String userId, String providerId) async {
    final res = await getFavoriteProviderIds(userId);
    if (!res.success) {
      return ApiResponse.error(res.error ?? 'Erreur', code: res.code);
    }
    return ApiResponse.success(res.data!.contains(providerId));
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String token) =>
      {'Authorization': 'Bearer $token'};
  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Pas de connexion. Réessayez.');

  ApiResponse<T> _errorFrom<T>(http.Response res) {
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
}
