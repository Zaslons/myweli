import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No price, and no purchase route, in the Pro binary — App Store 3.1.1.
///
/// ## Why this file exists
///
/// The Pro subscription screen rendered a struck-through anchor
/// (« 70 000 FCFA ») and « /mois » on each tier card, beside a « Nous contacter »
/// button that opened WhatsApp with « je souhaite activer mon offre ». A
/// subscription that unlocks app functionality is digital content in Apple's
/// reading, so advertising its price and routing the purchase off-platform is
/// the shape that gets an app rejected — on a first submission, costing a cycle.
///
/// **What was NOT removed, and must not be:** « Choisir ». It moves no money.
/// It calls `PUT /providers/{id}/subscription`, starts the free trial, and is a
/// hard publish gate — `salon_provisioning_service.dart` refuses to publish a
/// salon without an offer and `team_service.dart` refuses staff invites. Taking
/// it out to look safer would break onboarding for every salon.
///
/// A source grep rather than a widget test, for the same reason the other infra
/// tests give: what matters is that the strings are not in the binary at all,
/// and a widget test only proves one route through one state.
void main() {
  final source = File(
    'lib/screens/provider/subscription/pro_subscription_screen.dart',
  ).readAsStringSync();

  /// Comments stripped. The block explaining WHY the price was removed quotes
  /// « 70 000 FCFA » and « /mois » — two guards in this repo have already
  /// matched a string that existed only in a comment, one of them the comment
  /// describing the very defect it was meant to catch.
  final code = source
      .split('\n')
      .map((l) => l.trimLeft().startsWith('//') ? '' : l)
      .join('\n');

  group('the Pro app advertises no price', () {
    test('no currency is rendered', () {
      for (final needle in ['FCFA', 'formatCurrency', '/mois', 'Sur devis']) {
        expect(
          code.contains(needle),
          isFalse,
          reason:
              'the subscription screen renders "$needle" — a price in the '
              'binary beside a way to buy is exactly what 3.1.1 refuses',
        );
      }
    });

    test('no anchor price is read from the plan config', () {
      expect(
        code,
        isNot(contains('AnchorMonthlyFcfa')),
        reason:
            'the amounts still live in SubscriptionPlans for the web dashboard, '
            'which is where billing belongs — but reading one here puts it back '
            'on the card',
      );
    });

    test('no purchase conversation is offered', () {
      expect(
        code,
        isNot(contains('openWhatsApp')),
        reason:
            'the CTA opened WhatsApp to arrange payment, which is the steering '
            'half of the same problem — and never worked anyway, because '
            'supportWhatsApp is passed by no build',
      );
      for (final phrase in ['régler', 'Nous contacter']) {
        expect(
          code.contains(phrase),
          isFalse,
          reason: 'the copy still routes the salon to a payment conversation',
        );
      }
    });
  });

  group('what must survive, because removing it breaks onboarding', () {
    test('« Choisir » is still there', () {
      // It moves no money: PUT /providers/{id}/subscription starts the free
      // trial. It is also the publish gate — a salon that cannot reach it
      // cannot go live or invite staff.
      expect(
        code,
        contains("'Choisir'"),
        reason:
            'without it a salon cannot select an offer, and the server refuses '
            'to publish (offer_required) — so the app would be unusable while '
            'looking compliant',
      );
    });

    test('the trial is still advertised', () {
      expect(code, contains('trialMonths'));
    });

    test('support is reachable from the screen', () {
      expect(code, contains('AppConfig.supportUrl'));
    });
  });
}
