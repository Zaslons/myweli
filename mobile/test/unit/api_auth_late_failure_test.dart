import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// A failure AFTER the server said yes still reaches the sign-in's own catch.
///
/// The four social doors end their `try` with `return _loginFrom(res)` or
/// `return _providerLoginResultFrom(res)`. Both are `async`, and both can throw
/// once the server has answered: a 200 whose body is not what the contract
/// says, or the keychain refusing the session in `_persistSession`. Returned
/// without `await`, that Future leaves the `try` before it fails, so the bare
/// `catch (_)` written for exactly these failures — the one that reports
/// `non_plugin_error` and says « Connexion … impossible. » — never sees it, and
/// the sign-in throws instead of answering.
///
/// Dart 3.13 names it (`unawaited_return_in_try_block`, a warning under
/// `--fatal-warnings`); docs/design/mobile-flutter-3.47-upgrade.md §6 step 5.
void main() {
  /// The contract's two shapes (docs/api/openapi.yaml): the client doors
  /// answer `{tokens, user}`, the Pro doors `{provider, accessToken, …}`.
  Map<String, dynamic> clientOk() => {
    'tokens': {
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
      'expiresAt': DateTime(2027).toIso8601String(),
    },
    'user': {
      'id': 'user_1',
      'phoneNumber': '+2250700000000',
      'name': null,
      'email': null,
      'avatarUrl': null,
      'createdAt': DateTime(2026).toIso8601String(),
    },
  };
  Map<String, dynamic> proOk() => {
    'provider': {
      'id': 'p1',
      'phoneNumber': '+2250700000000',
      'businessName': 'Chez Awa',
      'businessType': 'salon',
      'email': null,
      'verificationStatus': 'pending',
      'kycDocs': const <Map<String, dynamic>>[],
      'createdAt': DateTime(2026).toIso8601String(),
      'providerId': 'p1',
    },
    'accessToken': 'access-1',
    'refreshToken': 'refresh-1',
    'expiresAt': DateTime(2027).toIso8601String(),
  };

  /// A server that answers 200 with [body].
  http.Client answering(Map<String, dynamic> body) =>
      MockClient((_) async => http.Response(jsonEncode(body), 200));

  Future<AuthorizationCredentialAppleID> apple(String _) async =>
      const AuthorizationCredentialAppleID(
        userIdentifier: 'apple-user',
        givenName: null,
        familyName: null,
        authorizationCode: 'code',
        email: null,
        identityToken: 'apple-identity-token',
        state: null,
      );

  ApiAuthService service(http.Client client, {SessionStore? store}) =>
      ApiAuthService(
        client: client,
        baseUrl: 'http://x',
        sessionStore: store,
        providerSessionStore: store,
        googleIdToken: () async => 'google-id-token',
        appleCredential: apple,
      );

  /// Each door, reduced to (signed in?, code). It must ANSWER: a throw fails
  /// the test with the escaped error, which is the defect.
  final doors = <String, Future<(bool, String?)> Function(ApiAuthService s)>{
    'client Google': (s) async {
      final r = await s.signInWithGoogle();
      return (r.success, r.code);
    },
    'client Apple': (s) async {
      final r = await s.signInWithApple();
      return (r.success, r.code);
    },
    'Pro Google': (s) async {
      final r = await s.signInProviderWithGoogle();
      return (r.signedIn, r.code);
    },
    'Pro Apple': (s) async {
      final r = await s.signInProviderWithApple();
      return (r.signedIn, r.code);
    },
  };

  String failedCode(String door) =>
      door.contains('Google') ? 'google_failed' : 'apple_failed';

  for (final door in doors.entries) {
    group(door.key, () {
      final ok = door.key.startsWith('Pro') ? proOk : clientOk;
      final tokenKey = door.key.startsWith('Pro') ? 'accessToken' : 'tokens';

      test('the control: a proper 200 signs in', () async {
        final (signedIn, _) = await door.value(service(answering(ok())));
        expect(signedIn, isTrue);
      });

      test(
        'a 200 without its tokens answers « impossible », not a throw',
        () async {
          final (signedIn, code) = await door.value(
            service(answering(ok()..remove(tokenKey))),
          );
          expect(signedIn, isFalse);
          expect(code, failedCode(door.key));
        },
      );

      test(
        'a keychain that refuses the session answers, not a throw',
        () async {
          final (signedIn, code) = await door.value(
            service(answering(ok()), store: _RefusingStore()),
          );
          expect(signedIn, isFalse);
          expect(code, failedCode(door.key));
        },
      );
    });
  }
}

/// The keychain, refusing: what `flutter_secure_storage` does on a locked or
/// corrupted keychain.
class _RefusingStore implements SessionStore {
  @override
  Future<void> save(String value) async =>
      throw StateError('keychain refused the write');

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}

  @override
  Object get identity => this;
}
