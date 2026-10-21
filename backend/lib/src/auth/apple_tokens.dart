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
/// revoked — a log line says so — and nothing breaks. The key arrives as a
/// secret when the owner creates it (docs/DEPLOYMENT.md).

const _appleTokenUrl = 'https://appleid.apple.com/auth/token';
const _appleRevokeUrl = 'https://appleid.apple.com/auth/revoke';

/// The Sign in with Apple key (`AuthKey_<id>.p8`) that signs the
/// `client_secret` Apple asks for on both endpoints.
class AppleSignInKey {
  AppleSignInKey({
    required this.teamId,
    required this.keyId,
    required this.privateKey,
  });

  final String teamId;
  final String keyId;
  final ECPrivateKey privateKey;

  /// From `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the `.p8`
  /// as Apple gives it, PKCS#8; escaped `\n` accepted, as for the FCM key).
  ///
  /// None of the three → null: **inactive**. Some but not all, or a key that
  /// does not read → [StateError] at boot: a half-made configuration must not
  /// look like it works.
  static AppleSignInKey? fromEnv(String? Function(String) env) {
    final teamId = env('APPLE_TEAM_ID');
    final keyId = env('APPLE_KEY_ID');
    final pem = env('APPLE_PRIVATE_KEY')?.replaceAll(r'\n', '\n');
    final given = [teamId, keyId, pem].where((v) => v != null).length;
    if (given == 0) return null;
    if (given < 3) {
      throw StateError(
        'Sign in with Apple token revocation needs all three of APPLE_TEAM_ID, '
        'APPLE_KEY_ID and APPLE_PRIVATE_KEY — or none (inactive). Only $given '
        'set.',
      );
    }
    final ECPrivateKey key;
    try {
      key = ECPrivateKey(pem!);
    } catch (_) {
      throw StateError(
        'APPLE_PRIVATE_KEY does not read as a PKCS#8 EC key (the .p8 file '
        'Apple Developer gives, as is).',
      );
    }
    return AppleSignInKey(teamId: teamId!, keyId: keyId!, privateKey: key);
  }

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
    this._key, {
    http.Client? client,
    void Function(String)? log,
    Duration timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _log = log ?? print,
       _timeout = timeout;

  final AppleTokenRepository _tokens;
  final AppleSignInKey? _key;
  final http.Client _client;
  final void Function(String) _log;
  final Duration _timeout;

  /// Whether a key is configured (boot announces it once).
  bool get isActive => _key != null;

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
  /// Apple's to fail.
  Future<void> keepFromCode({
    required String kind,
    required String accountId,
    required String clientId,
    required String sub,
    required String code,
    String? redirectUri,
  }) async {
    final key = _key;
    if (key == null) {
      _log('apple_token SKIPPED kind=$kind account=$accountId cause=no_key');
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
        _log(
          'apple_token FAILED kind=$kind account=$accountId '
          'status=${res.statusCode}',
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

  /// Revoke every token kept for the account, then erase them — **in every
  /// case**: a secret held for nobody is worse than a missed revocation, and
  /// the deletion goes on whatever Apple answers (the person can still
  /// remove MyWeli in their Apple settings). Called by both deletion paths,
  /// just before the identity goes.
  Future<void> revokeAll({
    required String kind,
    required String accountId,
  }) async {
    final kept = await _tokens.listFor(kind: kind, accountId: accountId);
    if (kept.isEmpty) return;
    final key = _key;
    if (key == null) {
      _log(
        'apple_revoke SKIPPED kind=$kind account=$accountId '
        'tokens=${kept.length} cause=no_key',
      );
    } else {
      for (final t in kept) {
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
              'client=${t.clientId} status=${res.statusCode}',
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
