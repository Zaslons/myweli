import 'package:myweli_backend/src/email/subscription_emails.dart';
import 'package:test/test.dart';

const _kinds = [
  SubscriptionNotice.trialJ14,
  SubscriptionNotice.trialJ7,
  SubscriptionNotice.trialJ1,
  SubscriptionNotice.grace,
  SubscriptionNotice.unpublished,
];

void main() {
  group('subscription notice HTML fits a phone (the OTP e-mail frame)', () {
    for (final kind in _kinds) {
      test('$kind: no fixed width, the card is capped at 440px', () {
        final html = renderSubscriptionNoticeHtml(kind, 'Salon Ama');

        // A fixed 440px card scrolled sideways at 310px.
        expect(html, isNot(contains('width="440"')));
        expect(html, contains('max-width:440px'));
        final tables = RegExp('<table[^>]*>').allMatches(html).toList();
        expect(tables, hasLength(2));
        for (final table in tables) {
          expect(table[0], contains('width="100%"'));
          // Padding lives on the cells: on the table it adds to the width.
          final style = RegExp('style="([^"]*)"').firstMatch(table[0]!)![1];
          expect(style, isNot(contains('padding')));
        }
      });
    }
  });

  group('subscription notice HTML keeps its content', () {
    for (final kind in _kinds) {
      test('$kind: body, logo, button and footer', () {
        final html = renderSubscriptionNoticeHtml(kind, 'Salon Ama');
        final body = renderSubscriptionNoticeText(
          kind,
          'Salon Ama',
        ).split('\n\n').first;

        expect(html, contains(body));
        expect(
          html,
          contains(
            'src="https://myweli.com/brand/myweli_lockup_horizontal_black.png"',
          ),
        );
        expect(html, contains('>Nous contacter</a>'));
        expect(html, contains('MyWeli Pro — votre salon, en ligne.'));
        expect(html, contains('>myweli.com</a>'));
      });
    }
  });
}
