import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../net/app_http_transport.dart';

/// CacheManager that enforces an HTTP timeout so downloads don't hang forever.
class TimeoutCacheManager extends CacheManager {
  TimeoutCacheManager({
    required String cacheKey,
    required Duration requestTimeout,
    required http.Client client,
    Duration stalePeriod = const Duration(days: 7),
    int maxNrOfCacheObjects = 200,
  }) : super(
         Config(
           cacheKey,
           stalePeriod: stalePeriod,
           maxNrOfCacheObjects: maxNrOfCacheObjects,
           fileService: _TimeoutHttpFileService(requestTimeout, client),
         ),
       );

  static final TimeoutCacheManager images = TimeoutCacheManager(
    cacheKey: 'myweliImageCache',
    requestTimeout: const Duration(seconds: 12),
    // Every photo in the app, through the app's one transport
    // (docs/design/android-http3-transport.md §4.1).
    client: AppHttpTransport.client,
  );
}

class _TimeoutHttpFileService extends FileService {
  _TimeoutHttpFileService(this._timeout, this._client);

  final Duration _timeout;
  final http.Client _client;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final req = http.Request('GET', uri);
    if (headers != null) {
      req.headers.addAll(headers);
    }

    final streamed = await _client.send(req).timeout(_timeout);
    return _StreamedResponseFileServiceResponse(streamed);
  }
}

class _StreamedResponseFileServiceResponse implements FileServiceResponse {
  _StreamedResponseFileServiceResponse(this._response);

  final http.StreamedResponse _response;

  @override
  int get statusCode => _response.statusCode;

  @override
  Stream<List<int>> get content => _response.stream;

  @override
  int? get contentLength => _response.contentLength;

  @override
  DateTime get validTill {
    // Use Cache-Control max-age if present; otherwise default to 7 days.
    final cacheControl = _response.headers['cache-control'];
    if (cacheControl != null) {
      final parts = cacheControl.split(',');
      for (final p in parts) {
        final s = p.trim();
        if (s.startsWith('max-age=')) {
          final v = int.tryParse(s.substring('max-age='.length));
          if (v != null) return DateTime.now().add(Duration(seconds: v));
        }
      }
    }
    return DateTime.now().add(const Duration(days: 7));
  }

  @override
  String? get eTag => _response.headers['etag'];

  @override
  String get fileExtension => '';
}
