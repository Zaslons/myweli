import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/smoke_seam.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:test/test.dart';

import '../../routes/auth/email/otp/request.dart' as otp_request;

class _MockRequestContext extends Mock implements RequestContext {}

/// The Q1b seam **through the real route** (`routes/auth/email/otp/request.dart`).
///
/// `smoke_seam_test.dart` pins the decision function. This pins the wiring —
/// that the route actually consults it, actually reads the `X-Smoke-Secret`
/// header, and actually returns `result.code` rather than the suppressed
/// `devCode`. A correct decision function that the route forgot to call would
/// pass every test in the other file.
void main() {
  // Composed rather than written as a literal: a 32-char string in a variable
  // named `secret` is the exact shape gitleaks' generic-api-key rule matches,
  // and a test fixture that trips the credential scanner is worse than none —
  // it trains us to wave the scanner through, and the next finding is real.
  // Derived from the real floor so it self-adjusts if that changes.
  final secret = 'not-a-real-secret-'.padRight(kMinSmokeSecretLength + 4, 'x');

  late InMemoryAuthRepository prodRepo;
  late InMemoryAuthRepository devRepo;

  setUp(() {
    // echoDevCode: false is the whole point — this is the configuration in
    // which devCode is null and the seam is the only way to obtain the code.
    // It is now the configuration of STAGING too, not just production
    // (docs/design/backend-staging-otp-disclosure.md).
    prodRepo = InMemoryAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: false,
    );
    devRepo = InMemoryAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: true,
    );
  });

  RequestContext ctx({
    required String email,
    required AuthRepository repo,
    required SmokeSeam seam,
    String? smokeHeader,
  }) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost/auth/email/otp/request'),
        headers: {
          'content-type': 'application/json',
          if (smokeHeader != null) 'X-Smoke-Secret': smokeHeader,
        },
        body: '{"email":"$email"}',
      ),
    );
    when(() => context.read<AuthMethods>()).thenReturn(AuthMethods.parse(null));
    when(() => context.read<AuthRepository>()).thenReturn(repo);
    when(() => context.read<SmokeSeam>()).thenReturn(seam);
    when(() => context.read<EmailProvider>()).thenReturn(LogEmailProvider());
    return context;
  }

  Future<Map<String, dynamic>> body(Response r) async =>
      await r.json() as Map<String, dynamic>;

  group('production', () {
    test('WITHOUT the seam configured, no code comes back', () async {
      // The status quo this slice must not disturb: production discloses
      // nothing, and the header is meaningless because the seam is absent.
      final r = await otp_request.onRequest(
        ctx(
          email: 'x@smoke.test',
          repo: prodRepo,
          seam: const SmokeSeam(null),
          smokeHeader: secret,
        ),
      );
      expect(r.statusCode, HttpStatus.accepted);
      expect((await body(r)).containsKey('devCode'), isFalse);
    });

    test('seam configured but NO header → still nothing', () async {
      final r = await otp_request.onRequest(
        ctx(email: 'x@smoke.test', repo: prodRepo, seam: SmokeSeam(secret)),
      );
      expect(r.statusCode, HttpStatus.accepted);
      expect((await body(r)).containsKey('devCode'), isFalse);
    });

    test('seam + header + a REAL address → still nothing', () async {
      // The account-takeover case, asserted at the route rather than only at
      // the pure function, because this is the request an attacker would send.
      final r = await otp_request.onRequest(
        ctx(
          email: 'owner@gmail.com',
          repo: prodRepo,
          seam: SmokeSeam(secret),
          smokeHeader: secret,
        ),
      );
      expect(r.statusCode, HttpStatus.accepted);
      expect(
        (await body(r)).containsKey('devCode'),
        isFalse,
        reason: 'a real address must never be disclosable, secret or not',
      );
    });

    test('seam + header + a .test identity → the code IS returned', () async {
      // Without this, the cutover gate cannot authenticate at all.
      final r = await otp_request.onRequest(
        ctx(
          email: 'client-abc@smoke.test',
          repo: prodRepo,
          seam: SmokeSeam(secret),
          smokeHeader: secret,
        ),
      );
      expect(r.statusCode, HttpStatus.accepted);
      final code = (await body(r))['devCode'] as String?;
      expect(code, isNotNull);
      expect(
        code,
        matches(RegExp(r'^\d{6}$')),
        reason: 'it must be the real six-digit OTP, not a placeholder',
      );
    });
  });

  group('non-production is untouched', () {
    test('devCode is echoed with no seam and no header', () async {
      // CI and local dev must need no secret. If this breaks, the entire
      // existing test suite and the CI funnel job break with it.
      final r = await otp_request.onRequest(
        ctx(
          email: 'anyone@example.com',
          repo: devRepo,
          seam: const SmokeSeam(null),
        ),
      );
      expect(r.statusCode, HttpStatus.accepted);
      expect((await body(r))['devCode'], matches(RegExp(r'^\d{6}$')));
    });
  });
}
