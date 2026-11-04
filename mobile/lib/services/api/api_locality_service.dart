import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/locality.dart';
import '../interfaces/locality_service_interface.dart';
import 'api_errors.dart';

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
    // Nothing answered, a refusal or a page, an answer that does not read:
    // three facts, three sentences (docs/design/app-failure-messages.md §1.2
    // — this one said « Connexion impossible » for all of them).
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$_baseUrl/localities'));
    } catch (_) {
      return networkError();
    }
    if (res.statusCode != 200) return errorFromResponse(res);
    return readOrUnreadable(
      res,
      (json) =>
          (((json! as Map<String, dynamic>)['countries'] as List?) ?? const [])
              .map((c) => LocalityCountry.fromJson(c as Map<String, dynamic>))
              .toList(),
    );
  }
}
