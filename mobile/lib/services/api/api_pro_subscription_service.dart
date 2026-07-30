import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/api_response.dart';
import '../../models/salon_subscription.dart';
import '../interfaces/session_store.dart';
import '../interfaces/subscription_service_interface.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [SubscriptionServiceInterface] (pricing
/// pivot, team access R2a/R3): `GET/PUT /providers/{id}/subscription` on the
/// **provider** session (silent refresh). The SETUP state is the server's
/// 404 → code `no_offer`. Design: docs/design/team-access-r3-app.md.
class ApiProSubscriptionService implements SubscriptionServiceInterface {
  ApiProSubscriptionService({
    http.Client? client,
    String? baseUrl,
    SessionStore? providerSessionStore,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _providerSessionStore = providerSessionStore ?? InMemorySessionStore() {
    _authed = RefreshingHttpClient(
      client: _client,
      baseUrl: _baseUrl,
      store: _providerSessionStore,
      refreshPath: '/auth/provider/refresh',
    );
  }

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _providerSessionStore;
  late final RefreshingHttpClient _authed;

  @override
  Future<ApiResponse<SalonSubscription>> getSalonSubscription(
    String providerId,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/subscription'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode == 404) return ApiResponse.error('', code: 'no_offer');
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      SalonSubscription.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponse<SalonSubscription>> chooseOffer(
    String providerId,
    SalonTier tier,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.put(
        _uri('/providers/$providerId/subscription'),
        headers: {..._bearer(t), 'Content-Type': 'application/json'},
        body: jsonEncode({'tier': tier.name}),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      SalonSubscription.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
    );
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String t) => {'Authorization': 'Bearer $t'};
  ApiResponse<T> _networkError<T>() =>
      ApiResponse.error('Pas de connexion. Réessayez.');

  ApiResponse<T> _errorFrom<T>(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final code = body['error'] as String?;
      return ApiResponse.error(teamErrorMessage(code), code: code);
    } catch (_) {
      return ApiResponse.error('Erreur');
    }
  }
}
