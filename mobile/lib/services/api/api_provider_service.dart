import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/provider.dart';
import '../../models/provider_page.dart';
import '../interfaces/provider_service_interface.dart';
import 'api_errors.dart';

/// Real HTTP implementation of [ProviderServiceInterface] (backend B1).
///
/// It is wired in by [setupDependencyInjection] only when
/// `AppConfig.useApiBackend` is true; the app otherwise keeps the mock. The
/// method surface is identical to `MockProviderService`, so screens/providers
/// are unchanged — the swap is purely in DI.
class ApiProviderService implements ProviderServiceInterface {
  ApiProviderService({required this._client, String? baseUrl})
    : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

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
    final res = await searchProviders(
      ProviderQuery(
        text: searchQuery ?? '',
        category: category,
        commune: commune,
        sort: sort,
        availableToday: availableToday,
        page: page,
        pageSize: limit,
      ),
    );
    final data = res.data;
    if (res.success && data != null) return ApiResponse.success(data.items);
    return ApiResponse(
      success: false,
      error: res.error,
      message: res.message,
      code: res.code,
    );
  }

  /// One page of `GET /providers`, with its `total`
  /// (docs/design/consumer-search.md §3). Each parameter goes only when it
  /// narrows: an empty text, no category, no commune, the default sort and
  /// « Disponible aujourd’hui » off are no parameter at all.
  @override
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query) async {
    final category = query.category;
    final commune = query.commune;
    final uri = Uri.parse('$_baseUrl/providers').replace(
      queryParameters: <String, String>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (query.text.isNotEmpty) 'q': query.text,
        if (commune != null && commune.isNotEmpty) 'commune': commune,
        if (query.sort != ProviderSort.relevance) 'sort': query.sort.query,
        if (query.availableToday) 'availableToday': 'true',
        'page': '${query.page}',
        'pageSize': '${query.pageSize}',
      },
    );

    // Three facts, three sentences (docs/design/app-failure-messages.md
    // §1.2): nothing answered; a refusal or a page; an answer that does not
    // read. One catch used to call all three « Connexion au serveur
    // impossible ».
    final http.Response res;
    try {
      res = await _client.get(uri);
    } catch (_) {
      return networkError();
    }
    if (res.statusCode != 200) return errorFromResponse(res);
    return readOrUnreadable(res, (json) {
      final body = json! as Map<String, dynamic>;
      return ProviderPage(
        items: (body['items']! as List)
            .map((e) => Provider.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (body['page']! as num).toInt(),
        pageSize: (body['pageSize']! as num).toInt(),
        total: (body['total']! as num).toInt(),
      );
    });
  }

  /// The public salon read.
  ///
  /// **It sets `code:` now, like every other service does**
  /// (`api_appointment_service._errorFrom`, `api_review_service`,
  /// `api_favorites_service`). It was the only one that did not, so a screen
  /// could tell a 404 from a dead network only by comparing French strings —
  /// and the string it compared against, « Provider non trouvé », was English
  /// jargon rendered on a consumer screen. The route is about to stop serving
  /// salons that are `draft` or `suspended` (Decision C), which makes the
  /// difference between « this salon is gone » and « your connection dropped »
  /// something the UI has to say out loud.
  @override
  Future<ApiResponse<Provider>> getProviderById(SalonId id) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$_baseUrl/providers/$id'));
    } catch (_) {
      return networkError();
    }
    if (res.statusCode == 404) {
      return ApiResponse.error(
        'Ce salon n’est plus disponible sur MyWeli.',
        code: 'not_found',
      );
    }
    if (res.statusCode != 200) {
      // The code stays what `salonLoadFailure` reads; the words are the
      // generic sentence, never « Erreur serveur (500) ».
      return ApiResponse.error(kGenericErrorMessage, code: 'server_error');
    }
    return readOrUnreadable(
      res,
      (json) => Provider.fromJson(json! as Map<String, dynamic>),
    );
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
