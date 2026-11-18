import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// The transport's settings and names, free of any platform code, so the unit
// tests and every platform file can share them
// (docs/design/android-http3-transport.md §4.1, §4.2, §4.7).

/// Which stack carries the app's HTTP.
enum NetTransport { cronet, dartio }

/// What the transport settled on, once per process.
@immutable
class NetTransportOutcome {
  const NetTransportOutcome(this.transport, {this.fallbackReason});

  final NetTransport transport;

  /// What made Cronet fail on Android — a Java class name or a Dart error
  /// type, never a message, a URL or anything about the user. `null` when
  /// there was no fallback.
  final String? fallbackReason;

  bool get isFallback => fallbackReason != null;
}

/// The Cronet engine's settings, as data, so a test can read them. Everything
/// else about the engine is fixed in `platform_clients_io.dart`: HTTP/3 on,
/// no cache and no storage, the system's DNS resolver.
@immutable
class CronetSettings {
  const CronetSettings({required this.quicHosts, required this.userAgent});

  /// The hosts told up front that they speak QUIC on port 443.
  final List<String> quicHosts;
  final String userAgent;
}

typedef CronetClientBuilder = http.Client Function(CronetSettings settings);

/// The photos' host — Cloudflare, answering HTTP/3 when hinted (spec R4).
const String kCdnHost = 'cdn.myweli.com';

/// The hosts hinted for QUIC: the API this build talks to — so a staging build
/// hints its own — and the CDN. Only HTTPS hosts: QUIC is never plain text.
/// Hosts off Cloudflare (CARTO, Google, Sentry) are not hinted, and use TCP
/// through Cronet (spec §4.2).
List<String> quicHintHosts(String apiBaseUrl) {
  final api = Uri.tryParse(apiBaseUrl);
  return {
    if (api != null && api.scheme == 'https' && api.host.isNotEmpty) api.host,
    kCdnHost,
  }.toList();
}

/// The user agent Cronet sends: the app and its version, nothing about the
/// phone. Cronet's own default names the device model and the locale.
String appUserAgent({String? packageName, String? version, String? build}) {
  if (packageName == null || packageName.isEmpty || version == null) {
    return 'MyWeli (Android)';
  }
  final number = (build == null || build.isEmpty) ? version : '$version+$build';
  return 'MyWeli/$number ($packageName; Android)';
}

/// A stable name for what made Cronet fail, for the `net.fallback` tag.
///
/// The Java exception's class when there is one (a JThrowable's text starts
/// with it), else the Dart error's kind. Never the message: it is not ours to
/// send. And never `runtimeType`, which `--obfuscate` turns into noise.
String cronetFailureName(Object error) {
  final java = RegExp(
    r'((?:[a-z][A-Za-z0-9_$]*\.)+[A-Z][A-Za-z0-9_$]*(?:Exception|Error))',
  ).firstMatch(error.toString());
  if (java != null) return java.group(1)!;
  return switch (error) {
    ArgumentError() => 'ArgumentError',
    UnsupportedError() => 'UnsupportedError',
    StateError() => 'StateError',
    _ => 'unknown',
  };
}
