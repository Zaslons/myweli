import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/salon_validation_copy.dart';
import 'package:myweli/core/utils/salon_go_live.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/validation_labels.dart';
import 'package:myweli/models/pro_membership.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

import '../support/dart_source.dart';

/// B0.18 — docs/design/salon-go-live-approval.md §6.1, §6.6 (decision 136):
/// where a salon stands with MyWeli's validation, derived once, the same way
/// the website derives it (docs/design/web-salon-validation.md §2, row for
/// row), and the words each state shows — one home
/// ([SalonValidationCopy]), the website's words where both show the same
/// thing, the server's refusal sentences.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  SalonValidation v(
    SalonValidationState state, {
    bool wentLive = false,
    bool? offerLive,
    SalonRefusal? refusal,
    DateTime? submittedAt,
  }) => SalonValidation(
    state: state,
    wentLive: wentLive,
    offerLive: offerLive,
    refusal: refusal,
    submittedAt: submittedAt,
  );

  const photos = SalonRefusal(code: 'photos', note: 'Floues', isFinal: false);
  const outside = SalonRefusal(code: 'outside_ci', isFinal: true);

  group('goLiveState — web-salon-validation.md §2, row for row', () {
    GoLiveState s(String? status, SalonValidation? validation) => goLiveState(
      status: status,
      validationSent: true,
      validation: validation,
    );

    test('1 · no `validation` key (a server before B0.18) → legacy, whatever '
        'the status — today\'s screens (decision 136 item 10)', () {
      for (final status in [null, 'active', 'draft', 'suspended']) {
        expect(
          goLiveState(status: status, validationSent: false, validation: null),
          GoLiveState.legacy,
          reason: '$status',
        );
      }
    });

    test(
      '2 · suspended → suspended, before live and before the validation',
      () {
        expect(s('suspended', null), GoLiveState.suspended);
        expect(
          s('suspended', v(SalonValidationState.pending)),
          GoLiveState.suspended,
        );
        expect(
          s('suspended', v(SalonValidationState.approved, wentLive: true)),
          GoLiveState.suspended,
        );
      },
    );

    test('3 · active, or no status (null reads active) → live, whatever the '
        'row says (a rollback)', () {
      expect(s('active', null), GoLiveState.live);
      expect(s(null, null), GoLiveState.live);
      // The website's `!status` — an empty status is « no status » there.
      expect(s('', null), GoLiveState.live);
      expect(s('', v(SalonValidationState.pending)), GoLiveState.live);
      expect(
        s('active', v(SalonValidationState.refused, refusal: outside)),
        GoLiveState.live,
      );
    });

    test('4 · a draft with `validation: null` → never asked', () {
      expect(s('draft', null), GoLiveState.neverAsked);
    });

    test('5 · pending, or approved never live (finishing) → pending', () {
      expect(s('draft', v(SalonValidationState.pending)), GoLiveState.pending);
      expect(s('draft', v(SalonValidationState.approved)), GoLiveState.pending);
    });

    test('6 · refused with a final code → refusedFinal', () {
      expect(
        s('draft', v(SalonValidationState.refused, refusal: outside)),
        GoLiveState.refusedFinal,
      );
    });

    test('7 · refused otherwise → refused (no refusal object included)', () {
      expect(
        s('draft', v(SalonValidationState.refused, refusal: photos)),
        GoLiveState.refused,
      );
      expect(s('draft', v(SalonValidationState.refused)), GoLiveState.refused);
    });

    test('8–10 · validated and live once, back to draft: by `offerLive` — '
        'true republish, false unpaid, absent (not the owner) offline', () {
      SalonValidation was(bool? offerLive) => v(
        SalonValidationState.approved,
        wentLive: true,
        offerLive: offerLive,
      );
      expect(s('draft', was(true)), GoLiveState.offlineRepublish);
      expect(s('draft', was(false)), GoLiveState.offlineUnpaid);
      expect(s('draft', was(null)), GoLiveState.offline);
    });

    test('a state this build does not know never claims one: never asked, '
        'as the website', () {
      expect(
        s('draft', v(SalonValidationState.unknown)),
        GoLiveState.neverAsked,
      );
    });
  });

  group('the words, by state (§6.1, decision 136)', () {
    test('the picker\'s line: every state but legacy, which keeps today\'s '
        'row (decision 136 item 8)', () {
      expect(
        {for (final s in GoLiveState.values) s: goLiveLine(s)},
        {
          GoLiveState.legacy: null,
          GoLiveState.suspended: 'Suspendu',
          GoLiveState.live: 'En ligne',
          GoLiveState.neverAsked: 'Brouillon — pas encore en ligne',
          GoLiveState.pending: 'En cours de validation',
          GoLiveState.refused: 'Mise en ligne refusée',
          GoLiveState.refusedFinal: 'Mise en ligne refusée',
          GoLiveState.offlineRepublish: 'Plus en ligne',
          GoLiveState.offlineUnpaid: 'Plus en ligne',
          GoLiveState.offline: 'Plus en ligne',
        },
      );
    });

    test('the home card\'s subtitle (decision 136 item 1); not read yet (an '
        'offline cold start) keeps today\'s', () {
      expect(
        homeCardSubtitle(null),
        'Complétez les étapes pour aller en ligne',
      );
      expect(
        {for (final s in GoLiveState.values) s: homeCardSubtitle(s)},
        {
          GoLiveState.legacy: 'Complétez les étapes pour aller en ligne',
          GoLiveState.neverAsked: 'Complétez les étapes pour aller en ligne',
          GoLiveState.pending: 'En cours de validation',
          GoLiveState.refused: 'Mise en ligne refusée',
          GoLiveState.refusedFinal: 'Mise en ligne refusée',
          GoLiveState.offlineRepublish: 'Plus en ligne',
          GoLiveState.offlineUnpaid: 'Plus en ligne',
          GoLiveState.offline: 'Plus en ligne',
          GoLiveState.suspended: 'Suspendu',
          GoLiveState.live: 'Votre salon est en ligne',
        },
      );
    });

    test('the button: request, resubmit, republish — legacy keeps today\'s; '
        'none while waiting, after a final refusal, suspended, live', () {
      expect(
        {for (final s in GoLiveState.values) s: publishButtonLabel(s)},
        {
          GoLiveState.legacy: 'Mettre mon profil en ligne',
          GoLiveState.neverAsked: 'Demander la mise en ligne',
          GoLiveState.refused: 'Renvoyer pour validation',
          GoLiveState.offlineRepublish: 'Remettre en ligne',
          GoLiveState.pending: null,
          GoLiveState.refusedFinal: null,
          GoLiveState.suspended: null,
          GoLiveState.live: null,
          GoLiveState.offlineUnpaid: null,
          GoLiveState.offline: null,
        },
      );
    });

    test('the hint beside a disabled button', () {
      expect(
        publishHint(GoLiveState.legacy),
        'Complétez les étapes essentielles pour mettre votre profil en ligne.',
      );
      for (final s in [GoLiveState.neverAsked, GoLiveState.refused]) {
        expect(
          publishHint(s),
          'Complétez les étapes essentielles pour demander la mise en ligne.',
        );
      }
      for (final s in GoLiveState.values.where(
        (s) => !{
          GoLiveState.legacy,
          GoLiveState.neverAsked,
          GoLiveState.refused,
        }.contains(s),
      )) {
        expect(publishHint(s), isNull, reason: '$s');
      }
    });

    test('the banners: titles, lines and tones (§6.1; tones as the website '
        '§4.1)', () {
      final pending = goLiveBanner(GoLiveState.pending, null)!;
      expect(pending.tone, GoLiveTone.neutral);
      expect(pending.title, 'En cours de validation');
      expect(pending.lines, [
        'Nous examinons votre salon avant sa mise en ligne. Nous vous '
            'préviendrons dès que c’est fait.',
      ]);

      final refused = goLiveBanner(
        GoLiveState.refused,
        v(SalonValidationState.refused, refusal: photos),
      )!;
      expect(refused.tone, GoLiveTone.error);
      expect(refused.title, 'Mise en ligne refusée');
      expect(refused.lines, [
        'Les photos ne montrent pas assez clairement le salon et son travail.',
        'Floues',
        'Modifiez votre salon, puis renvoyez-le pour validation.',
      ]);

      final finalOne = goLiveBanner(
        GoLiveState.refusedFinal,
        v(
          SalonValidationState.refused,
          refusal: const SalonRefusal(
            code: 'test_salon',
            note: 'Salon de démonstration',
            isFinal: true,
          ),
        ),
      )!;
      expect(finalOne.tone, GoLiveTone.error);
      expect(finalOne.lines, [
        'Ce salon est un salon de test : il ne sera pas mis en ligne.',
        'Salon de démonstration',
      ], reason: 'a final refusal: no « Modifiez… renvoyez-le »');

      final unpaid = goLiveBanner(GoLiveState.offlineUnpaid, null)!;
      expect(unpaid.tone, GoLiveTone.warning);
      expect(unpaid.title, 'Votre salon n’est plus en ligne');
      expect(unpaid.lines, [
        'Votre salon n’est plus visible des clients. Vos données sont '
            'intactes.',
      ]);

      final republish = goLiveBanner(GoLiveState.offlineRepublish, null)!;
      expect(republish.tone, GoLiveTone.warning);
      expect(republish.lines, ['Vous pouvez le remettre en ligne.']);

      final suspended = goLiveBanner(GoLiveState.suspended, null)!;
      expect(suspended.tone, GoLiveTone.error);
      expect(suspended.title, 'Votre salon est suspendu');
      expect(suspended.lines, ['Contactez MyWeli pour en savoir plus.']);

      for (final s in [
        GoLiveState.legacy,
        GoLiveState.neverAsked,
        GoLiveState.live,
        GoLiveState.offline,
      ]) {
        expect(goLiveBanner(s, null), isNull, reason: '$s');
      }
    });

    test('a refusal\'s lines: `other` is the note alone; no note for a '
        'member who is not the owner; a blank note is no note', () {
      expect(
        refusalLines(
          const SalonRefusal(
            code: 'other',
            note: ' Appelez-nous ',
            isFinal: false,
          ),
        ),
        ['Appelez-nous'],
      );
      expect(
        refusalLines(const SalonRefusal(code: 'unconfirmed', isFinal: false)),
        ['Nous n’avons pas pu confirmer l’existence de ce salon.'],
      );
      expect(
        refusalLines(
          const SalonRefusal(code: 'photos', note: '  ', isFinal: false),
        ),
        ['Les photos ne montrent pas assez clairement le salon et son travail.'],
      );
      expect(refusalLines(null), isEmpty);
      expect(
        refusalLines(const SalonRefusal(code: 'nouveau', isFinal: false)),
        isEmpty,
        reason:
            'a code this build does not know shows no sentence, never '
            'the code',
      );
    });

    test('« Demande envoyée le 13 novembre 2026 » — no weekday (decision 136 '
        'item 6), the salon\'s day; nothing without a time', () {
      expect(
        requestSentLine(
          DateTime.utc(2026, 11, 13, 9, 30),
          tz: 'Africa/Abidjan',
        ),
        'Demande envoyée le 13 novembre 2026',
      );
      // 23:30 UTC is already the 14th in Lagos (UTC+1): the salon's clock,
      // never the device's.
      expect(
        requestSentLine(DateTime.utc(2026, 11, 13, 23, 30), tz: 'Africa/Lagos'),
        'Demande envoyée le 14 novembre 2026',
      );
      expect(
        requestSentLine(DateTime.utc(2026, 11, 1, 8), tz: 'Africa/Abidjan'),
        'Demande envoyée le 1 novembre 2026',
      );
      expect(requestSentLine(null), isNull);
    });
  });

  group('after a publish (§6.1 « After a request », decision 136 item 7)', () {
    test('« Demande envoyée » only for a request now waiting, or one whose '
        'body could not be read — as the website\'s onPublished', () {
      expect(const PublishOutcome.live().saysRequestSent, isFalse);
      expect(
        PublishOutcome.requested(
          v(SalonValidationState.pending),
        ).saysRequestSent,
        isTrue,
      );
      expect(
        PublishOutcome.requested(
          v(SalonValidationState.approved),
        ).saysRequestSent,
        isTrue,
        reason: 'the admin\'s validation finishing',
      );
      expect(
        PublishOutcome.requested(
          v(SalonValidationState.refused, refusal: photos),
        ).saysRequestSent,
        isFalse,
      );
      expect(const PublishOutcome.requested(null).saysRequestSent, isFalse);
      expect(const PublishOutcome.requestedUnread().saysRequestSent, isTrue);
    });

    test('the words: the request, the live answer, the final refusal', () {
      expect(
        SalonValidationCopy.requestSent,
        'Demande envoyée. Nous vous préviendrons de la décision.',
      );
      expect(SalonValidationCopy.wentLive, '🎉 Votre profil est en ligne !');
      expect(SalonValidationCopy.refusedFinalMessage, 'Mise en ligne refusée');
      expect(SalonValidationCopy.billingPointer, 'Mon abonnement');
      expect(
        SalonValidationCopy.communeFromList,
        'Choisissez la commune dans la liste',
      );
    });
  });

  group('the models carry the key apart from its value (decision 136 item '
      '10)', () {
    test('readSalonValidationKey: absent, null, an object, anything else', () {
      expect(readSalonValidationKey(const {}), (sent: false, validation: null));
      expect(readSalonValidationKey(const {'validation': null}), (
        sent: true,
        validation: null,
      ));
      expect(readSalonValidationKey(const {'validation': 'pending'}), (
        sent: true,
        validation: null,
      ));
      final read = readSalonValidationKey(const {
        'validation': {'state': 'pending', 'wentLive': false},
      });
      expect(read.sent, isTrue);
      expect(read.validation!.state, SalonValidationState.pending);
    });

    test('SalonValidation round-trips its wire shape, optional keys only '
        'when set', () {
      final full = SalonValidation(
        state: SalonValidationState.refused,
        wentLive: false,
        submittedAt: DateTime.utc(2026, 11, 12, 9),
        decidedAt: DateTime.utc(2026, 11, 13, 18, 51, 45),
        offerLive: false,
        refusal: photos,
        decidedBy: 'admin_1',
      );
      expect(SalonValidation.fromJson(full.toJson()), full);
      final bare = v(SalonValidationState.pending);
      expect(bare.toJson(), {'state': 'pending', 'wentLive': false});
      expect(SalonValidation.fromJson(bare.toJson()), bare);
      // A state this build does not know keeps the server's word.
      final unknown = SalonValidation.fromJson(const {
        'state': 'archived',
        'wentLive': false,
      });
      expect(unknown.state, SalonValidationState.unknown);
      expect(unknown.toJson()['state'], 'archived');
      expect(SalonValidation.fromJson(unknown.toJson()), unknown);
      expect(const SalonRefusal(code: 'outside_ci', isFinal: true).toJson(), {
        'code': 'outside_ci',
        'final': true,
      });
    });

    test('SalonMembershipInfo round-trips « absent », « null » and a '
        'validation as three answers', () {
      SalonMembershipInfo row({bool sent = false, SalonValidation? val}) =>
          SalonMembershipInfo(
            salonId: SalonId('p2'),
            salonName: 'Beauté Divine',
            role: TeamRole.staff,
            salonStatus: 'draft',
            verified: false,
            validation: val,
            validationSent: sent,
          );
      for (final info in [
        row(),
        row(sent: true),
        row(
          sent: true,
          val: v(
            SalonValidationState.approved,
            wentLive: true,
            submittedAt: DateTime.utc(2026, 11, 1),
          ),
        ),
      ]) {
        final json = info.toJson();
        expect(json.containsKey('validation'), info.validationSent);
        expect(SalonMembershipInfo.fromJson(json), info);
      }
      expect(row(), isNot(row(sent: true)));
    });

    test('MyProviderInfo.copyWith keeps the validation as it came', () {
      final salon = MockData.providers.first;
      final info = MyProviderInfo(
        salon: salon,
        membership: ProMembership(
          role: TeamRole.owner,
          capabilities: presetCapabilitiesFor(TeamRole.owner),
          salonId: salon.id,
          salonName: salon.name,
        ),
        validation: v(SalonValidationState.pending),
        validationSent: true,
      );
      final copy = info.copyWith();
      expect(copy.validation, info.validation);
      expect(copy.validationSent, isTrue);
    });
  });

  group('one home, and the same words as the server and the website', () {
    /// Comment-free source, its adjacent literals joined.
    String source(String path) =>
        asCopy(stripDartComments(File(path).readAsStringSync()));

    test('the refusal sentences are ONE map — the console\'s and the Pro '
        'app\'s — and the server\'s own', () {
      expect(
        identical(
          ValidationLabels.salonSentences,
          SalonValidationCopy.refusalSentences,
        ),
        isTrue,
      );
      final backend = source(
        '../backend/lib/src/validation/salon_validation_copy.dart',
      );
      for (final s in [
        ...SalonValidationCopy.refusalSentences.values.nonNulls,
        SalonValidationCopy.resubmit,
      ]) {
        expect(backend, contains(asCopy(s)), reason: s);
      }
    });

    test('the website shows the same words for the same states '
        '(web/lib/pro/salon-validation.ts)', () {
      final web = File(
        '../web/lib/pro/salon-validation.ts',
      ).readAsStringSync().replaceAll(RegExp(r'\s*\n\s*'), ' ');
      // STATE_LINE, key by key: the app's states are the website's.
      final block = RegExp(r'STATE_LINE[^=]*=\s*\{([^}]*)\}').firstMatch(web);
      expect(block, isNotNull, reason: 'STATE_LINE not found');
      final webLines = {
        for (final m in RegExp(
          r"(\w+):\s*'([^']*)'",
        ).allMatches(block!.group(1)!))
          m.group(1)!: m.group(2)!,
      };
      expect(webLines, {
        for (final s in GoLiveState.values)
          if (s != GoLiveState.legacy) s.name: goLiveLine(s),
      });
      // The rest, as literals. The legacy button and hint differ on
      // purpose (each surface keeps its own of today), and so does the
      // unpaid sentence (each « Mon abonnement » its own).
      for (final s in [
        SalonValidationCopy.requestButton,
        SalonValidationCopy.resubmitButton,
        SalonValidationCopy.republishButton,
        SalonValidationCopy.requestHint,
        SalonValidationCopy.billingPointer,
        SalonValidationCopy.requestSent,
        SalonValidationCopy.communeFromList,
        SalonValidationCopy.pendingTitle,
        SalonValidationCopy.pendingText,
        SalonValidationCopy.refusedTitle,
        SalonValidationCopy.offlineTitle,
        SalonValidationCopy.offlineRepublishText,
        SalonValidationCopy.suspendedTitle,
        SalonValidationCopy.suspendedText,
        SalonValidationCopy.resubmit,
        '${SalonValidationCopy.requestSentOnPrefix} ',
        ...SalonValidationCopy.refusalSentences.values.nonNulls,
      ]) {
        expect(web, contains(s), reason: s);
      }
    });
  });
}
