import 'dart:io';

import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:test/test.dart';

/// The outbound-email ceiling.
///
/// Cloud Armor bought a 99.3% reduction against the trivial attacker and
/// nothing against a patient one, because per-IP limits *requests* and requests
/// are a proxy. This bounds the asset — the email channel and the domain's
/// reputation — so no attack SHAPE matters.
///
/// Design: docs/design/backend-email-send-budget.md.
class _Recording implements EmailProvider {
  final List<String> sent = [];
  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    sent.add('$to|$subject|${classification.bucket}');
    return (ok: true, providerMessageId: 'x${sent.length}', error: null);
  }
}

void main() {
  Future<EmailSendResult> fire(EmailProvider p, {required EmailClass cls}) =>
      p.send(
        to: 'someone@example.test',
        subject: 's',
        text: 't',
        classification: cls,
      );

  group('the ceiling', () {
    test('under it sends, at it refuses', () async {
      final inner = _Recording();
      final p = BudgetedEmailProvider(
        inner,
        InMemorySendBudget(ceilings: (cold: 3, warm: 100)),
        log: (_) {},
      );
      for (var i = 0; i < 3; i++) {
        expect(
          (await fire(p, cls: EmailClass.cold)).ok,
          isTrue,
          reason: 'send $i',
        );
      }
      final over = await fire(p, cls: EmailClass.cold);
      expect(over.ok, isFalse);
      expect(over.error, 'send_budget_exhausted');
      expect(
        inner.sent,
        hasLength(3),
        reason: 'the 4th never reached the provider',
      );
    });

    test('the window rolls', () async {
      var now = DateTime.utc(2026, 8, 18, 10, 30);
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 1, warm: 1), clock: () => now),
        log: (_) {},
      );
      expect((await fire(p, cls: EmailClass.cold)).ok, isTrue);
      expect((await fire(p, cls: EmailClass.cold)).ok, isFalse);
      now = DateTime.utc(2026, 8, 18, 11, 0); // next hour
      expect((await fire(p, cls: EmailClass.cold)).ok, isTrue);
    });
  });

  test('EXHAUSTING COLD DOES NOT TOUCH WARM', () async {
    // The whole reason there are two classes. A single global ceiling is worse
    // than none: an attacker exhausts it in a minute and every booking
    // confirmation for the rest of the hour is dropped — spam prevention
    // becomes a cheaper availability attack, because the attacker no longer
    // needs volume, only to be first.
    final inner = _Recording();
    final p = BudgetedEmailProvider(
      inner,
      InMemorySendBudget(ceilings: (cold: 2, warm: 5)),
      log: (_) {},
    );
    for (var i = 0; i < 6; i++) {
      await fire(p, cls: EmailClass.cold);
    }
    expect(
      (await fire(p, cls: EmailClass.cold)).ok,
      isFalse,
      reason: 'cold is spent',
    );

    // …and a real customer still gets their confirmation.
    expect((await fire(p, cls: EmailClass.warm)).ok, isTrue);
    expect(
      inner.sent.where((s) => s.endsWith('|warm')),
      hasLength(1),
      reason: 'warm must be untouched by a cold flood',
    );
  });

  test('concurrent sends cannot exceed the ceiling', () async {
    // The reservation is one atomic step for exactly this reason. A
    // read-then-write would let two callers both see 2 and both send.
    final inner = _Recording();
    final p = BudgetedEmailProvider(
      inner,
      InMemorySendBudget(ceilings: (cold: 10, warm: 10)),
      log: (_) {},
    );
    final results = await Future.wait([
      for (var i = 0; i < 25; i++) fire(p, cls: EmailClass.cold),
    ]);
    expect(results.where((r) => r.ok), hasLength(10));
    expect(inner.sent, hasLength(10));
  });

  test('the decorator passes the message through unchanged', () async {
    final inner = _Recording();
    final p = BudgetedEmailProvider(inner, InMemorySendBudget(), log: (_) {});
    await p.send(
      to: 'a@b.test',
      subject: 'Votre code',
      text: 'body',
      classification: EmailClass.cold,
    );
    expect(inner.sent.single, 'a@b.test|Votre code|cold');
  });

  test(
    'exhaustion is logged, so the operator learns what the caller does not',
    () async {
      final logged = <String>[];
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 0, warm: 0)),
        log: logged.add,
      );
      await fire(p, cls: EmailClass.cold);
      expect(logged.single, contains('email_budget_exhausted'));
      expect(logged.single, contains('cold'));
      // The recipient must NOT be in the log line — it is user data, and an OTP
      // address is exactly what an attacker would want read back.
      expect(logged.single, isNot(contains('example.test')));
    },
  );

  test('a refusal never carries a provider message id', () async {
    final p = BudgetedEmailProvider(
      _Recording(),
      InMemorySendBudget(ceilings: (cold: 0, warm: 0)),
      log: (_) {},
    );
    final r = await fire(p, cls: EmailClass.cold);
    expect(r.providerMessageId, isNull);
  });

  test('the default cold ceiling is far above real volume', () {
    // Measured 2026-08-18: ~37 /auth/* requests in SEVEN DAYS. If someone ever
    // tightens this below plausible launch traffic, that is a decision, not a
    // tidy-up.
    expect(kDefaultCeilings.cold, greaterThanOrEqualTo(60));
    expect(kDefaultCeilings.warm, greaterThan(kDefaultCeilings.cold));
  });

  test('a budget refusal must NOT change what the caller sees', () async {
    // `/auth/email/otp/request` returns 202 whether or not mail went out, so a
    // caller cannot learn whether an address exists. The budget adds a new way
    // for a send to fail, and that must not become an oracle: refusal and
    // success have to be indistinguishable from outside.
    //
    // The route ignores the send result entirely (`await …send(…)` with no
    // branch), which is what makes this hold — asserted here so a future
    // refactor that starts checking the result has to think about it.
    final routeSrc = File(
      'routes/auth/email/otp/request.dart',
    ).readAsStringSync().replaceAll(RegExp(r'//.*'), '');
    expect(
      routeSrc,
      isNot(
        contains(
          RegExp(
            r'(if|final)\s*\w*\s*=?\s*await\s+context\.read<EmailProvider>',
          ),
        ),
      ),
      reason:
          'the route must not branch on the send result — that would turn '
          'a budget refusal into an address-exists oracle',
    );
    expect(routeSrc, contains('await context.read<EmailProvider>().send('));
  });

  group('the early warning', () {
    // An alarm that only fires on exhaustion arrives AFTER users have been
    // turned away. For the case that actually worried us — real growth quietly
    // outrunning a ceiling picked before launch — that is too late to be worth
    // much. The warning is the half that arrives in time to act.
    test('fires once, while every message is still going out', () async {
      final logged = <String>[];
      final inner = _Recording();
      final p = BudgetedEmailProvider(
        inner,
        InMemorySendBudget(ceilings: (cold: 10, warm: 100)),
        log: logged.add,
      );
      for (var i = 0; i < 10; i++) {
        expect((await fire(p, cls: EmailClass.cold)).ok, isTrue);
      }
      expect(
        inner.sent,
        hasLength(10),
        reason: 'a warning must never withhold mail',
      );
      final warnings = logged.where(
        (l) => l.startsWith('email_budget_warning'),
      );
      expect(warnings, hasLength(1), reason: 'once per window, never a flood');
      expect(warnings.single, contains('class=cold'));
      expect(warnings.single, contains('sent=8'));
      expect(warnings.single, contains('ceiling=10'));
    });

    test('and it arrives BEFORE the first refusal', () async {
      // The ordering is the point. If the warning could only be emitted once
      // something had already been dropped it would be an alarm wearing a
      // different name.
      final logged = <String>[];
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 5, warm: 100)),
        log: logged.add,
      );
      for (var i = 0; i < 7; i++) {
        await fire(p, cls: EmailClass.cold);
      }
      final warned = logged.indexWhere(
        (l) => l.startsWith('email_budget_warn'),
      );
      final refused = logged.indexWhere(
        (l) => l.startsWith('email_budget_exh'),
      );
      expect(warned, isNonNegative, reason: 'it warned at all');
      expect(refused, isNonNegative, reason: 'it refused at all');
      expect(warned, lessThan(refused));
    });

    test('each class warns on its own counter', () async {
      final logged = <String>[];
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 5, warm: 10)),
        log: logged.add,
      );
      for (var i = 0; i < 5; i++) {
        await fire(p, cls: EmailClass.cold);
      }
      expect(
        logged.where((l) => l.startsWith('email_budget_warning')),
        hasLength(1),
        reason: 'cold crossed 4/5; warm has sent nothing and must be silent',
      );
      expect(logged.single, contains('class=cold'));

      for (var i = 0; i < 8; i++) {
        await fire(p, cls: EmailClass.warm);
      }
      final warnings = logged
          .where((l) => l.startsWith('email_budget_warning'))
          .toList();
      expect(warnings, hasLength(2));
      expect(warnings.last, contains('class=warm'));
      expect(warnings.last, contains('ceiling=10'));
    });

    test('a ceiling too small to have an 80% never warns', () async {
      // 80% of 3 is 2.4, which floors to 2 — but the danger is a ceiling of 1,
      // where the threshold floors to 0 and `sent` starts at 1. It must produce
      // silence rather than a warning on every single send.
      final logged = <String>[];
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 1, warm: 1)),
        log: logged.add,
      );
      for (var i = 0; i < 4; i++) {
        await fire(p, cls: EmailClass.cold);
      }
      expect(
        logged.where((l) => l.startsWith('email_budget_warning')),
        isEmpty,
        reason:
            'at that size exhaustion is the only signal that means anything',
      );
      expect(warnThreshold(1), 0);
    });

    test('the threshold is 80% of the ceiling', () {
      expect(warnThreshold(60), 48);
      expect(warnThreshold(1000), 800);
    });

    test('the log lines carry no recipient', () async {
      // Same rule as the exhaustion line: an OTP address is exactly what an
      // attacker would want read back out of the logs.
      final logged = <String>[];
      final p = BudgetedEmailProvider(
        _Recording(),
        InMemorySendBudget(ceilings: (cold: 5, warm: 5)),
        log: logged.add,
      );
      for (var i = 0; i < 6; i++) {
        await fire(p, cls: EmailClass.cold);
      }
      expect(logged, isNotEmpty);
      for (final line in logged) {
        expect(line, isNot(contains('example.test')));
      }
    });
  });

  test('the alert script watches the strings the code actually prints', () {
    // The literal reason this test exists: an alert that greps for a string the
    // code no longer prints reads as coverage forever. Rename either line and
    // this fails in CI rather than in production silence.
    final script = File(
      '../infra/gcp/88-email-budget-alert.sh',
    ).readAsStringSync();
    expect(script, contains('email_budget_exhausted'));
    expect(script, contains('email_budget_warning'));
  });
}
