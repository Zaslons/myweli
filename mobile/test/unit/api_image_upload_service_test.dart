import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_image_upload_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// A provider-session-backed uploader with a stub compressor (so no native
/// image codec runs in tests).
ApiImageUploadService _service(
  MockClient client, {
  Uint8List? bytes,
  String? refresh = 'r1',
}) {
  final store = InMemorySessionStore();
  store.save(
    jsonEncode({
      'token': 'tok',
      'refreshToken': refresh,
      'provider': {'id': 'p1'},
    }),
  );
  return ApiImageUploadService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
    compressor: (_) async => bytes ?? Uint8List.fromList([1, 2, 3, 4]),
  );
}

/// The CONSUMER avatar instance, configured exactly as the composition root
/// configures it: a consumer session store, `purpose: 'avatar'`, and the
/// consumer refresh path. All three are one decision — a half-configured
/// instance is a 403 at best and a foreign object prefix at worst.
ApiImageUploadService _avatarService(MockClient client) {
  final store = InMemorySessionStore();
  store.save(
    jsonEncode({
      'token': 'utok',
      'refreshToken': 'ur1',
      'user': {'id': 'u1'},
    }),
  );
  return ApiImageUploadService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
    purpose: 'avatar',
    refreshPath: '/auth/refresh',
    compressor: (_) async => Uint8List.fromList([1, 2, 3, 4]),
  );
}

/// The salon LOGO instance: provider session + `purpose: 'logo'` — and,
/// unlike the avatar, SALON-SCOPED: the sign must carry `?salonId=` when the
/// pro has switched salons, or a multi-salon owner's logo lands on their
/// default salon (salon-logo.md; the R6 arm in `_signUri`).
ApiImageUploadService _logoService(MockClient client) {
  final store = InMemorySessionStore();
  store.save(
    jsonEncode({
      'token': 'tok',
      'refreshToken': 'r1',
      'provider': {'id': 'p1'},
      'selectedSalonId': 'provider2',
    }),
  );
  return ApiImageUploadService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
    purpose: 'logo',
    compressor: (_) async => Uint8List.fromList([1, 2, 3, 4]),
  );
}

void main() {
  group('the salon logo instance', () {
    test('signs purpose=logo WITH the selected salonId', () async {
      Uri? signUri;
      Map<String, dynamic>? signBody;
      final client = MockClient((req) async {
        if (req.url.path == '/uploads/sign') {
          signUri = req.url;
          signBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'method': 'PUT',
              'uploadUrl': 'http://storage.local/bucket',
              'headers': {'content-type': 'image/jpeg'},
              'publicUrl': 'https://cdn/pending/logo/provider2/abc.jpg',
              'maxBytes': 5242880,
              'expiresInSeconds': 300,
            }),
            200,
          );
        }
        return http.Response('', 200);
      });

      final res = await _logoService(
        client,
      ).uploadImage(source: '/tmp/logo.png');
      expect(res.success, isTrue);
      expect(signBody!['purpose'], 'logo');
      expect(
        signUri!.queryParameters['salonId'],
        'provider2',
        reason:
            'the logo is salon-scoped under R6 — without the arm in _signUri '
            'a switched-to salon would get its logo on the default one',
      );
    });
  });

  group('the consumer avatar instance', () {
    test('signs purpose=avatar with the CONSUMER token, no salonId', () async {
      // Every part of this failed before: AuthProvider resolved the PRO
      // instance, so the purpose was `gallery` (a 403 for a consumer token),
      // the token came from a store the consumer binary never fills, and the
      // gallery branch appends `?salonId=`.
      Uri? signUri;
      Map<String, dynamic>? signBody;
      final client = MockClient((req) async {
        if (req.url.path == '/uploads/sign') {
          signUri = req.url;
          signBody = jsonDecode(req.body) as Map<String, dynamic>;
          expect(req.headers['Authorization'], 'Bearer utok');
          return http.Response(
            jsonEncode({
              'method': 'PUT',
              'uploadUrl': 'http://storage.local/bucket',
              'headers': {'content-type': 'image/jpeg'},
              'publicUrl': 'https://cdn/pending/avatar/u1/abc.jpg',
              'maxBytes': 5242880,
              'expiresInSeconds': 300,
            }),
            200,
          );
        }
        return http.Response('', 200);
      });

      final res = await _avatarService(
        client,
      ).uploadImage(source: '/tmp/face.jpg');
      expect(res.success, isTrue);
      expect(res.data, 'https://cdn/pending/avatar/u1/abc.jpg');
      expect(signBody!['purpose'], 'avatar');
      expect(
        signUri!.queryParameters.containsKey('salonId'),
        isFalse,
        reason: 'salon scoping is a GALLERY concern; an avatar has no salon',
      );
    });

    test('a 401 refreshes at /auth/refresh, NOT the provider path', () async {
      // The refresh path is the other half of "which session is this". Pointed
      // at /auth/provider/refresh, a consumer refresh token is simply rejected
      // and the upload dies on a retry that could never work.
      final hit = <String>[];
      var signed = false;
      final client = MockClient((req) async {
        hit.add(req.url.path);
        if (req.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode({
              'accessToken': 'utok2',
              'refreshToken': 'ur2',
              'expiresAt': DateTime(2030).toIso8601String(),
            }),
            200,
          );
        }
        if (req.url.path == '/uploads/sign') {
          if (!signed) {
            signed = true;
            return http.Response('{}', 401);
          }
          expect(req.headers['Authorization'], 'Bearer utok2');
          return http.Response(
            jsonEncode({
              'method': 'PUT',
              'uploadUrl': 'http://storage.local/bucket',
              'headers': {'content-type': 'image/jpeg'},
              'publicUrl': 'https://cdn/pending/avatar/u1/abc.jpg',
              'maxBytes': 5242880,
              'expiresInSeconds': 300,
            }),
            200,
          );
        }
        return http.Response('', 200);
      });

      final res = await _avatarService(
        client,
      ).uploadImage(source: '/tmp/face.jpg');
      expect(res.success, isTrue);
      expect(hit, contains('/auth/refresh'));
      expect(hit, isNot(contains('/auth/provider/refresh')));
    });
  });

  test('signs, uploads to storage, returns the public URL', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path == '/uploads/sign') {
        expect(req.headers['Authorization'], 'Bearer tok');
        expect((jsonDecode(req.body) as Map)['contentType'], 'image/jpeg');
        return http.Response(
          jsonEncode({
            'method': 'PUT',
            'uploadUrl': 'http://storage.local/bucket',
            'headers': {'content-type': 'image/jpeg'},
            'publicUrl': 'https://cdn/gallery/p1/abc.jpg',
            'maxBytes': 5242880,
            'expiresInSeconds': 300,
          }),
          200,
        );
      }
      // The storage upload: a raw PUT, no bearer (the presign is the auth).
      // R2 answers a multipart POST with 501, so the body must be the bytes
      // themselves and the content-type exactly the one that was signed.
      expect(req.method, 'PUT');
      expect(req.headers['content-type'], 'image/jpeg');
      expect(req.headers.containsKey('authorization'), isFalse);
      return http.Response('', 200);
    });

    final progress = <double>[];
    final res = await _service(
      client,
    ).uploadImage(source: '/tmp/photo.jpg', onProgress: progress.add);

    expect(res.success, isTrue);
    expect(res.data, 'https://cdn/gallery/p1/abc.jpg');
    expect(paths, ['/uploads/sign', '/bucket']);
    expect(progress.last, 1.0);
  });

  test('no provider session → fails fast without HTTP', () async {
    final client = MockClient(
      (req) async => throw Exception('should not be called'),
    );
    final service = ApiImageUploadService(
      client: client,
      baseUrl: 'http://x',
      sessionStore: InMemorySessionStore(),
      compressor: (_) async => Uint8List.fromList([1]),
    );
    final res = await service.uploadImage(source: '/tmp/x.jpg');
    expect(res.success, isFalse);
  });

  test('a sign error surfaces its code', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/uploads/sign') {
        return http.Response(jsonEncode({'error': 'forbidden'}), 403);
      }
      throw Exception('should not reach storage');
    });
    final res = await _service(client).uploadImage(source: '/tmp/x.jpg');
    expect(res.success, isFalse);
    expect(res.code, 'forbidden');
  });

  test('an empty/failed compression is rejected before any HTTP', () async {
    final client = MockClient(
      (req) async => throw Exception('should not be called'),
    );
    final res = await _service(
      client,
      bytes: Uint8List(0),
    ).uploadImage(source: '/tmp/x.jpg');
    expect(res.success, isFalse);
  });

  test('a 401 on sign triggers provider silent refresh + retry', () async {
    var refreshed = false;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/provider/refresh') {
        refreshed = true;
        return http.Response(
          jsonEncode({
            'accessToken': 'tok2',
            'refreshToken': 'r2',
            'expiresAt': DateTime(2030).toIso8601String(),
          }),
          200,
        );
      }
      if (req.url.path == '/uploads/sign') {
        final auth = req.headers['Authorization'];
        if (auth != 'Bearer tok2') {
          return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
        }
        return http.Response(
          jsonEncode({
            'method': 'PUT',
            'uploadUrl': 'http://storage.local/bucket',
            'headers': {'content-type': 'image/jpeg'},
            'publicUrl': 'https://cdn/gallery/p1/abc.jpg',
            'maxBytes': 1,
            'expiresInSeconds': 300,
          }),
          200,
        );
      }
      return http.Response('', 200);
    });

    final res = await _service(client).uploadImage(source: '/tmp/x.jpg');
    expect(res.success, isTrue);
    expect(refreshed, isTrue);
  });
}
