import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/smoke_seam.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:test/test.dart';

import '../../routes/auth/email/otp/request.dart' as otp_request;

class _MockRequestContext extends Mock implements RequestContext {}

/// A global send ceiling must not become a per-user lockout.
///
/// `/auth/email/otp/request` calls `requestEmailOtp` FIRST — which spends one
/// of the caller's resends — and only then hands the message to the budget,
/// which may refuse. Left alone, that means an hour-long GLOBAL degradation
/// bills itself to whichever individuals happened to try during it, and the
/// bill outlasts the window: the budget resets at the top of the hour, their
/// resend allowance does not. Four silent retries and they hold a hard
/// `otp_resend_limit` for a reason that has nothing to do with them.
///
/// Design: docs/design/backend-email-send-budget.md §9.
void main() {
  const maxResends = 3;
  late InMemoryAuthRepository repo;

  setUp(() {
    repo = InMemoryAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: false,
      maxResends: maxResends,
    );
  });

  /// The real route, wired to a real budget at [ceiling] sends per hour.
  RequestContext ctx(String email, {required int ceiling}) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost/auth/email/otp/request'),
        body: jsonEncode({'email': email}),
        headers: {'content-type': 'application/json'},
      ),
    );
    when(() => context.read<AuthRepository>()).thenReturn(repo);
    when(
      () => context.read<AuthMethods>(),
    ).thenReturn(const AuthMethods({'email'}));
    when(() => context.read<SmokeSeam>()).thenReturn(const SmokeSeam(null));
    when(() => context.read<EmailProvider>()).thenReturn(
      BudgetedEmailProvider(
        LogEmailProvider(),
        InMemorySendBudget(ceilings: (cold: ceiling, warm: 1000)),
        log: (_) {},
      ),
    );
    return context;
  }

  Future<Response> hit(String email, {required int ceiling}) =>
      otp_request.onRequest(ctx(email, ceiling: ceiling));

  test(
    'a user refused by the budget is NOT left locked out afterwards',
    () async {
      // The whole regression, end to end. An exhausted window, a real person
      // trying repeatedly, and then the window rolls.
      const email = 'awa@example.test';
      for (var i = 0; i <= maxResends + 2; i++) {
        final r = await hit(email, ceiling: 0); // budget refuses everything
        expect(
          r.statusCode,
          HttpStatus.accepted,
          reason: 'attempt $i still looks normal to the caller',
        );
      }

      // The hour rolls: a fresh budget, and this person must be able to sign
      // in. Before the refund they could not — they had spent every resend on
      // mail that never left.
      final after = await hit(email, ceiling: 60);
      expect(after.statusCode, HttpStatus.accepted);
      final body = jsonDecode(await after.body()) as Map<String, dynamic>;
      expect(
        body['expiresInSeconds'],
        isNotNull,
        reason: 'a real code was issued, not an otp_resend_limit refusal',
      );
    },
  );

  test(
    'the ordinary resend budget still bites when mail DOES go out',
    () async {
      // The refund must not become a way to bypass the per-identity limit. With
      // a generous ceiling every send is real, so nothing is refunded and the
      // budget behaves exactly as before this change.
      const email = 'bintou@example.test';
      for (var i = 0; i <= maxResends; i++) {
        expect((await hit(email, ceiling: 60)).statusCode, HttpStatus.accepted);
      }
      final over = await hit(email, ceiling: 60);
      expect(over.statusCode, HttpStatus.tooManyRequests);
      expect(
        jsonDecode(await over.body()),
        containsPair('error', 'otp_resend_limit'),
      );
    },
  );

  test(
    'THE RESPONSE IS IDENTICAL whether the budget refused or sent',
    () async {
      // Replaces a test that read the route SOURCE and failed if it branched on
      // the send result. That was a proxy for the property, and the property is
      // what matters: a refusal must not be an address-exists oracle. Now the
      // real route is driven both ways and the answers are compared.
      final sent = await hit('one@example.test', ceiling: 60);
      final refused = await hit('two@example.test', ceiling: 0);

      expect(refused.statusCode, sent.statusCode);
      expect(
        jsonDecode(await refused.body()),
        equals(jsonDecode(await sent.body())),
      );
    },
  );

  group('the refund is bounded', () {
    test('it cannot lift an allowance above the maximum', () async {
      const email = 'cissé@example.test';
      await hit(email, ceiling: 0); // one request, one refusal, one refund
      for (var i = 0; i < 5; i++) {
        await repo.refundEmailOtpResend(email); // and four spurious ones
      }
      // Still exactly `maxResends` further requests before the limit bites.
      for (var i = 0; i < maxResends; i++) {
        expect(
          (await hit(email, ceiling: 60)).statusCode,
          HttpStatus.accepted,
          reason: 'resend $i',
        );
      }
      expect(
        (await hit(email, ceiling: 60)).statusCode,
        HttpStatus.tooManyRequests,
      );
    });

    test('it is a no-op for an address with no live code', () async {
      await repo.refundEmailOtpResend('nobody@example.test');
      // …and the first real request still starts from a full allowance.
      for (var i = 0; i <= maxResends; i++) {
        expect(
          (await hit('nobody@example.test', ceiling: 60)).statusCode,
          HttpStatus.accepted,
        );
      }
    });
  });

  test('a PROVIDER failure is deliberately NOT refunded', () async {
    // Reserve-before-send means a failed send has already spent global budget;
    // refunding the per-identity allowance too would remove the only bound left
    // exactly when the system is already degraded. The line: the allowance is
    // spent when we hand a message to the provider, refunded when we ourselves
    // declined to.
    const email = 'dede@example.test';
    final failing = _AlwaysFailsEmailProvider();
    for (var i = 0; i <= maxResends; i++) {
      final context = ctx(email, ceiling: 60);
      when(() => context.read<EmailProvider>()).thenReturn(failing);
      expect(
        (await otp_request.onRequest(context)).statusCode,
        HttpStatus.accepted,
      );
    }
    final context = ctx(email, ceiling: 60);
    when(() => context.read<EmailProvider>()).thenReturn(failing);
    expect(
      (await otp_request.onRequest(context)).statusCode,
      HttpStatus.tooManyRequests,
      reason: 'the per-identity budget still bites on provider failures',
    );
  });
}

class _AlwaysFailsEmailProvider implements EmailProvider {
  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async =>
      (ok: false, providerMessageId: null, error: 'provider_unavailable');
}
