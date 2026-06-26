import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/artist.dart';
import '../../models/availability.dart' show TimeSlot;
import '../../models/provider_session.dart';
import '../interfaces/pro_artist_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ProArtistServiceInterface] (backend
/// B-artists). The salon's staff CRUD, on the **provider** session (silent
/// refresh). The `artistId`-only edits resolve the salon from the persisted
/// session (like the catalogue's serviceId-only edits). `workingHours` is
/// JSON-normalized for the wire; `rating`/`reviewCount` are server-owned.
/// Design: docs/design/pro-artists.md.
class ApiProArtistService implements ProArtistServiceInterface {
  ApiProArtistService({
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
  Future<ApiResponse<List<Artist>>> getArtists(String providerId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/artists'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final items = ((_decode(res.body)['items'] as List?) ?? const [])
        .map((e) => Artist.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<Artist>> createArtist(
    String providerId,
    Map<String, dynamic> data,
  ) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((t) => _client.post(
          _uri('/providers/$providerId/artists'),
          headers: _bearer(t),
          body: jsonEncode(_wire(data)),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(Artist.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  ) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send((t) => _client.patch(
          _uri('/providers/$pid/artists/$artistId'),
          headers: _bearer(t),
          body: jsonEncode(_wire(data)),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(Artist.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<bool>> deleteArtist(String artistId) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send(
      (t) => _client.delete(
        _uri('/providers/$pid/artists/$artistId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204 && res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true);
  }

  /// JSON-safe body for create/update: keep editable fields and normalize
  /// `workingHours` (int weekday keys to strings, `TimeSlot` values to json).
  Map<String, dynamic> _wire(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final k in const ['name', 'specialization', 'imageUrl']) {
      if (data.containsKey(k)) out[k] = data[k];
    }
    final wh = data['workingHours'];
    if (wh is Map) {
      out['workingHours'] = wh.map(
        (key, value) => MapEntry(
          '$key',
          (value as List).map((s) => s is TimeSlot ? s.toJson() : s).toList(),
        ),
      );
    }
    return out;
  }

  Future<String?> _providerId() async {
    final raw = await _providerSessionStore.read();
    if (raw == null) return null;
    try {
      return ProviderSession.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .provider
          .providerId;
    } catch (_) {
      return null;
    }
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String t) => {'Authorization': 'Bearer $t'};
  Map<String, dynamic> _decode(String body) =>
      jsonDecode(body) as Map<String, dynamic>;
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
