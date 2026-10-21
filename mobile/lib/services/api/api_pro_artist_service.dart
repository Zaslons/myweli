import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/artist.dart';
import '../../models/availability.dart' show TimeSlot;
import '../../models/provider_session.dart';
import '../interfaces/pro_artist_service_interface.dart';
import '../interfaces/session_store.dart';
import 'api_errors.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ProArtistServiceInterface] (backend
/// B-artists). The salon's staff CRUD, on the **provider** session (silent
/// refresh). The `artistId`-only edits resolve the salon from the persisted
/// session (like the catalogue's serviceId-only edits, by the same
/// [ProviderSession.actingSalonId] rule). `workingHours` is
/// JSON-normalized for the wire; `rating`/`reviewCount` are server-owned.
/// Design: docs/design/pro-artists.md.
class ApiProArtistService implements ProArtistServiceInterface {
  ApiProArtistService({
    http.Client? client,
    String? baseUrl,
    SessionStore? providerSessionStore,
  }) : _client = client ?? http.Client(),
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
    if (res == null) return networkError();
    if (res.statusCode != 200) return errorFromResponse(res);
    // The server always sends `items` (an empty list for a salon with no
    // staff): a 200 without it is an answer that did not arrive whole, never
    // « no team » — the salon export would ship it as complete
    // (docs/design/export-unreadable-200.md §2).
    final list = _decode(res.body)['items'];
    if (list is! List) return unreadable();
    final items = list
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
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/providers/$providerId/artists'),
        headers: _bearer(t),
        body: jsonEncode(_wire(data)),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode != 201) return errorFromResponse(res);
    return ApiResponse.success(Artist.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<Artist>> updateArtist(
    String artistId,
    Map<String, dynamic> data,
  ) async {
    final pid = await _providerId();
    if (pid == null) return ApiResponse.error('Compte non lié à un salon');
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/providers/$pid/artists/$artistId'),
        headers: _bearer(t),
        body: jsonEncode(_wire(data)),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode != 200) return errorFromResponse(res);
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
    if (res == null) return networkError();
    if (res.statusCode != 204 && res.statusCode != 200) {
      return errorFromResponse(res);
    }
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

  /// The salon the session ACTS IN — the same rule as
  /// ProAuthProvider.activeSalonId (the R6 selection, else the account's own
  /// salon, else the membership's), so an edit lands in the salon the screen
  /// shows. Null if not signed in or no salon is known
  /// (docs/design/services-acting-salon.md).
  Future<String?> _providerId() async {
    final raw = await _providerSessionStore.read();
    if (raw == null) return null;
    try {
      return ProviderSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      ).actingSalonId;
    } catch (_) {
      return null;
    }
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String t) => {'Authorization': 'Bearer $t'};
  Map<String, dynamic> _decode(String body) =>
      jsonDecode(body) as Map<String, dynamic>;
}
