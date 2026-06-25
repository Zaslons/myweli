import 'dart:convert';

import 'package:http/http.dart' as http;

import '../interfaces/session_store.dart';

/// Wraps authenticated HTTP calls with transparent **silent refresh**, so a
/// short-lived access token expiring mid-session is invisible to the user.
///
/// [send] reads the access token from the persisted session, runs the request,
/// and on a **401** exchanges the stored refresh token at [refreshPath] for a
/// fresh pair, rotates the stored session, and retries the request **once**.
///
/// Failure handling is deliberate:
/// - a **rejected** refresh (non-2xx — e.g. the refresh token was revoked by
///   reuse-detection) clears the session so the app falls back to sign-in;
/// - a **transport failure** during refresh leaves the session intact (a flaky
///   network must not log the user out) — the original 401 is surfaced.
///
/// It is store-shape-agnostic: it only touches the top-level `token` and
/// `refreshToken` keys of the persisted JSON, so the same client works for the
/// consumer [Session] and the provider session.
class RefreshingHttpClient {
  RefreshingHttpClient({
    required http.Client client,
    required String baseUrl,
    required SessionStore store,
    this.refreshPath = '/auth/refresh',
  })  : _client = client,
        _baseUrl = baseUrl,
        _store = store;

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _store;
  final String refreshPath;

  /// The current access token, or null when there is no stored session.
  Future<String?> accessToken() => _field('token');

  /// Runs [run] (which builds a request given a bearer token). On 401 it
  /// refreshes once and retries. Returns null on a transport failure or when
  /// not signed in; any non-401 response is returned as-is.
  Future<http.Response?> send(
    Future<http.Response> Function(String token) run,
  ) async {
    final token = await accessToken();
    if (token == null) return null;
    final first = await _guard(() => run(token));
    if (first == null || first.statusCode != 401) return first;

    final fresh = await _refresh();
    if (fresh == null) return first; // refresh failed → original 401 stands
    return _guard(() => run(fresh));
  }

  /// Merge [changes] into the stored session JSON without disturbing the
  /// (possibly just-rotated) tokens — used to persist profile edits.
  Future<void> mergeIntoSession(Map<String, dynamic> changes) async {
    final map = await _readMap();
    if (map == null) return;
    map.addAll(changes);
    await _store.save(jsonEncode(map));
  }

  Future<String?> _field(String key) async {
    final map = await _readMap();
    final value = map?[key];
    return value is String ? value : null;
  }

  Future<Map<String, dynamic>?> _readMap() async {
    final raw = await _store.read();
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Exchange the stored refresh token for a new pair and rotate the session.
  /// Returns the new access token, or null. Clears the session only when the
  /// refresh is genuinely dead (no token, malformed, or server rejection) — not
  /// on a transport failure, so a flaky network keeps the user signed in.
  Future<String?> _refresh() async {
    final map = await _readMap();
    if (map == null) {
      await _store.clear();
      return null;
    }
    final refreshToken = map['refreshToken'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      await _store.clear();
      return null;
    }
    final res = await _guard(() => _client.post(
          Uri.parse('$_baseUrl$refreshPath'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        ));
    if (res == null) return null; // transport failure → keep the session
    if (res.statusCode != 200) {
      await _store.clear(); // refresh rejected (revoked/expired) → end session
      return null;
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      await _store.clear();
      return null;
    }
    final newAccess = body['accessToken'];
    final newRefresh = body['refreshToken'];
    if (newAccess is! String || newRefresh is! String) {
      await _store.clear();
      return null;
    }
    map['token'] = newAccess;
    map['refreshToken'] = newRefresh;
    await _store.save(jsonEncode(map));
    return newAccess;
  }

  Future<http.Response?> _guard(Future<http.Response> Function() run) async {
    try {
      return await run();
    } catch (_) {
      return null;
    }
  }
}
