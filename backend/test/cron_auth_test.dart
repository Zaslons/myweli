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
  CronAuth build({IdTokenVerifier? verifier, String? sa = schedulerSa}) =>
      CronAuth(oidcVerifier: verifier, schedulerServiceAccount: sa);

  group('deny by default', () {
    test('no verifier → the route does not exist', () {
      // The transitional shared secret is gone (2026-08-18), so OIDC is the
      // only mechanism: unconfigured means 404, not a route that exists and
      // can never authenticate anyone.
      expect(build().isConfigured, isFalse);
      expect(build(sa: null).isConfigured, isFalse);
    });

    test('a verifier → it exists', () {
      expect(build(verifier: _StubVerifier()).isConfigured, isTrue);
    });

    test('no credentials at all → forbidden', () async {
      final res = await build(verifier: _StubVerifier()).authenticate();
      expect(res.ok, isFalse);
      expect(res.error, 'forbidden');
    });
  });

  group('OIDC — the token Cloud Scheduler already sends', () {
    test('a valid token from the scheduler service account → ok', () async {
      final v = _StubVerifier(email: schedulerSa);
      final res = await build(verifier: v).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isTrue);
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

    test('a valid OIDC token is the only path there is', () async {
      final res = await build(
        verifier: _StubVerifier(email: schedulerSa),
      ).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isTrue);
    });
  });

  group('the retired shared secret cannot come back', () {
    // These are the tests that used to prove the fallback WORKED. Inverted
    // rather than deleted: the header is now inert, and a silently-vanished
    // group is indistinguishable from one that was never there.

    test('a bad OIDC token is refused outright — there is no fallback', () async {
      // This is the behaviour change. It used to fall through to the header so
      // a misconfigured audience could not take the crons down; now an audience
      // that stops matching CRON_OIDC_AUDIENCE fails closed, and
      // 86-cron-auth-alert.sh is what makes that visible.
      final res = await build(
        verifier: _StubVerifier(ok: false),
      ).authenticate(bearer: 'Bearer tok');
      expect(res.ok, isFalse);
      expect(res.error, 'forbidden');
    });

    test('authenticate() accepts no secret parameter at all', () {
      // Checked against CODE, not prose: the class doc deliberately still says
      // what was retired and why, so a plain `contains` over the whole file
      // would fail on its own documentation. Comment lines are stripped first.
      final code = File('lib/src/cron_auth.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final gone in [
        'sharedSecret',
        'headerSecret',
        'CronAuthMethod',
        'x-cron-secret',
      ]) {
        expect(
          code,
          isNot(contains(gone)),
          reason: '`$gone` is back in cron_auth.dart',
        );
      }
    });

    test('no route reads the header any more', () {
      for (final f in [
        'routes/internal/cron/reminders.dart',
        'routes/internal/cron/subscriptions.dart',
      ]) {
        // Comment lines stripped, same as above: both routes' docs still say
        // what was retired, and they should.
        final code = File(f)
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n')
            .toLowerCase();
        expect(
          code,
          isNot(contains('cron-secret')),
          reason: '$f still reads the retired header',
        );
      }
    });
  });

  /// The credential must never travel in a URL.
  ///
  /// [CronAuth.authenticate] takes no query parameter, so a route cannot pass
  /// one without deliberately reaching for `uri.queryParameters` — which is
  /// exactly what both routes used to do, putting a production secret into
  /// access logs, load-balancer logs and anything else that records a URL.
  ///
  /// **This pin moved, and grew, because it missed one.** It used to enumerate
  /// the two cron files by path — and `routes/webhooks/messaging/status.dart`
  /// was reading `?secret=` the whole time, so T21's claim that the pattern was
  /// "source-pinned so no route can reintroduce it" was false as written. An
  /// allowlist of the routes someone remembered is not a guard on the rule.
  ///
  /// It now scans the entire route tree and the composition root, with no
  /// exemptions, in `test/no_secret_in_url_test.dart` — which covers these two
  /// files along with every other.
  group('the secret cannot travel in a URL', () {
    test('is enforced tree-wide, not per-file — see no_secret_in_url_test', () {
      // Kept as a signpost rather than deleted: someone looking for this rule
      // will look here first, and a silently-vanished guard is indistinguishable
      // from one that was never there.
      expect(File('test/no_secret_in_url_test.dart').existsSync(), isTrue);
    });
  });
}
