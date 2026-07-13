import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/locality.dart';
import '../interfaces/locality_service_interface.dart';

/// Real HTTP implementation of [LocalityServiceInterface] — `GET /localities`
/// (multi-pays MP1; public, cacheable). Wired by [setupDependencyInjection]
/// when `AppConfig.useApiBackend` is true.
class ApiLocalityService implements LocalityServiceInterface {
  ApiLocalityService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<ApiResponse<List<LocalityCountry>>> getLocalities() async {
    try {
      final res = await _client.get(Uri.parse('$_baseUrl/localities'));
      if (res.statusCode != 200) {
        return ApiResponse.error('Erreur serveur (${res.statusCode})');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final countries = ((body['countries'] as List?) ?? const [])
          .map((c) => LocalityCountry.fromJson(c as Map<String, dynamic>))
          .toList();
      return ApiResponse.success(countries);
    } catch (_) {
      return ApiResponse.error('Connexion impossible. Réessayez.');
    }
  }
}
