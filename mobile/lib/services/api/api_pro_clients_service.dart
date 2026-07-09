import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/salon_client.dart';
import '../interfaces/pro_clients_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// REST impl of the salon client base (module `clients` C1) against
/// `/providers/{id}/clients*` — provider-authenticated (pro session), reads
/// audited server-side. Mirrors the ApiProArtistService idiom.
class ApiProClientsService implements ProClientsServiceInterface {
  ApiProClientsService({
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
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final params = <String, String>{
      'page': '$page',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/clients').replace(
          queryParameters: params,
        ),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(SalonClientsPage.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  ) async {
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/clients/$clientId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(SalonClientCard.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    String providerId,
    String clientId, {
    int page = 1,
  }) async {
    final res = await _authed.send(
      (t) => _client.get(
        _uri(
          '/providers/$providerId/clients/$clientId/visits',
        ).replace(queryParameters: {'page': '$page'}),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    final items = ((_decode(res.body)['items'] as List?) ?? const [])
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<String>> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) async {
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/providers/$providerId/clients'),
        headers: _bearer(t),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode == 201) {
      return ApiResponse.success(
        _decode(res.body)['id'] as String,
        message: 'Client ajouté',
      );
    }
    if (res.statusCode == 409) {
      // Dedupe: carry the EXISTING card's id so the UI opens it.
      return ApiResponse(
        success: false,
        data: _decode(res.body)['clientId'] as String?,
        error: 'Ce numéro existe déjà.',
        code: 'client_exists',
      );
    }
    return _errorFrom(res);
  }

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) async {
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/providers/$providerId/clients/$clientId'),
        headers: _bearer(t),
        body: jsonEncode({'tags': tags}),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(SalonClient.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body,
  ) async {
    final res = await _authed.send(
      (t) => _client.post(
        _uri('/providers/$providerId/clients/$clientId/notes'),
        headers: _bearer(t),
        body: jsonEncode({'body': body}),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 201) return _errorFrom(res);
    return ApiResponse.success(SalonClientNote.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<bool>> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  ) async {
    final res = await _authed.send(
      (t) => _client.delete(
        _uri('/providers/$providerId/clients/$clientId/notes/$noteId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 204 && res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(true);
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
        _messageFor(body['error'] as String?),
        code: body['error'] as String?,
      );
    } catch (_) {
      return ApiResponse.error('Erreur');
    }
  }

  String _messageFor(String? code) => switch (code) {
        'invalid_phone' => 'Numéro invalide.',
        'invalid_tags' => 'Tags invalides (10 max, 24 caractères max).',
        'note_too_long' => 'Note trop longue (500 caractères max).',
        'not_found' => 'Client introuvable.',
        'forbidden' => 'Accès refusé.',
        _ => 'Une erreur est survenue.',
      };
}
