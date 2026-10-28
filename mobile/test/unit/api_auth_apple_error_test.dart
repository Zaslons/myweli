import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// docs/design/apple-signin-error-1000.md §2.2, §8 (B0.14) — what each of the
/// two Apple doors says when Apple's sheet fails, for EVERY code the plugin
/// has. Iterating `AuthorizationErrorCode.values` is the point: a code a later
/// plugin adds lands in the « every other code » row without anyone editing
/// this file, so it can never silently pick up the error-1000 sentence.
///
/// Error 1000 (`unknown`) is raised on the device, before anything reaches the
/// server — seen on 2026-10-26 on a device that is almost certainly Apple's
/// (BACKLOG B0.1). It is the one code with a fix the person can make.
void main() {
  const generic = 'Connexion Apple impossible.';
  // The owner-approved sentence, pinned literally (§2.3, Q1 — A).
  const checkTheAccount =
      'Connexion Apple impossible sur cet appareil. Vérifiez dans Réglages '
      'qu’un compte Apple est connecté, puis réessayez.';

  /// The two doors, reduced to what the screens show: the sentence and code.
  final doors = <String, Future<(String?, String?)> Function(ApiAuthService s)>{
    'client sign-in': (s) async {
      final r = await s.signInWithApple();
      expect(r.success, isFalse);
      return (r.error, r.code);
    },
    'Pro sign-in': (s) async {
      final r = await s.signInProviderWithApple();
      expect(r.signedIn, isFalse);
      return (r.error, r.code);
    },
  };

  /// A service whose Apple sheet throws [error]; [sent] records any request —
  /// there must never be one, the failure happens before the server.
  ApiAuthService failingWith(Object error, List<http.Request> sent) =>
      ApiAuthService(
        client: MockClient((req) async {
          sent.add(req);
          return http.Response('{}', 500);
        }),
        baseUrl: 'http://x',
        appleCredential: (_) async => throw error,
      );

  for (final door in doors.entries) {
    group(door.key, () {
      for (final code in AuthorizationErrorCode.values) {
        test('$code', () async {
          final sent = <http.Request>[];
          final (message, apiCode) = await door.value(
            failingWith(
              SignInWithAppleAuthorizationException(
                code: code,
                message: 'from the plugin',
              ),
              sent,
            ),
          );
          expect(sent, isEmpty, reason: 'nothing may reach the server');
          switch (code) {
            case AuthorizationErrorCode.canceled:
              // Closing the sheet says nothing (unchanged).
              expect(apiCode, 'cancelled');
              expect(message, isEmpty);
            case AuthorizationErrorCode.unknown:
              expect(message, checkTheAccount);
              expect(apiCode, 'apple_failed');
            default:
              expect(message, generic, reason: '$code has no fix to name');
              expect(apiCode, 'apple_failed');
          }
        });
      }

      test('not a plugin error — the generic sentence', () async {
        final sent = <http.Request>[];
        final (message, apiCode) = await door.value(
          failingWith(StateError('boom'), sent),
        );
        expect(sent, isEmpty);
        expect(message, generic);
        expect(apiCode, 'apple_failed');
      });
    });
  }
}
