import 'package:myweli_backend/src/email/invitation_emails.dart';
import 'package:test/test.dart';

const _roles = ['manager', 'reception', 'staff'];

void main() {
  // The name is the salon's to write — the owner or a Manager
  // (`profile.manage`) — and an invitation goes to ANY address the owner
  // types, from no-reply@myweli.com (threat T73).
  group('invitation HTML escapes the salon name', () {
    const hostile =
        'Ama <a href="https://evil.test">payer ici</a> '
        '<img src="https://evil.test/p.gif"> & "Co"';

    for (final role in _roles) {
      test('$role: the name is shown, never rendered as markup', () {
        final html = renderInvitationEmailHtml(hostile, role);

        expect(html, isNot(contains('evil.test">')));
        expect('<a '.allMatches(html), hasLength(2)); // button + footer
        expect('<img'.allMatches(html), hasLength(1)); // the logo
        // Shown escaped, not dropped.
        expect(html, contains('Ama &lt;a href='));
        expect(html, contains('&lt;img src='));
        expect(html, contains(' &amp; '));
      });

      test('$role: the plain text and the subject keep it as written', () {
        final text = renderInvitationEmailText(hostile, role);
        final subject = invitationEmailSubject(hostile);

        for (final plain in [text, subject]) {
          expect(plain, contains(hostile));
          expect(plain, isNot(contains('&lt;')));
          expect(plain, isNot(contains('&amp;')));
        }
      });
    }

    // The role is checked against the invitable set before any send, but
    // `roleLabelFr` falls back to the raw value: the template escapes every
    // string it interpolates, not only the one that is hostile today.
    test('an unknown role reaching the renderer is escaped too', () {
      final html = renderInvitationEmailHtml('Salon Ama', '<b>x</b>');

      expect(html, isNot(contains('<b>x')));
      expect(html, contains('&lt;b&gt;x'));
    });
  });

  group('invitation HTML keeps its content', () {
    for (final role in _roles) {
      test('$role: name, role, summary, logo, button and footer', () {
        final html = renderInvitationEmailHtml('Salon Ama', role);

        expect(html, contains('<strong>« Salon Ama »</strong>'));
        expect(html, contains('<strong>${roleLabelFr(role)}</strong>'));
        expect(
          html,
          contains(
            'src="https://myweli.com/brand/myweli_lockup_horizontal_black.png"',
          ),
        );
        expect(html, contains('>Ouvrir MyWeli Pro</a>'));
        expect(html, contains('L’invitation est valable 7 jours.'));
        expect(html, contains('>myweli.com</a>'));
      });
    }

    test('each role carries its own summary', () {
      expect(
        renderInvitationEmailHtml('Salon Ama', 'manager'),
        contains('Gère les rendez-vous, le catalogue et les disponibilités'),
      );
      expect(
        renderInvitationEmailHtml('Salon Ama', 'reception'),
        contains('Accueil : tout le planning et le fichier clients.'),
      );
      expect(
        renderInvitationEmailHtml('Salon Ama', 'staff'),
        contains('Voit uniquement son propre planning.'),
      );
    });
  });
}
