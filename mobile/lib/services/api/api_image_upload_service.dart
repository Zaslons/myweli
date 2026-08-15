import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../models/api_response.dart';
import '../interfaces/image_upload_service_interface.dart';
import '../interfaces/session_store.dart';
import 'refreshing_http_client.dart';

/// Compresses [source] (a local file path) to JPEG bytes for upload. Injected
/// so the network flow is testable without the native compressor.
typedef ImageCompressor = Future<Uint8List?> Function(String source);

/// Real image upload: **compress on-device → presigned direct-to-storage
/// upload** (design: docs/design/pro-image-upload-pipeline.md). Bytes never go
/// through our API — the app asks `POST /uploads/sign` (provider-authenticated,
/// with silent refresh) for a short-lived presigned **multipart POST**, then
/// uploads straight to object storage (Cloudflare R2) and returns the public
/// CDN URL the caller saves to the gallery.
class ApiImageUploadService implements ImageUploadServiceInterface {
  ApiImageUploadService({
    http.Client? client,
    String? baseUrl,
    // **Named `providerSessionStore` until it wasn't one.** This pipeline is
    // shared by pro AND consumer uploads, and the old name made a registration
    // that handed it the PRO store read as obviously correct — which is how the
    // consumer avatar ended up signing against a store its binary never fills.
    // The store, the purpose and the refresh path are one decision; the name
    // now says so.
    SessionStore? sessionStore,
    ImageCompressor? compressor,
    // The defaults keep the pro gallery. Consumer purposes (`review`, `avatar`)
    // MUST pass all three: a consumer session, their purpose, and
    // `/auth/refresh` — the server role-gates per purpose, so a half-configured
    // instance is a 403 at best and a foreign prefix at worst.
    this._purpose = 'gallery',
    String refreshPath = '/auth/provider/refresh',
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
       _compress = compressor ?? _defaultCompress,
       _sessionStore = sessionStore ?? InMemorySessionStore() {
    _authed = RefreshingHttpClient(
      client: _client,
      baseUrl: _baseUrl,
      store: _sessionStore,
      refreshPath: refreshPath,
    );
  }

  final http.Client _client;
  final String _baseUrl;
  final ImageCompressor _compress;
  final String _purpose;
  final SessionStore _sessionStore;
  late final RefreshingHttpClient _authed;

  /// R6: gallery uploads follow the switched-to salon (`?salonId=` on the
  /// sign call; keys scope server-side, T55). Other purposes stay
  /// account/user-scoped.
  Future<Uri> _signUri() async {
    final base = Uri.parse('$_baseUrl/uploads/sign');
    if (_purpose != 'gallery') return base;
    final raw = await _sessionStore.read();
    if (raw == null) return base;
    try {
      final selected =
          (jsonDecode(raw) as Map<String, dynamic>)['selectedSalonId']
              as String?;
      if (selected == null || selected.isEmpty) return base;
      return base.replace(queryParameters: {'salonId': selected});
    } catch (_) {
      return base;
    }
  }

  static Future<Uint8List?> _defaultCompress(String source) =>
      FlutterImageCompress.compressWithFile(
        source,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
        format: CompressFormat.jpeg,
      );

  @override
  Future<ApiResponse<String>> uploadImage({
    required String source,
    void Function(double progress)? onProgress,
  }) async {
    if (await _authed.accessToken() == null) {
      return ApiResponse.error('Non connecté');
    }
    onProgress?.call(0.1);

    final Uint8List? bytes;
    try {
      bytes = await _compress(source);
    } catch (_) {
      return ApiResponse.error('Image invalide');
    }
    if (bytes == null || bytes.isEmpty) {
      return ApiResponse.error('Image invalide');
    }

    // 1. Ask the backend to presign a direct-to-storage upload.
    final signRes = await _authed.send(
      (t) async => _client.post(
        await _signUri(),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'contentType': 'image/jpeg', 'purpose': _purpose}),
      ),
    );
    if (signRes == null) {
      return ApiResponse.error('Pas de connexion. Réessayez.');
    }
    if (signRes.statusCode != 200) {
      return _errorFrom(signRes);
    }
    final ticket = jsonDecode(signRes.body) as Map<String, dynamic>;
    onProgress?.call(0.4);

    // 2. PUT the bytes straight to storage (the presign is the auth — no
    //    bearer here). Cloudflare R2 does not implement presigned POST and
    //    answers one with 501 NotImplemented, so this is a PUT of the raw
    //    body. The signature covers `headers` — sending a different
    //    content-type than the one signed is a 403 from storage, so send
    //    exactly these and nothing else.
    //    docs/design/backend-r2-presigned-put.md.
    final http.Response uploaded;
    try {
      uploaded = await _client.put(
        Uri.parse(ticket['uploadUrl'] as String),
        headers: (ticket['headers'] as Map).map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        body: bytes,
      );
    } catch (_) {
      return ApiResponse.error('Échec de l’envoi. Réessayez.');
    }
    onProgress?.call(0.9);
    if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
      return ApiResponse.error('Échec de l’envoi. Réessayez.');
    }

    onProgress?.call(1.0);
    return ApiResponse.success(ticket['publicUrl'] as String);
  }

  ApiResponse<String> _errorFrom(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return ApiResponse.error(
        body['message'] as String? ?? 'Échec de l’envoi',
        code: body['error'] as String?,
      );
    } catch (_) {
      return ApiResponse.error('Échec de l’envoi');
    }
  }
}
