import 'dart:io';

import 'package:myweli_backend/src/email/salon_validation_emails.dart';
import 'package:myweli_backend/src/validation/salon_validation_copy.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

/// The salon validation's words are the owner's: decision 132, « Yes, use
/// these words » (docs/design/salon-go-live-approval.md §4.3, §5.2, §6.1).
///
/// **Literally, here.** Every other test compares what a channel says with
/// the same constant the code uses (`kRefusalSentences[...]`,
/// `kResubmitSentence`), so a sentence edited, misspelt or reworded in that
/// constant stays green everywhere. These are the approved sentences,
/// copied from the spec — the one place a change to them goes red.
void main() {
  test('each refusal reason reads as §4.3 says, word for word; `other` has '
      'none of its own (the note alone)', () {
    expect(kRefusalSentences, {
      'incomplete_info':
          'Certaines informations du salon sont incomplètes ou peu claires.',
      'photos':
          'Les photos ne montrent pas assez clairement le salon et son '
          'travail.',
      'unconfirmed': 'Nous n’avons pas pu confirmer l’existence de ce salon.',
      'outside_ci':
          'MyWeli n’est pas encore disponible dans votre pays. Si votre '
          'salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & '
          'Support ».',
      'test_salon':
          'Ce salon est un salon de test : il ne sera pas mis en ligne.',
      'other': null,
    });
    expect(kRefusalSentences.keys, kRefusalCodes);
  });

  test('§6.1\'s resubmit sentence, and §5.2\'s titles and validated body', () {
    expect(
      kResubmitSentence,
      'Modifiez votre salon, puis renvoyez-le pour validation.',
    );
    expect(
      kApprovedBody,
      'Vos clients peuvent maintenant trouver votre salon et réserver.',
    );
    expect(approvedTitle('Salon Awa'), 'Salon Awa est en ligne');
    expect(refusedTitle('Salon Awa'), 'Mise en ligne de Salon Awa refusée');
  });

  group('no « vérif » in the validation copy — that word is KYC\'s', () {
    final banned = RegExp('v[ée]rif', caseSensitive: false);

    test('in the source of the copy and of the e-mails (comments aside)', () {
      for (final path in const [
        'lib/src/validation/salon_validation_copy.dart',
        'lib/src/email/salon_validation_emails.dart',
      ]) {
        // Comments stripped first: the copy file's own header says « No
        // « vérif » here ».
        final code = File(path)
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
            .replaceAll(RegExp(r'//[^\n]*'), '');
        expect(code, isNot(contains(banned)), reason: path);
      }
    });

    test('in every message as rendered', () {
      final said = <String>[
        for (final s in kRefusalSentences.values) ?s,
        kResubmitSentence,
        kApprovedBody,
        approvedTitle('Salon Awa'),
        refusedTitle('Salon Awa'),
        for (final code in kRefusalCodes) ...[
          refusalText(code, 'Une note.'),
          refusedPushBody(code, 'Une note.'),
        ],
      ];
      final mails = [
        renderSalonApprovedEmail(
          salonName: 'Salon Awa',
          providerId: 'p1',
          trialEndsOn: '14/02/2027',
        ),
        for (final code in kRefusalCodes)
          renderSalonRefusedEmail(
            salonName: 'Salon Awa',
            providerId: 'p1',
            code: code,
            note: 'Une note.',
          ),
        renderAdminNewRequestEmail(
          providerId: 'p1',
          salonName: 'Salon Awa',
          commune: 'Cocody',
          city: 'Abidjan',
          countryCode: 'CI',
        ),
        renderAdminPlaceChangedEmail(
          providerId: 'p1',
          salonName: 'Salon Awa',
          changes: [
            for (final field in kPlaceFieldLabels.keys)
              (field: field, before: 'avant', after: 'après'),
          ],
        ),
      ];
      for (final m in mails) {
        said.addAll([m.subject, m.text, m.html]);
      }
      for (final s in said) {
        expect(s, isNot(contains(banned)), reason: s);
      }
    });
  });
}
