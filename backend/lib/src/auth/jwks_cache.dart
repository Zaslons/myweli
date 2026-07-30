import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pointycastle/asymmetric/api.dart' as pc;

/// Fetches and caches a JWKS (JSON Web Key Set) endpoint, exposing RSA public
/// keys by `kid` — the trust anchor for Google/Apple ID-token verification.
/// The set is cached per the endpoint's `Cache-Control: max-age` (default
/// [defaultTtl]); an unknown `kid` triggers a refetch (key rotation), throttled
/// by [minRefetchInterval] so a flood of bad tokens can't hammer the endpoint.
/// Design: docs/design/auth-social-email.md §7.
class JwksCache {
  JwksCache(
    this.url, {
    http.Client? client,
    this.defaultTtl = const Duration(hours: 1),
    this.minRefetchInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final String url;
  final Duration defaultTtl;
  final Duration minRefetchInterval;
  final http.Client _client;
  final DateTime Function() _clock;

  Map<String, pc.RSAPublicKey> _keys = {};
  DateTime? _fetchedAt;
  DateTime? _expiresAt;

  /// The RSA public key for [kid], or null when the JWKS doesn't contain it
  /// (even after a refetch) or the endpoint is unreachable.
  Future<pc.RSAPublicKey?> keyFor(String kid) async {
    final now = _clock().toUtc();
    final fresh =
        _expiresAt != null && now.isBefore(_expiresAt!) && _keys.isNotEmpty;
    if (fresh && _keys.containsKey(kid)) return _keys[kid];

    // Stale, empty, or unknown kid → refetch (throttled).
    final canRefetch =
        _fetchedAt == null || now.difference(_fetchedAt!) >= minRefetchInterval;
    if (!fresh || (canRefetch && !_keys.containsKey(kid))) {
      if (canRefetch) await _fetch(now);
    }
    return _keys[kid];
  }

  Future<void> _fetch(DateTime now) async {
    _fetchedAt = now;
    try {
      final res = await _client.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final keys = <String, pc.RSAPublicKey>{};
      for (final k in (body['keys'] as List? ?? const [])) {
        final jwk = k as Map<String, dynamic>;
        if (jwk['kty'] != 'RSA') continue;
        final kid = jwk['kid'] as String?;
        final n = jwk['n'] as String?;
        final e = jwk['e'] as String?;
        if (kid == null || n == null || e == null) continue;
        keys[kid] = pc.RSAPublicKey(_bigIntB64(n), _bigIntB64(e));
      }
      if (keys.isNotEmpty) {
        _keys = keys;
        _expiresAt = now.add(_ttlFrom(res.headers['cache-control']));
      }
    } catch (_) {
      // Unreachable endpoint → keep whatever we had; verification will fail
      // closed (no key → token rejected).
    }
  }

  Duration _ttlFrom(String? cacheControl) {
    final m = RegExp(r'max-age=(\d+)').firstMatch(cacheControl ?? '')?.group(1);
    return m == null ? defaultTtl : Duration(seconds: int.parse(m));
  }

  static BigInt _bigIntB64(String base64url) {
    final bytes = base64Url.decode(base64Url.normalize(base64url));
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }
}
