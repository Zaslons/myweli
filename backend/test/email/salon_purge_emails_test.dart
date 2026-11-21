import 'package:myweli_backend/src/email/salon_purge_emails.dart';
import 'package:test/test.dart';

/// Decision 156's two e-mails (deleted-owner-salon-purge.md §5.1): the
/// approved words, the day in the salon's timezone, the salon's own name
/// escaped in the HTML and kept on one line in the subject (T73).
void main() {
  test('the day is the salon\'s, in French', () {
    expect(
      salonPurgeDay(DateTime.utc(2027, 2, 18, 12), 'Africa/Abidjan'),
      '18 février 2027',
    );
    // 23:30 UTC is already the next day in Paris (UTC+1 in winter).
    expect(
      salonPurgeDay(DateTime.utc(2027, 2, 18, 23, 30), 'Europe/Paris'),
      '19 février 2027',
    );
  });

  test('the subjects', () {
    expect(
      salonPurgeNoticeSubject('Chez Awa', '18 février 2027'),
      'Chez Awa sera supprimé le 18 février 2027',
    );
    expect(
      salonPurgeReminderSubject('Chez Awa', 7),
      'Chez Awa sera supprimé dans 7 jours',
    );
    expect(
      salonPurgeReminderSubject('Chez Awa', 1),
      'Chez Awa sera supprimé demain',
    );
    expect(
      salonPurgeNoticeSubject('Chez\r\nBcc: x@y.z Awa', '1 mars 2027'),
      'Chez Bcc: x@y.z Awa sera supprimé le 1 mars 2027',
      reason: 'one line, whatever the salon typed',
    );
  });

  test(
    'the body: the approved words, the date twice-told, the account kept',
    () {
      final text = renderSalonPurgeText('Chez Awa', '18 février 2027');
      expect(
        text,
        contains(
          'Le propriétaire du salon Chez Awa a supprimé son '
          'compte MyWeli Pro.',
        ),
      );
      expect(text, contains('jusqu’au 18 février 2027'));
      expect(
        text,
        contains('y compris les rendez-vous prévus après cette date'),
      );
      expect(text, contains('Pensez à prévenir les clients concernés.'));
      expect(text, contains('Profil → Supprimer mon compte.'));
    },
  );

  test('the HTML escapes the salon\'s name', () {
    final html = renderSalonPurgeHtml('<b>Awa</b> & Co', '18 février 2027');
    expect(html, contains('&lt;b&gt;Awa&lt;/b&gt; &amp; Co'));
    expect(html, isNot(contains('<b>Awa</b>')));
  });
}
