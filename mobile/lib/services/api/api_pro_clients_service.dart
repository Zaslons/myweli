import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/salon_client.dart';
import '../interfaces/pro_clients_service_interface.dart';
import '../interfaces/session_store.dart';
import 'api_errors.dart';
import 'idempotent_write.dart';
import 'refreshing_http_client.dart';

/// REST impl of the salon client base (module `clients` C1) against
/// `/providers/{id}/clients*` — provider-authenticated (pro session), reads
/// audited server-side. Mirrors the ApiProArtistService idiom.
class ApiProClientsService implements ProClientsServiceInterface {
  ApiProClientsService({
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
  Future<ApiResponse<SalonClientsPage>> listClients(
    SalonId providerId, {
    String? query,
    String? tag,
    int page = 1,
    int? pageSize,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final params = <String, String>{
      'page': '$page',
      if (pageSize != null) 'pageSize': '$pageSize',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/clients').replace(queryParameters: params),
        headers: _bearer(t),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode != 200) return _refused(res);
    // A page that does not read — cut off, or without its `items` / `total`
    // (SalonClientsPage.fromJson) — is a failed read, worded as `_errorFrom`
    // words an unreadable body: never an empty page, and never a throw whose
    // English text the list would show (docs/design/export-unreadable-200.md
    // §2.2).
    try {
      return ApiResponse.success(SalonClientsPage.fromJson(_decode(res.body)));
    } on FormatException {
      return unreadable();
    }
  }

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    SalonId providerId,
    String clientId,
  ) async {
    final res = await _authed.send(
      (t) => _client.get(
        _uri('/providers/$providerId/clients/$clientId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode != 200) return _refused(res);
    return ApiResponse.success(SalonClientCard.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    SalonId providerId,
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
    if (res == null) return networkError();
    if (res.statusCode != 200) return _refused(res);
    final items = ((_decode(res.body)['items'] as List?) ?? const [])
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiResponse.success(items);
  }

  @override
  Future<ApiResponse<String>> addClient(
    SalonId providerId, {
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
    if (res == null) return networkError();
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
    return _refused(res);
  }

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    SalonId providerId,
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
    if (res == null) return networkError();
    if (res.statusCode != 200) return _refused(res);
    return ApiResponse.success(SalonClient.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    SalonId providerId,
    String clientId,
    String phone,
  ) async {
    final res = await _authed.send(
      (t) => _client.patch(
        _uri('/providers/$providerId/clients/$clientId'),
        headers: _bearer(t),
        body: jsonEncode({'phone': phone}),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode == 200) {
      return ApiResponse.success(
        SalonClientPhoneChange.changed(
          SalonClientCard.fromJson(_decode(res.body)),
        ),
        message: 'Numéro mis à jour',
      );
    }
    if (res.statusCode == 409) {
      Map<String, dynamic>? body;
      try {
        body = _decode(res.body);
      } catch (_) {
        body = null; // not JSON: `_errorFrom` answers it below
      }
      if (body?['error'] == 'client_exists') {
        // The card that already has the number — the sheet offers it.
        final id = body!['clientId'];
        final takenBy = id is String ? id : null;
        return ApiResponse(
          success: false,
          data: takenBy == null ? null : SalonClientPhoneChange.taken(takenBy),
          error: _messageFor('client_exists'),
          code: 'client_exists',
        );
      }
    }
    return _refused(res);
  }

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    SalonId providerId,
    String clientId,
    String body, {
    String? idempotencyKey,
  }) async {
    // Under its key, a lost answer is asked again once — the note is added
    // once (docs/design/write-idempotency.md §4).
    final res = await sendIdempotent(
      _authed,
      (t, key) => _client.post(
        _uri('/providers/$providerId/clients/$clientId/notes'),
        headers: {..._bearer(t), ...key},
        body: jsonEncode({'body': body}),
      ),
      key: idempotencyKey,
    );
    if (res == null) return networkError();
    if (res.statusCode != 201) return _refused(res);
    return ApiResponse.success(SalonClientNote.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<bool>> deleteNote(
    SalonId providerId,
    String clientId,
    String noteId,
  ) async {
    final res = await _authed.send(
      (t) => _client.delete(
        _uri('/providers/$providerId/clients/$clientId/notes/$noteId'),
        headers: _bearer(t),
      ),
    );
    if (res == null) return networkError();
    if (res.statusCode != 204 && res.statusCode != 200) return _refused(res);
    return ApiResponse.success(true);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');
  Map<String, String> _bearer(String t) => {'Authorization': 'Bearer $t'};
  Map<String, dynamic> _decode(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  /// A refusal, worded: this service's codes keep their sentences, anything
  /// else is the generic one (docs/design/app-failure-messages.md §2.1).
  ApiResponse<T> _refused<T>(http.Response res) =>
      errorFromResponse(res, messageFor: _messageFor);

  /// The codes with words of their own; anything else is the generic sentence
  /// (`errorFromResponse`).
  String? _messageFor(String? code) => switch (code) {
    'invalid_phone' => 'Numéro invalide.',
    'client_exists' => 'Ce numéro est déjà sur une autre fiche.',
    'client_linked' => 'Numéro du compte client.',
    'invalid_tags' => 'Tags invalides (10 max, 24 caractères max).',
    'note_too_long' => 'Note trop longue (500 caractères max).',
    'not_found' => 'Client introuvable.',
    'forbidden' => 'Accès refusé.',
    _ => null,
  };
}
