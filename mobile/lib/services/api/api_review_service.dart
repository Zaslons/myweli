import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/review.dart';
import '../interfaces/review_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ReviewServiceInterface] (backend B-reviews).
/// `submitReview` reviews a **completed appointment** (`POST
/// /appointments/{id}/review`, consumer session + silent refresh) — only
/// rating/text/photos are sent; the server derives the rest from the
/// appointment. `getProviderReviews` reads the public paginated list.
/// Design: docs/design/consumer-reviews.md.
class ApiReviewService implements ReviewServiceInterface {
  ApiReviewService({
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
  Future<ApiResponse<Review>> submitReview(Review review) async {
    if (review.appointmentId.isEmpty) {
      return ApiResponse.error('Avis lié à aucun rendez-vous');
    }
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Connectez-vous pour publier un avis');
    }
    final res = await _authed.send((t) => _client.post(
          _uri('/appointments/${review.appointmentId}/review'),
          headers: {
            'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'rating': review.rating,
            'text': review.text,
            'photoUrls': review.photoUrls,
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(
      Review.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
      message: 'Merci pour votre avis',
    );
  }

  @override
  Future<ApiResponse<List<Review>>> getProviderReviews(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = _uri('/providers/$providerId/reviews').replace(
      queryParameters: {'page': '$page', 'pageSize': '$pageSize'},
    );
    final res = await _client.get(uri); // public
    if (res.statusCode != 200) return _errorFrom(res);
    final items =
        ((jsonDecode(res.body) as Map<String, dynamic>)['items'] as List? ??
                const [])
            .map((e) => Review.fromJson(e as Map<String, dynamic>))
            .toList();
    return ApiResponse.success(items);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
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
