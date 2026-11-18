import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import 'net_settings.dart';
import 'platform_clients.dart';

export 'net_settings.dart';

/// The one HTTP transport of the app, shared by every call
/// (docs/design/android-http3-transport.md §4.1).
///
/// **Why it exists.** Since Flutter 3.47.8, `dart:io` offers a post-quantum
/// key share first, and its ClientHello no longer fits in one packet. On a
/// network whose MTU is 1,460 bytes (Orange CI fibre, read 2026-11-18), the
/// TLS handshake over TCP to our Cloudflare hostnames then dies after 15 s,
/// and the app says « Pas de connexion ». QUIC works there. So on Android the
/// app talks through Cronet, Chrome's network stack from Play Services, with
/// HTTP/3 hinted for our Cloudflare hosts ([CronetSettings]).
///
/// - **Android:** one Cronet engine, built on the first request — never in
///   `main()` before the binding exists, which froze release builds
///   (dart-lang/http#1241) — and never closed.
/// - **Android without a working Cronet** (no Play Services, a provider that
///   fails to load): `dart:io`, exactly the app before this change, and the
///   fallback is reported once ([whenSettled]).
/// - **Every other platform:** the platform's own client, unchanged.
///
/// Every service, the image cache and the map tiles get [client] explicitly;
/// `http.runWithClient` in each entry is only the backstop for a package that
/// builds its own `Client()`.
class AppHttpTransport {
  AppHttpTransport({
    required this.isAndroid,
    required this.apiBaseUrl,
    required this._buildCronet,
    required this._buildPlatformClient,
    required this._readUserAgent,
  });

  /// The process's transport. The OS decides, not `defaultTargetPlatform`:
  /// a widget test claims to be Android and has no Cronet to build.
  static final AppHttpTransport instance = AppHttpTransport(
    isAndroid: runsOnAndroid,
    apiBaseUrl: AppConfig.apiBaseUrl,
    buildCronet: buildCronetClient,
    buildPlatformClient: buildPlatformClient,
    readUserAgent: readAppUserAgent,
  );

  /// The shared client: what every `Api*Service`, the version gate, the image
  /// cache and the map tiles are given.
  static http.Client get client => instance.sharedClient;

  final bool isAndroid;
  final String apiBaseUrl;
  final CronetClientBuilder _buildCronet;
  final http.Client Function() _buildPlatformClient;
  final Future<String> Function() _readUserAgent;

  /// One client for the whole process, which nobody can close
  /// ([_SharedClient.close]).
  late final http.Client sharedClient = _SharedClient(this);

  Future<http.Client>? _resolving;
  NetTransportOutcome? _outcome;
  final List<void Function(NetTransportOutcome)> _listeners = [];

  /// What this process settled on; `null` before the first request.
  NetTransportOutcome? get outcome => _outcome;

  /// Calls [listener] once with the outcome: now if it is known, otherwise
  /// when the first request settles it. Error reporting registers here after
  /// Sentry starts, which is after the version gate's request may have gone.
  void whenSettled(void Function(NetTransportOutcome outcome) listener) {
    final known = _outcome;
    if (known != null) {
      _notify(listener, known);
    } else {
      _listeners.add(listener);
    }
  }

  Future<http.Client> _client() => _resolving ??= _resolve();

  Future<http.Client> _resolve() async {
    if (!isAndroid) {
      _settle(const NetTransportOutcome(NetTransport.dartio));
      return _buildPlatformClient();
    }
    final settings = CronetSettings(
      quicHosts: quicHintHosts(apiBaseUrl),
      userAgent: await _readUserAgent(),
    );
    try {
      final cronet = _buildCronet(settings);
      _settle(const NetTransportOutcome(NetTransport.cronet));
      return cronet;
    } on Object catch (error) {
      // Broad on purpose: without Play Services Cronet throws a Java
      // RuntimeException, rethrown as a JThrowable, and phones whose Cronet
      // module fails to load throw other things (spec §4.1). Whatever it is,
      // the app must still reach the network as it did before.
      _settle(
        NetTransportOutcome(
          NetTransport.dartio,
          fallbackReason: cronetFailureName(error),
        ),
      );
      return _buildPlatformClient();
    }
  }

  void _settle(NetTransportOutcome outcome) {
    _outcome = outcome;
    final waiting = List.of(_listeners);
    _listeners.clear();
    for (final listener in waiting) {
      _notify(listener, outcome);
    }
  }

  /// A listener that throws must not fail the request that settled the
  /// transport.
  static void _notify(
    void Function(NetTransportOutcome) listener,
    NetTransportOutcome outcome,
  ) {
    try {
      listener(outcome);
    } on Object catch (_) {}
  }
}

/// The client handed out. It resolves the transport on its first request and
/// forwards every request to it.
class _SharedClient extends http.BaseClient {
  _SharedClient(this._transport);

  final AppHttpTransport _transport;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      (await _transport._client()).send(request);

  /// Does nothing, deliberately. The whole process shares this client, and
  /// cronet_http refuses every request once its client is closed — so a
  /// package reached through `runWithClient` that closes « its » client would
  /// otherwise take the app's network down with it.
  @override
  void close() {}
}

/// [appUserAgent] from the installed package. Never throws: a user agent is
/// not worth a failed request.
Future<String> readAppUserAgent() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return appUserAgent(
      packageName: info.packageName,
      version: info.version,
      build: info.buildNumber,
    );
  } on Object catch (_) {
    return appUserAgent();
  }
}
