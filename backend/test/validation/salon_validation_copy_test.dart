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

  group('the admin\'s place-change e-mails (§5.1)', () {
    test('the immediate one keeps its words under the cap (decision 133)', () {
      final m = renderAdminPlaceChangedEmail(
        providerId: 'p1',
        salonName: 'Salon Awa',
        changes: [
          (field: 'phone', before: '+2250700000009', after: '+2250700000010'),
          (field: 'location', before: null, after: '5.35, -3.99'),
        ],
      );
      expect(m.subject, 'Salon Awa a modifié son emplacement et son téléphone');
      expect(
        m.text,
        [
          'Salon Awa, un salon validé, a modifié son emplacement et son '
              'téléphone. Il reste en ligne ; vous pouvez le suspendre depuis '
              'la console.',
          'Emplacement : — → 5.35, -3.99',
          'Téléphone : +2250700000009 → +2250700000010',
          'https://admin.myweli.com/#/admin/providers/p1',
          'MyWeli — console d’administration.',
          'MyWeli Pro — votre salon, en ligne.',
        ].join('\n\n'),
      );
    });

    // Decision 133's summary: NEW copy, listed for the owner's approval in
    // the PR — pinned here so any change to it is a visible diff.
    Map<String, String?> place({String address = 'Rue des Jardins'}) => {
      'location': '5.35, -3.99',
      'address': address,
      'commune': 'Cocody, Abidjan',
      'phone': '+2250700000010',
    };

    test('the summary, word for word: the kinds, how many, since when in '
        'Abidjan\'s time, last reported → now, a value back to the reported '
        'one, the cap said', () {
      final m = renderAdminPlaceSummaryEmail(
        providerId: 'p1',
        salonName: 'Salon Awa',
        reported: place(),
        current: place(address: 'Rue Neuve'),
        fields: ['phone', 'address'],
        saves: 2,
        since: DateTime.utc(2026, 11, 12, 9, 10),
      );
      expect(
        m.subject,
        'Salon Awa a encore modifié son adresse et son téléphone',
      );
      expect(
        m.text,
        [
          'Salon Awa, un salon validé, a encore modifié son adresse et son '
              'téléphone : 2 modifications depuis le 12/11/2026 à 09:10 '
              '(heure d’Abidjan). Il reste en ligne ; vous pouvez le '
              'suspendre depuis la console.',
          'Valeurs du dernier e-mail → valeurs actuelles :',
          'Adresse : Rue des Jardins → Rue Neuve',
          'Téléphone : +2250700000010 (identique au dernier e-mail)',
          'Pour un même salon, ces e-mails sont regroupés : un au plus par '
              'heure.',
          'https://admin.myweli.com/#/admin/providers/p1',
          'MyWeli — console d’administration.',
          'MyWeli Pro — votre salon, en ligne.',
        ].join('\n\n'),
      );
      expect(m.html, contains('>Voir le salon</a>'));
    });

    test('one save is « 1 modification »; a kind no save touched but whose '
        'value moved (changed while suspended) is listed too', () {
      final m = renderAdminPlaceSummaryEmail(
        providerId: 'p1',
        salonName: 'Salon Awa',
        reported: place(),
        current: {...place(), 'location': '14.69, -17.44'},
        fields: ['phone'],
        saves: 1,
        since: DateTime.utc(2026, 11, 12, 23, 5),
      );
      expect(
        m.subject,
        'Salon Awa a encore modifié son emplacement et son téléphone',
      );
      expect(m.text, contains(': 1 modification depuis le 12/11/2026 à 23:05'));
      expect(m.text, contains('Emplacement : 5.35, -3.99 → 14.69, -17.44'));
      expect(m.text, isNot(contains('Adresse')));
    });
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
        renderAdminPlaceSummaryEmail(
          providerId: 'p1',
          salonName: 'Salon Awa',
          reported: {for (final f in kPlaceFieldLabels.keys) f: 'avant'},
          current: {
            for (final f in kPlaceFieldLabels.keys)
              f: f == 'phone' ? 'avant' : 'après',
          },
          fields: kPlaceFieldLabels.keys,
          saves: 3,
          since: DateTime.utc(2026, 11, 12, 9),
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
