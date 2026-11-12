import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/status_labels.dart';
import 'package:myweli/core/utils/validation_labels.dart';
import 'package:myweli/models/admin_salon_validation.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/screens/admin/widgets/audit_actions.dart';
import 'package:myweli/screens/admin/widgets/status_chip.dart';
import 'package:myweli/services/admin/admin_service.dart';

import '../support/admin_salon_validation_fixtures.dart';
import '../support/dart_source.dart';

/// docs/design/salon-go-live-approval.md §4.3, §4.4, §8.2 « Bookkeeping » —
/// the console's words for a salon's validation: their own mapping, which
/// never relabels the shared « En attente » of every KYC and booking; the
/// salon's refusal sentences, the server's own (decision 132); « Lever la
/// suspension »'s snackbar, one per reason, from either server; the audit
/// labels, one per code the backend writes to the admin log.
void main() {
  SalonValidation v(String state, {bool wentLive = false}) =>
      SalonValidation.fromJson(
        validationJson(state: state, wentLive: wentLive),
      );

  /// Comment-free backend source, its adjacent literals joined.
  String backend(String path) =>
      asCopy(stripDartComments(File('../backend/$path').readAsStringSync()));

  group('the validation\'s state — its own words (§4.4)', () {
    test('« En attente de validation » · « Validé » · « Refusé »', () {
      expect(ValidationLabels.of(v('pending')), 'En attente de validation');
      expect(ValidationLabels.of(v('approved', wentLive: true)), 'Validé');
      expect(ValidationLabels.of(v('refused')), 'Refusé');
    });

    test('approved, never live: « Validation à terminer » (§3.2)', () {
      expect(ValidationLabels.of(v('approved')), 'Validation à terminer');
    });

    test('never asked has its words; a state this build does not know has '
        'none — never the wire value', () {
      expect(ValidationLabels.of(null), ValidationLabels.neverAsked);
      expect(ValidationLabels.of(v('escalated')), isNull);
    });

    test('the chips: waiting is pending, live is ok, refused is danger', () {
      for (final (validation, label, kind) in [
        (v('pending'), 'En attente de validation', AdminChipKind.pending),
        (v('approved'), 'Validation à terminer', AdminChipKind.pending),
        (v('approved', wentLive: true), 'Validé', AdminChipKind.ok),
        (v('refused'), 'Refusé', AdminChipKind.danger),
        (null, ValidationLabels.neverAsked, AdminChipKind.neutral),
        (v('escalated'), '—', AdminChipKind.neutral),
      ]) {
        final chip = StatusChip.forValidation(validation);
        expect(chip.label, label);
        expect(chip.kind, kind, reason: label);
      }
    });

    test('the shared « pending » is untouched: KYC and bookings still read '
        '« En attente »', () {
      expect(StatusLabels.ofRaw('pending'), 'En attente');
      final kyc = StatusChip.forStatus('pending');
      expect(kyc.label, 'En attente');
      expect(kyc.kind, AdminChipKind.pending);
    });
  });

  group('refusing (§4.3)', () {
    test('the salon reads the spec\'s words, verbatim; `other` reads the '
        'note alone', () {
      expect(ValidationLabels.salonSentences, {
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
    });

    test('… and they are the server\'s own sentences — the push, the feed '
        'and the e-mail say what the console shows', () {
      final copy = backend('lib/src/validation/salon_validation_copy.dart');
      for (final s in ValidationLabels.salonSentences.values.nonNulls) {
        expect(copy, contains(asCopy(s)), reason: s);
      }
    });

    test('the codes and the final ones are the server\'s, in its order', () {
      final repo = backend(
        'lib/src/validation/salon_validation_repository.dart',
      );
      List<String> literals(String decl) {
        final m = RegExp(
          '$decl\\s*=\\s*[\\[{]([^\\]}]*)[\\]}]',
        ).firstMatch(repo);
        expect(m, isNotNull, reason: decl);
        return [
          for (final q in RegExp("'([^']+)'").allMatches(m!.group(1)!))
            q.group(1)!,
        ];
      }

      expect(kSalonRefusalCodes, literals('kRefusalCodes'));
      expect(kFinalSalonRefusalCodes, literals('kFinalRefusalCodes').toSet());
    });

    test('every code has an admin name and a salon entry; only outside_ci '
        'and test_salon are final', () {
      for (final code in kSalonRefusalCodes) {
        expect(ValidationLabels.refusalNames[code], isNotNull, reason: code);
        expect(ValidationLabels.salonSentences.containsKey(code), isTrue);
      }
      expect(ValidationLabels.refusalName('other'), 'Autre');
      expect(
        [
          for (final c in kSalonRefusalCodes)
            if (ValidationLabels.isFinal(c)) c,
        ],
        ['outside_ci', 'test_salon'],
      );
    });

    test('the note is counted as the server counts it: code points of the '
        'trimmed note', () {
      expect(refusalNoteLength('  abc  '), 3);
      expect(refusalNoteLength('👍🏽'), 2, reason: 'one grapheme, two runes');
      expect(refusalInputError(code: 'other', note: ' '), 'note_required');
      expect(refusalInputError(code: 'other', note: 'x'), isNull);
      expect(refusalInputError(code: 'photos', note: ''), isNull);
      expect(refusalInputError(code: null, note: ''), 'invalid_input');
      expect(refusalInputError(code: 'nope', note: ''), 'invalid_input');
      expect(refusalInputError(code: 'photos', note: 'a' * 500), isNull);
      expect(
        refusalInputError(code: 'photos', note: 'a' * 501),
        'note_too_long',
      );
      expect(
        refusalInputError(code: 'photos', note: ' ${'🇨🇮' * 250} '),
        isNull,
        reason: '500 code points — 1000 UTF-16 units, 250 graphemes',
      );
      expect(
        refusalInputError(code: 'photos', note: '${'🇨🇮' * 250}x'),
        'note_too_long',
      );
    });

    test('the server counts runes of the trimmed note, too', () {
      final service = backend(
        'lib/src/validation/salon_validation_service.dart',
      );
      expect(service, contains('trimmed.runes.length > maxNoteCodePoints'));
      expect(service, contains('maxNoteCodePoints = 500'));
    });
  });

  group('a 409 `incomplete`\'s steps', () {
    test('each gate key in French — the app\'s checklist words, « horaires » '
        'as the spec writes it', () {
      expect(
        {
          for (final k in [
            'profile',
            'location',
            'services',
            'photos',
            'availability',
          ])
            k: ValidationLabels.missingStep(k),
        },
        {
          'profile': 'profil de l’entreprise',
          'location': 'position sur la carte',
          'services': 'services',
          'photos': 'photos',
          'availability': 'horaires',
        },
      );
    });

    test('the spec\'s example sentence, verbatim', () {
      expect(
        AdminService.incompleteSentence(['photos', 'availability']),
        'Le salon n’est plus complet : photos, horaires.',
      );
    });
  });

  group('« Lever la suspension »\'s snackbar — one per answer (§4.4)', () {
    test('live, from either server: « Salon remis en ligne »', () {
      for (final body in [
        {'id': 'provider_1', 'status': 'active'}, // before B0.18
        {'status': 'active', 'reason': null}, // B0.18
      ]) {
        expect(
          ValidationLabels.restoreMessage(RestoreOutcome.fromJson(body)),
          'Salon remis en ligne',
        );
      }
    });

    test('offline: the reason\'s word, each one', () {
      for (final (reason, word) in [
        ('not_validated', 'non validé'),
        ('offer_not_live', 'offre inactive'),
        ('unpaid', 'dépublié pour impayé'),
        ('no_owner', 'sans propriétaire'),
        ('unknown_prior', 'état antérieur inconnu'),
      ]) {
        expect(
          ValidationLabels.restoreMessage(
            RestoreOutcome.fromJson({'status': 'draft', 'reason': reason}),
          ),
          'Suspension levée — le salon reste hors ligne : $word',
        );
      }
    });

    test('a reason this build does not know still says « offline », never '
        'the wire value', () {
      final m = ValidationLabels.restoreMessage(
        RestoreOutcome.fromJson({'status': 'draft', 'reason': 'audit_hold'}),
      );
      expect(m, startsWith('Suspension levée — le salon reste hors ligne : '));
      expect(m, isNot(contains('audit_hold')));
    });

    test('the server\'s reasons are the five worded here', () {
      final service = backend('lib/src/admin/admin_provider_service.dart');
      final reasons = {
        for (final m in RegExp(
          r"static const \w+ = '([a-z_]+)';",
        ).allMatches(service))
          m.group(1)!,
      };
      expect(reasons, {
        'not_validated',
        'no_owner',
        'offer_not_live',
        'unpaid',
        'unknown_prior',
      });
      for (final r in reasons) {
        expect(
          ValidationLabels.restoreReason(r),
          isNot(ValidationLabels.restoreReason('?')),
          reason: r,
        );
      }
    });
  });

  group('the audit log\'s labels (§4.4)', () {
    test('the validation\'s decisions, and the renamed lift', () {
      expect(auditActionLabel('salon.approve'), 'Salon validé');
      expect(auditActionLabel('salon.refuse'), 'Mise en ligne refusée');
      expect(auditActionLabel('provider.restore'), 'Suspension levée');
    });

    test('every code the backend writes to the ADMIN log has a label — none '
        'renders raw', () {
      // The admin log's writers: `AuditLogRepository.append` callers. The
      // salon's own log (`ProviderAuditLogRepository`: members.*, clients.*)
      // is not shown here.
      final codes = <String>{};
      for (final dir in [
        'lib/src/admin',
        'lib/src/validation',
        'routes/admin',
      ]) {
        for (final f in Directory(
          '../backend/$dir',
        ).listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final src = stripDartComments(f.readAsStringSync());
          for (final m in RegExp(r"action:\s*'([a-z_.]+)'").allMatches(src)) {
            codes.add(m.group(1)!);
          }
          // `_setStatus(adminId, id, 'banned', 'user.ban', reason)`.
          for (final m in RegExp(
            r"_setStatus\(\s*\w+,\s*\w+,\s*'[a-z]+',\s*'([a-z_.]+)'",
          ).allMatches(src)) {
            codes.add(m.group(1)!);
          }
        }
      }
      expect(
        codes,
        containsAll(<String>[
          'salon.approve',
          'salon.refuse',
          'subscription.paid',
          'user.erase',
          'demo.snapshot',
          'admin.password_changed',
          'user.ban',
        ]),
        reason: 'the scan itself must see the writers',
      );
      expect(codes.where((c) => !kAuditActions.containsKey(c)), isEmpty);
    });
  });

  test('no « vérif » in the validation\'s words — that word is KYC\'s '
      '(spec, Vocabulary)', () {
    final words = [
      ValidationLabels.pending,
      ValidationLabels.approved,
      ValidationLabels.refused,
      ValidationLabels.finishing,
      ValidationLabels.neverAsked,
      ValidationLabels.unavailableTitle,
      ValidationLabels.unavailableBody,
      ValidationLabels.restoredLive,
      ValidationLabels.restoredOffline,
      ...ValidationLabels.refusalNames.values,
      ...ValidationLabels.salonSentences.values.nonNulls,
      for (final k in ValidationEventKind.values) ValidationLabels.eventKind(k),
      for (final c in ['salon.approve', 'salon.refuse', 'provider.restore'])
        auditActionLabel(c),
    ];
    for (final w in words) {
      expect(w.toLowerCase(), isNot(contains('vérif')), reason: w);
    }
    for (final f in [
      'lib/core/utils/validation_labels.dart',
      'lib/models/salon_validation.dart',
      'lib/models/admin_salon_validation.dart',
    ]) {
      expect(
        stripDartComments(File(f).readAsStringSync()).toLowerCase(),
        isNot(contains('vérif')),
        reason: f,
      );
    }
  });
}
