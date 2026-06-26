import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../../models/kyc_document.dart';
import '../interfaces/pro_kyc_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Real HTTP implementation of [ProKycServiceInterface] (backend B-kyc). KYC
/// documents upload to a **private** bucket via `POST /uploads/sign?purpose=kyc`
/// (the bytes go client → storage directly; only the returned key is kept), then
/// `POST /me/kyc` records the metadata + sets the status to `pending`. On the
/// **provider** session (silent refresh), self-scoped by the token.
/// Design: docs/design/pro-kyc.md.
class ApiProKycService implements ProKycServiceInterface {
  ApiProKycService({
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
  Future<ApiResponse<KycStatus>> getKycStatus(String providerUserId) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send(
      (t) => _client.get(_uri('/me/kyc'), headers: _bearer(t)),
    );
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(KycStatus.fromJson(_decode(res.body)));
  }

  @override
  Future<ApiResponse<String>> uploadDocument({
    required String source,
    required String contentType,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final List<int> bytes;
    try {
      bytes = await File(source).readAsBytes();
    } catch (_) {
      return ApiResponse.error('Fichier introuvable');
    }

    // 1. Presign a private, single-use upload to the KYC bucket.
    final signRes = await _authed.send((t) => _client.post(
          _uri('/uploads/sign'),
          headers: {..._bearer(t), 'Content-Type': 'application/json'},
          body: jsonEncode({'contentType': contentType, 'purpose': 'kyc'}),
        ));
    if (signRes == null) return _networkError();
    if (signRes.statusCode != 200) return _errorFrom(signRes);
    final ticket = _decode(signRes.body);
    final key = ticket['key'] as String;

    // 2. Upload the bytes straight to private storage (presign is the auth).
    final req =
        http.MultipartRequest('POST', Uri.parse(ticket['uploadUrl'] as String));
    (ticket['fields'] as Map).forEach((k, v) {
      req.fields[k as String] = v as String;
    });
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'doc'));
    try {
      final uploaded = await _client.send(req);
      await uploaded.stream.drain<void>();
      if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
        return ApiResponse.error('Échec de l’envoi du document');
      }
    } catch (_) {
      return ApiResponse.error('Échec de l’envoi du document');
    }
    return ApiResponse.success(key);
  }

  @override
  Future<ApiResponse<KycStatus>> submitKyc({
    required String providerUserId,
    required List<KycDocument> documents,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    final res = await _authed.send((t) => _client.post(
          _uri('/me/kyc'),
          headers: {..._bearer(t), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'documents': [
              for (final d in documents)
                {'type': d.type.name, 'fileName': d.fileName, 'key': d.key},
            ],
          }),
        ));
    if (res == null) return _networkError();
    if (res.statusCode != 200) return _errorFrom(res);
    return ApiResponse.success(
      KycStatus.fromJson(_decode(res.body)),
      message: 'Documents soumis pour vérification',
    );
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
