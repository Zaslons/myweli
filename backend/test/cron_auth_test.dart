import 'dart:io';

import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/cron_auth.dart';
import 'package:test/test.dart';

/// A stand-in for the JWKS-backed verifier. The real one's signature/`iss`/
/// `aud`/`exp` checking is covered by the auth-social suite; what is untested —
/// and what this file exists for — is the layer above it: *which* Google
/// principal presented a valid token, and what happens when nobody did.
class _StubVerifier implements IdTokenVerifier {
  _StubVerifier({this.email, this.ok = true});

  final String? email;
  final bool ok;
  int calls = 0;

  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async {
    calls++;
    return (
      ok: ok,
      error: ok ? null : 'token_rejected',
      sub: ok ? 'sub-123' : null,
      email: ok ? email : null,
      emailVerified: ok,
      name: null,
      avatarUrl: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const schedulerSa = 'myweli-scheduler@myweli.iam.gserviceaccount.com';
  const secret = 'a-long-random-cron-secret-value';

  CronAuth build({
    IdTokenVerifier? verifier,
    String? sa = schedulerSa,
    String? shared = secret,
  }) => CronAuth(
    oidcVerifier: verifier,
    schedulerServiceAccount: sa,
    sharedSecret: shared,
  );

  group('deny by default', () {
    test('nothing configured → the route does not exist', () {
      expect(build(sa: null, shared: null).isConfigured, isFalse);
    });

    test('either mechanism configured → it exists', () {
      expect(
        build(shared: null, verifier: _StubVerifier()).isConfigured,
        isTrue,
      );
      expect(build().isConfigured, isTrue);
    });

    test('no credentials at all → forbidden', () async {
      final res = await build().authenticate();
      expect(res.ok, isFalse);
      expect(res.error, 'forbidden');
    });
  });

  group('OIDC — the token Cloud Scheduler already sends', () {
    test('a valid token from the scheduler service account → ok', () async {
      final v = _StubVerifier(email: schedulerSa);
      final res = await build(verifier: v).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isTrue);
      expect(res.method, CronAuthMethod.oidc);
      expect(v.calls, 1);
    });

    test('a VALID token from a different Google account → rejected', () async {
      // The load-bearing assertion. `aud` is a public string — any Google
      // account can mint a correctly-signed token for it — so verifying the
      // signature without pinning the principal would authenticate anyone.
      final res = await build(
        verifier: _StubVerifier(email: 'someone-else@gmail.com'),
      ).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isFalse);
    });

    test('a rejected token does not authenticate', () async {
      final res = await build(
        verifier: _StubVerifier(ok: false),
      ).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isFalse);
    });

    test(
      'the service-account match is case- and whitespace-insensitive',
      () async {
        final res = await build(
          verifier: _StubVerifier(
            email: '  MyWeli-Scheduler@Myweli.IAM.gserviceaccount.com ',
          ),
        ).authenticate(bearer: 'Bearer tok');
        expect(res.ok, isTrue);
      },
    );

    test(
      'a malformed Authorization header is ignored, not crashed on',
      () async {
        final v = _StubVerifier(email: schedulerSa);
        for (final header in ['', 'Bearer', 'Bearer   ', 'Basic abc', 'tok']) {
          final res = await build(verifier: v).authenticate(bearer: header);
          expect(res.ok, isFalse, reason: 'header: "$header"');
        }
        expect(v.calls, 0, reason: 'nothing reached the verifier');
      },
    );

    test('a valid OIDC token wins without the header being present', () async {
      // The end state: once the Scheduler jobs stop carrying the secret, this
      // is the only path left.
      final res = await build(
        verifier: _StubVerifier(email: schedulerSa),
        shared: null,
      ).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isTrue);
      expect(res.method, CronAuthMethod.oidc);
    });
  });

  group('shared secret — transitional, and reported as such', () {
    test(
      'the correct header authenticates, and says which path it took',
      () async {
        final res = await build().authenticate(headerSecret: secret);
        expect(res.ok, isTrue);
        expect(
          res.method,
          CronAuthMethod.sharedSecret,
          reason:
              'the route logs this — it is the signal that the header can go',
        );
      },
    );

    test('a wrong secret is refused', () async {
      expect((await build().authenticate(headerSecret: 'nope')).ok, isFalse);
    });

    test('a prefix of the real secret is refused', () async {
      // Guards the constant-time comparison against a length short-circuit.
      expect(
        (await build().authenticate(
          headerSecret: secret.substring(0, secret.length - 1),
        )).ok,
        isFalse,
      );
    });

    test('an empty secret does not authenticate', () async {
      expect((await build().authenticate(headerSecret: '')).ok, isFalse);
    });

    test('a bad OIDC token falls through to a good header', () async {
      // During the transition a misconfigured audience must not take the crons
      // down — the fallback is the whole point of shipping both at once.
      final res = await build(
        verifier: _StubVerifier(ok: false),
      ).authenticate(bearer: 'Bearer tok', headerSecret: secret);
      expect(res.ok, isTrue);
      expect(res.method, CronAuthMethod.sharedSecret);
    });
  });

  /// The credential must never travel in a URL.
  ///
  /// [CronAuth.authenticate] takes no query parameter, so a route cannot pass
  /// one without deliberately reaching for `uri.queryParameters` — which is
  /// exactly what both routes used to do, putting a production secret into
  /// access logs, load-balancer logs and anything else that records a URL.
  ///
  /// Source-pinned rather than exercised, because these routes read a global
  /// composition-root singleton built from `Platform.environment` at import
  /// time, so a handler test cannot configure them in-process. The repo already
  /// uses this shape for its design-system pins.
  group('the secret cannot travel in a URL', () {
    for (final path in [
      'routes/internal/cron/reminders.dart',
      'routes/internal/cron/subscriptions.dart',
    ]) {
      test('$path reads no query parameter', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('queryParameters'),
          isFalse,
          reason:
              '$path must not accept the cron secret via ?secret= — it lands '
              'in every log that records a URL',
        );
      });
    }
  });
}
