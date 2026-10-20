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

  // The name is the salon's to write — a Manager can rename it
  // (`profile.manage`) — and these notices land in the OWNER's inbox.
  group('subscription notice HTML escapes the salon name', () {
    const hostile =
        'Ama <a href="https://evil.test">payer ici</a> '
        '<img src="https://evil.test/p.gif"> & "Co"';

    for (final kind in _kinds) {
      test('$kind: the name is shown, never rendered as markup', () {
        final html = renderSubscriptionNoticeHtml(kind, hostile);

        expect(html, isNot(contains('evil.test">')));
        expect('<a '.allMatches(html), hasLength(2)); // button + footer
        expect('<img'.allMatches(html), hasLength(1)); // the logo
        // Shown escaped, not dropped.
        expect(html, contains('Ama &lt;a href='));
        expect(html, contains('&lt;img src='));
        expect(html, contains(' &amp; '));
      });

      test('$kind: the plain-text part keeps the name as written', () {
        final text = renderSubscriptionNoticeText(kind, hostile);

        expect(text, contains(hostile));
        expect(text, isNot(contains('&lt;')));
        expect(text, isNot(contains('&amp;')));
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
