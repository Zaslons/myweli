import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../http/body_fields.dart';
import 'id_token_verifier.dart';

/// Sign in with Apple's refresh token — exchanged from the sign-in's
/// `authorizationCode`, kept per account and client, **revoked when the
/// account is deleted**, so a deleted account leaves « Apps using Apple ID »
/// (App Store 5.1.1(v)). B6.7, docs/design/backend-integrity-batch6.md §2.7
/// and §13; threat model T79.
///
/// Built **inactive** (Q5): with no key configured nothing is exchanged nor
/// revoked — a log line says so — and nothing breaks. The keys arrive as
/// secrets when the owner creates them (docs/DEPLOYMENT.md).
///
/// **One key per app** (docs/design/apple-signin-keys.md): MyWeli and MyWeli
/// Pro are separate Sign in with Apple primaries, and Apple associates a key
/// with ONE primary — so each token is exchanged and revoked with the key of
/// its own client ([AppleSignInKeys]).

const _appleTokenUrl = 'https://appleid.apple.com/auth/token';
const _appleRevokeUrl = 'https://appleid.apple.com/auth/revoke';

/// A Sign in with Apple key (`AuthKey_<id>.p8`) that signs the
/// `client_secret` Apple asks for on both endpoints.
class AppleSignInKey {
  AppleSignInKey({
    required this.teamId,
    required this.keyId,
    required this.privateKey,
  });

  /// The `.p8` as Apple gives it (PKCS#8; escaped `\n` accepted, as for the
  /// FCM key). A key that does not read → [StateError] naming [name] — never
  /// the value.
  factory AppleSignInKey.fromPem({
    required String teamId,
    required String keyId,
    required String pem,
    String name = 'The Sign in with Apple key',
  }) {
    final ECPrivateKey key;
    try {
      key = ECPrivateKey(pem.replaceAll(r'\n', '\n'));
    } catch (_) {
      throw StateError(
        '$name does not read as a PKCS#8 EC key (the .p8 file Apple '
        'Developer gives, as is).',
      );
    }
    return AppleSignInKey(teamId: teamId, keyId: keyId, privateKey: key);
  }

  final String teamId;
  final String keyId;
  final ECPrivateKey privateKey;

  /// The `client_secret`: an ES256 JWT for [clientId], five minutes of life
  /// (Apple allows six months; a secret minted per call never needs storing).
  String clientSecret(String clientId, {DateTime? now}) {
    final iat = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return JWT(
      {
        'iss': teamId,
        'iat': iat,
        'exp': iat + 300,
        'aud': 'https://appleid.apple.com',
        'sub': clientId,
      },
      header: {'kid': keyId},
      // `iat` is ours (the claim above): the library would stamp its own.
    ).sign(privateKey, algorithm: JWTAlgorithm.ES256, noIssueAt: true);
  }
}

/// The Sign in with Apple keys, one per app, each signing for the clients it
/// lists (docs/design/apple-signin-keys.md §4).
class AppleSignInKeys {
  const AppleSignInKeys._(this._byClient);

  /// The keys as a client → key map, unchecked — for tests and tools; a
  /// production boot goes through [fromEnv] and its rules.
  factory AppleSignInKeys.of(Map<String, AppleSignInKey> byClient) =>
      byClient.isEmpty ? none : AppleSignInKeys._(Map.of(byClient));

  /// No key: **inactive**.
  static const none = AppleSignInKeys._({});

  /// The two slots: `APP` (the MyWeli primary) and `PRO` (MyWeli Pro).
  static const slots = ['APP', 'PRO'];

  final Map<String, AppleSignInKey> _byClient;

  /// From `APPLE_TEAM_ID` and, per slot, `APPLE_<slot>_KEY_ID`,
  /// `APPLE_<slot>_PRIVATE_KEY` and `APPLE_<slot>_KEY_CLIENTS` (a comma list
  /// of the clients that key signs for). [clientIds] is `APPLE_CLIENT_IDS`,
  /// already verified.
  ///
  /// No slot → [none]. Otherwise every rule of §4 or a [StateError] at boot,
  /// naming the variable and never a value: a half-made configuration must
  /// not look like it works, and a client typed wrong would keep nothing.
  static AppleSignInKeys fromEnv(
    String? Function(String) env, {
    required List<String> clientIds,
  }) {
    for (final old in ['APPLE_KEY_ID', 'APPLE_PRIVATE_KEY']) {
      if (env(old) != null) {
        throw StateError(
          '$old is the old single-key name. Sign in with Apple has one key per '
          'app now: APPLE_APP_KEY_ID, APPLE_APP_PRIVATE_KEY, '
          'APPLE_APP_KEY_CLIENTS, and the same with APPLE_PRO_ '
          '(docs/design/apple-signin-keys.md §4).',
        );
      }
    }
    final byClient = <String, AppleSignInKey>{};
    for (final slot in slots) {
      final names = [
        'APPLE_${slot}_KEY_ID',
        'APPLE_${slot}_PRIVATE_KEY',
        'APPLE_${slot}_KEY_CLIENTS',
      ];
      final values = [for (final n in names) env(n)];
      final missing = [
        for (var i = 0; i < names.length; i++)
          if (values[i] == null) names[i],
      ];
      if (missing.length == names.length) continue;
      if (missing.isNotEmpty) {
        throw StateError(
          'Sign in with Apple key $slot needs all three of ${names.join(', ')} '
          '— or none. Missing: ${missing.join(', ')}.',
        );
      }
      final teamId = env('APPLE_TEAM_ID');
      if (teamId == null) {
        throw StateError(
          'Sign in with Apple key $slot is set but APPLE_TEAM_ID is not.',
        );
      }
      final key = AppleSignInKey.fromPem(
        teamId: teamId,
        keyId: values[0]!,
        pem: values[1]!,
        name: names[1],
      );
      final clients = [
        for (final c in values[2]!.split(','))
          if (c.trim().isNotEmpty) c.trim(),
      ];
      if (clients.isEmpty) {
        throw StateError('${names[2]} lists no client.');
      }
      for (final c in clients) {
        if (!clientIds.contains(c)) {
          throw StateError(
            '${names[2]} lists $c, which is not in APPLE_CLIENT_IDS — its '
            'sign-ins would never reach this key.',
          );
        }
        if (byClient.containsKey(c) && !identical(byClient[c], key)) {
          throw StateError(
            '$c is listed by two Sign in with Apple keys — a client belongs to '
            'one primary App ID, so to one key.',
          );
        }
        byClient[c] = key;
      }
    }
    return byClient.isEmpty ? none : AppleSignInKeys._(byClient);
  }

  /// Whether at least one key is configured.
  bool get isActive => _byClient.isNotEmpty;

  /// The key that signs for [clientId], or null.
  AppleSignInKey? forClient(String clientId) => _byClient[clientId];

  /// The [clientIds] no key signs for, in their order.
  List<String> uncovered(Iterable<String> clientIds) => [
    for (final c in clientIds)
      if (!_byClient.containsKey(c)) c,
  ];
}

/// What a production boot says about the keys, or null when every client has
/// one (docs/design/apple-signin-keys.md §4, rules 1 and 5) — said where an
/// operator reads, never silently « done ».
String? appleKeysNotice(AppleSignInKeys keys, Iterable<String> clientIds) {
  if (!keys.isActive) {
    return 'NOTICE: no Sign in with Apple key (APPLE_APP_* / APPLE_PRO_*) — '
        'Sign in with Apple tokens are neither kept nor revoked at account '
        'deletion (docs/design/apple-signin-keys.md).';
  }
  final missing = keys.uncovered(clientIds);
  if (missing.isEmpty) return null;
  return 'NOTICE: no Sign in with Apple key for ${missing.join(', ')} — '
      'those sign-ins keep no token, so their accounts\' deletions revoke '
      'nothing (docs/design/apple-signin-keys.md §4).';
}

/// A kept refresh token and the client (app bundle id or web Services ID) it
/// was issued to — revocation must name the same client.
typedef AppleToken = ({String clientId, String refreshToken});

/// One refresh token per (account kind, account, client). `kind` is `user`
/// (a client) or `provider` (a Pro account): the two identity tables have
/// separate id spaces. Erased by the two account-deletion paths.
abstract interface class AppleTokenRepository {
  /// Keep [refreshToken], replacing the one held for the same client.
  Future<void> keep({
    required String kind,
    required String accountId,
    required String clientId,
    required String refreshToken,
  });

  Future<List<AppleToken>> listFor({
    required String kind,
    required String accountId,
  });

  Future<void> deleteFor({required String kind, required String accountId});
}

class InMemoryAppleTokenRepository implements AppleTokenRepository {
  final Map<String, Map<String, String>> _byAccount = {};

  String _k(String kind, String accountId) => '$kind\u0000$accountId';

  @override
  Future<void> keep({
    required String kind,
    required String accountId,
    required String clientId,
    required String refreshToken,
  }) async {
    (_byAccount[_k(kind, accountId)] ??= {})[clientId] = refreshToken;
  }

  @override
  Future<List<AppleToken>> listFor({
    required String kind,
    required String accountId,
  }) async => [
    for (final e in (_byAccount[_k(kind, accountId)] ?? const {}).entries)
      (clientId: e.key, refreshToken: e.value),
  ];

  @override
  Future<void> deleteFor({
    required String kind,
    required String accountId,
  }) async {
    _byAccount.remove(_k(kind, accountId));
  }
}

/// The exchange at sign-in and the revocation at deletion. Neither ever
/// throws, and neither ever logs the code, a token or the secret.
class AppleTokenService {
  AppleTokenService(
    this._tokens,
    this._keys, {
    http.Client? client,
    void Function(String)? log,
    Duration timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _log = log ?? print,
       _timeout = timeout;

  final AppleTokenRepository _tokens;
  final AppleSignInKeys _keys;
  final http.Client _client;
  final void Function(String) _log;
  final Duration _timeout;

  /// Whether a key is configured (boot announces it once).
  bool get isActive => _keys.isActive;

  /// Exchange the sign-in's [code] for a refresh token and keep it.
  ///
  /// Called after a SUCCESSFUL sign-in only. [clientId] is the audience of
  /// the identity token already verified — a code is exchanged with the
  /// client Apple gave it to. Apple's answer carries an `id_token`: its `sub`
  /// must be [sub], the verified identity's, or nothing is kept (another
  /// person's code must never land under this account — its deletion would
  /// revoke THEIR authorization). [redirectUri] is the web's (Apple requires
  /// the one of the authorization); the app sends none.
  ///
  /// Bounded by the timeout and silent on failure: the sign-in is never
  /// Apple's to fail. Signed with [clientId]'s own key; a client no key signs
  /// for keeps nothing (logged — a client id is public, it is in every
  /// identity token).
  Future<void> keepFromCode({
    required String kind,
    required String accountId,
    required String clientId,
    required String sub,
    required String code,
    String? redirectUri,
  }) async {
    if (!_keys.isActive) {
      _log('apple_token SKIPPED kind=$kind account=$accountId cause=no_key');
      return;
    }
    final key = _keys.forClient(clientId);
    if (key == null) {
      _log(
        'apple_token SKIPPED kind=$kind account=$accountId client=$clientId '
        'cause=no_key_for_client',
      );
      return;
    }
    try {
      final res = await _client
          .post(
            Uri.parse(_appleTokenUrl),
            body: {
              'client_id': clientId,
              'client_secret': key.clientSecret(clientId),
              'code': code,
              'grant_type': 'authorization_code',
              'redirect_uri': ?redirectUri,
            },
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        // Apple's error word tells a key that does not cover the client
        // (`invalid_client`) from a code Apple refused (`invalid_grant`) —
        // the only test of a key there is (docs/design/apple-signin-keys.md
        // §9: no fake request discriminates).
        _log(
          'apple_token FAILED kind=$kind account=$accountId client=$clientId '
          'status=${res.statusCode} error=${appleErrorWord(res.body)}',
        );
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final refresh = body['refresh_token'];
      final idToken = body['id_token'];
      if (refresh is! String || refresh.isEmpty || idToken is! String) {
        _log('apple_token FAILED kind=$kind account=$accountId cause=no_token');
        return;
      }
      // Read, not verified: this answer came from Apple over TLS, to a
      // request signed with our key.
      final answeredSub = (JWT.decode(idToken).payload as Map)['sub'];
      if (answeredSub != sub) {
        _log(
          'apple_token FAILED kind=$kind account=$accountId cause=sub_mismatch',
        );
        return;
      }
      await _tokens.keep(
        kind: kind,
        accountId: accountId,
        clientId: clientId,
        refreshToken: refresh,
      );
    } catch (e) {
      _log(
        'apple_token FAILED kind=$kind account=$accountId '
        'cause=${e.runtimeType}',
      );
    }
  }

  /// Revoke every token kept for the account, each with its own client's key,
  /// then erase them — **in every case**: a secret held for nobody is worse
  /// than a missed revocation, and the deletion goes on whatever Apple
  /// answers (the person can still remove MyWeli in their Apple settings).
  /// Called by both deletion paths, just before the identity goes.
  Future<void> revokeAll({
    required String kind,
    required String accountId,
  }) async {
    final kept = await _tokens.listFor(kind: kind, accountId: accountId);
    if (kept.isEmpty) return;
    if (!_keys.isActive) {
      _log(
        'apple_revoke SKIPPED kind=$kind account=$accountId '
        'tokens=${kept.length} cause=no_key',
      );
    } else {
      for (final t in kept) {
        final key = _keys.forClient(t.clientId);
        if (key == null) {
          _log(
            'apple_revoke SKIPPED kind=$kind account=$accountId '
            'client=${t.clientId} cause=no_key_for_client',
          );
          continue;
        }
        try {
          final res = await _client
              .post(
                Uri.parse(_appleRevokeUrl),
                body: {
                  'client_id': t.clientId,
                  'client_secret': key.clientSecret(t.clientId),
                  'token': t.refreshToken,
                  'token_type_hint': 'refresh_token',
                },
              )
              .timeout(_timeout);
          if (res.statusCode != 200) {
            _log(
              'apple_revoke FAILED kind=$kind account=$accountId '
              'client=${t.clientId} status=${res.statusCode} '
              'error=${appleErrorWord(res.body)}',
            );
          }
        } catch (e) {
          _log(
            'apple_revoke FAILED kind=$kind account=$accountId '
            'client=${t.clientId} cause=${e.runtimeType}',
          );
        }
      }
    }
    await _tokens.deleteFor(kind: kind, accountId: accountId);
  }
}

/// Apple's error word in an error answer (`invalid_client`, `invalid_grant`…),
/// or `-`. Only a short lowercase word is ever returned: the rest of a body
/// (an `error_description`, anything unexpected) is never logged.
String appleErrorWord(String body) {
  try {
    final decoded = jsonDecode(body);
    final error = decoded is Map ? decoded['error'] : null;
    if (error is String && RegExp(r'^[a-z_]{1,40}$').hasMatch(error)) {
      return error;
    }
  } catch (_) {
    // Not JSON: no word.
  }
  return '-';
}

/// The optional `authorizationCode` of an Apple sign-in body, and the
/// `redirectUri` the web's BFF adds.
///
/// Read with the other fields, BEFORE the sign-in: a wrong JSON type is
/// `400 invalid_body` like every field ([BodyFieldTypeError]), and must never
/// turn a sign-in that succeeded into a 400. A value that is merely unusable
/// (empty, too long, a redirect that is not https) is dropped: the sign-in
/// is not this field's to fail.
typedef AppleCode = ({String? code, String? redirectUri});

AppleCode appleCodeOf(Map<String, dynamic> body) {
  final code = optionalString(body, 'authorizationCode')?.trim() ?? '';
  final redirect = optionalString(body, 'redirectUri')?.trim() ?? '';
  if (code.isEmpty || code.length > 2000) {
    return (code: null, redirectUri: null);
  }
  final ok = redirect.startsWith('https://') && redirect.length <= 300;
  return (code: code, redirectUri: ok ? redirect : null);
}

/// After a SUCCESSFUL Apple sign-in: hand [apple]'s code, if any (read by
/// [appleCodeOf] with the other fields), over to be exchanged and kept under
/// [kind]/[accountId]. The client is the audience of the identity token
/// [verifier] just accepted; [sub] is its verified subject. [tokens] is read
/// only when there is a code — a sign-in without one never touches it.
Future<void> keepAppleSignInCode({
  required AppleCode apple,
  required String identityToken,
  required AppleIdTokenVerifier verifier,
  required String sub,
  required String kind,
  required String accountId,
  required AppleTokenService Function() tokens,
}) async {
  final code = apple.code;
  if (code == null) return;
  final clientId = verifier.audienceOf(identityToken);
  if (clientId == null) return;
  await tokens().keepFromCode(
    kind: kind,
    accountId: accountId,
    clientId: clientId,
    sub: sub,
    code: code,
    redirectUri: apple.redirectUri,
  );
}
