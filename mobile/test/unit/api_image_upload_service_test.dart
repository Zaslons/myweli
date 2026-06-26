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
  store.save(jsonEncode({
    'token': 'tok',
    'refreshToken': refresh,
    'provider': {'id': 'p1'},
  }));
  return ApiImageUploadService(
    client: client,
    baseUrl: 'http://x',
    providerSessionStore: store,
    compressor: (_) async => bytes ?? Uint8List.fromList([1, 2, 3, 4]),
  );
}

void main() {
  test('signs, uploads to storage, returns the public URL', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path == '/uploads/sign') {
        expect(req.headers['Authorization'], 'Bearer tok');
        expect((jsonDecode(req.body) as Map)['contentType'], 'image/jpeg');
        return http.Response(
          jsonEncode({
            'method': 'POST',
            'uploadUrl': 'http://storage.local/bucket',
            'fields': {
              'key': 'gallery/p1/abc.jpg',
              'Content-Type': 'image/jpeg'
            },
            'publicUrl': 'https://cdn/gallery/p1/abc.jpg',
            'maxBytes': 5242880,
            'expiresInSeconds': 300,
          }),
          200,
        );
      }
      // The storage upload: multipart POST, no bearer (the presign is the auth).
      expect(req.headers['content-type'], contains('multipart/form-data'));
      expect(req.body, contains('gallery/p1/abc.jpg'));
      return http.Response('', 204);
    });

    final progress = <double>[];
    final res = await _service(client).uploadImage(
      source: '/tmp/photo.jpg',
      onProgress: progress.add,
    );

    expect(res.success, isTrue);
    expect(res.data, 'https://cdn/gallery/p1/abc.jpg');
    expect(paths, ['/uploads/sign', '/bucket']);
    expect(progress.last, 1.0);
  });

  test('no provider session → fails fast without HTTP', () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final service = ApiImageUploadService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: InMemorySessionStore(),
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
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final res = await _service(client, bytes: Uint8List(0))
        .uploadImage(source: '/tmp/x.jpg');
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
            'method': 'POST',
            'uploadUrl': 'http://storage.local/bucket',
            'fields': {'key': 'gallery/p1/abc.jpg'},
            'publicUrl': 'https://cdn/gallery/p1/abc.jpg',
            'maxBytes': 1,
            'expiresInSeconds': 300,
          }),
          200,
        );
      }
      return http.Response('', 204);
    });

    final res = await _service(client).uploadImage(source: '/tmp/x.jpg');
    expect(res.success, isTrue);
    expect(refreshed, isTrue);
  });
}
