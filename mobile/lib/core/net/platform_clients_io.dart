import 'dart:io' show Platform;

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'net_settings.dart';

/// The real OS. `defaultTargetPlatform` says Android in every widget test.
bool get runsOnAndroid => Platform.isAndroid;

/// `dart:io`'s client — the app before this change, and Android's fallback.
///
/// Built directly, never through `http.Client()`: inside `runWithClient`,
/// `http.Client()` returns the shared client itself, which would then wait
/// on itself.
http.Client buildPlatformClient() => IOClient();

/// The Cronet client of docs/design/android-http3-transport.md §4.1. Throws
/// when there is no Cronet to build (no Play Services, a provider that fails
/// to load); the transport catches it and falls back.
///
/// Each setting is held by `test/infra/android_http_transport_guard_test.dart`:
/// - HTTP/3 on, with a hint for each Cloudflare host on port 443;
/// - no cache and no storage path: the app has its own image cache, and a disk
///   cache would keep copies of API answers that hold personal data;
/// - the system's DNS resolver, which honours Android's Private DNS — Cronet's
///   own fails on some cellular networks (cronet_http 1.10.0's changelog);
/// - the engine is never closed: one per process, shared.
http.Client buildCronetClient(CronetSettings settings) {
  final engine = CronetEngine.build(
    enableQuic: true,
    quicHints: [for (final host in settings.quicHosts) (host, 443, 443)],
    cacheMode: CacheMode.disabled,
    useBuiltInDnsResolver: false,
    userAgent: settings.userAgent,
  );
  return CronetClient.fromCronetEngine(engine, closeEngine: false);
}
