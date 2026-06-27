import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/provider.dart';
import '../interfaces/provider_service_interface.dart';

/// Real HTTP implementation of [ProviderServiceInterface] (backend B1).
///
/// It is wired in by [setupDependencyInjection] only when
/// `AppConfig.useApiBackend` is true; the app otherwise keeps the mock. The
/// method surface is identical to `MockProviderService`, so screens/providers
/// are unchanged — the swap is purely in DI.
class ApiProviderService implements ProviderServiceInterface {
  ApiProviderService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/providers').replace(
      queryParameters: <String, String>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (searchQuery != null && searchQuery.isNotEmpty) 'q': searchQuery,
        if (commune != null && commune.isNotEmpty) 'commune': commune,
        if (sort != ProviderSort.relevance) 'sort': sort.query,
        if (availableToday) 'availableToday': 'true',
        'page': '$page',
        'pageSize': '$limit',
      },
    );

    try {
      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        return ApiResponse.error('Erreur serveur (${res.statusCode})');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['items'] as List)
          .map((e) => Provider.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResponse.success(items);
    } catch (_) {
      return ApiResponse.error('Connexion au serveur impossible');
    }
  }

  @override
  Future<ApiResponse<Provider>> getProviderById(String id) async {
    try {
      final res = await _client.get(Uri.parse('$_baseUrl/providers/$id'));
      if (res.statusCode == 404) {
        return ApiResponse.error('Provider non trouvé');
      }
      if (res.statusCode != 200) {
        return ApiResponse.error('Erreur serveur (${res.statusCode})');
      }
      return ApiResponse.success(
        Provider.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
      );
    } catch (_) {
      return ApiResponse.error('Connexion au serveur impossible');
    }
  }

  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() {
    // The list endpoint is sorted by rating desc, so the first page is the
    // featured set. Proper curation/flags land with the pro write slice.
    return getProviders(limit: 3);
  }

  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) {
    // Proximity sorting needs the lat/lng query params + a geo index (later
    // slice); for now return a page of providers, like the mock.
    return getProviders(limit: 50);
  }
}
