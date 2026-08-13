import 'package:test/test.dart';

import '../tool/smoke/smoke_target.dart';

/// The funnel smoke harness may only write to a server it is allowed to write
/// to (docs/design/infra-staging.md §3.4).
///
/// **Why this is worth a test file.** The harness creates users, salons and
/// bookings, and in phase 7 it **suspends a salon**. Today one hostname is
/// plausible so a transposed `SMOKE_BASE_URL` is theoretical; staging creates a
/// second, and then the difference between "smoke ran" and "a salon was
/// suspended in production" is one wrong environment variable.
///
/// The check is deny-by-default, so the assertions that matter most are the
/// refusals — including the ones for addresses nobody has typed yet.
void main() {
  group('permitted targets', () {
    test('loopback — CI boots its own server, and so does a laptop', () {
      expect(
        resolveSmokeBaseUrl('http://localhost:8080'),
        'http://localhost:8080',
      );
      expect(
        resolveSmokeBaseUrl('http://127.0.0.1:8788'),
        'http://127.0.0.1:8788',
      );
    });

    test('the staging Cloud Run service, in both URL forms it publishes', () {
      // Cloud Run hands back two hostnames for one service; the check keys off
      // the service name leading the first label, which both forms share.
      for (final url in [
        'https://myweli-api-staging-731308991240.europe-west9.run.app',
        'https://myweli-api-staging-5a24ymhbbq-od.a.run.app',
      ]) {
        expect(resolveSmokeBaseUrl(url), url, reason: url);
      }
    });

    test('a trailing slash is trimmed, so paths concatenate cleanly', () {
      expect(
        resolveSmokeBaseUrl('http://localhost:8080/'),
        'http://localhost:8080',
      );
    });
  });

  group('refusals — the whole point', () {
    test('PRODUCTION, by hostname', () {
      expect(
        () => resolveSmokeBaseUrl('https://api.myweli.com'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('SUSPENDS a salon'),
          ),
        ),
      );
    });

    test("PRODUCTION's own run.app address, which is the subtle one", () {
      // It IS a *.run.app host, so a naive "allow Cloud Run" rule would let it
      // through. Production's ingress makes it unreachable today — but a guard
      // that depends on a separate setting staying correct is the kind that
      // stops working quietly, so this is refused on its own merits.
      expect(
        () => resolveSmokeBaseUrl(
          'https://myweli-api-731308991240.europe-west9.run.app',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('every other production surface, refused by default not by list', () {
      for (final url in [
        'https://myweli.com',
        'https://www.myweli.com',
        'https://admin.myweli.com',
        'https://cdn.myweli.com',
        'https://myweli-api-staging.myweli.com', // staging-looking, wrong domain
        'https://evil.example.com',
      ]) {
        expect(
          () => resolveSmokeBaseUrl(url),
          throwsA(isA<StateError>()),
          reason: 'must be refused: $url',
        );
      }
    });

    test('a lookalike host does not get in on prefix alone', () {
      // `.run.app` must be the real suffix, not a label inside someone else's
      // domain.
      expect(
        () => resolveSmokeBaseUrl(
          'https://myweli-api-staging.run.app.attacker.example',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('unset stays fail-closed — a vacuous pass is worse than no smoke', () {
      for (final raw in [null, '', '   ']) {
        expect(
          () => resolveSmokeBaseUrl(raw),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('refusing to pass vacuously'),
            ),
          ),
          reason: 'raw: $raw',
        );
      }
    });

    test('a value that is not an absolute URL is rejected, not guessed at', () {
      for (final raw in ['localhost:8080', 'api.myweli.com', 'not a url']) {
        expect(
          () => resolveSmokeBaseUrl(raw),
          throwsA(isA<StateError>()),
          reason: 'raw: $raw',
        );
      }
    });
  });
}
