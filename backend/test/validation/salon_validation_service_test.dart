import 'dart:convert';

import 'package:myweli_backend/src/validation/salon_decision_notifier.dart';
import 'package:myweli_backend/src/validation/salon_validation_copy.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// A failure injected into the going-live step (§3.2 « a crash between step
/// 2 and step 4 »), or something run just before it (a suspension landing
/// between the checks and the going-live).
class _GoLiveHooks extends InMemorySalonValidationRepository {
  _GoLiveHooks({required super.providers, required super.members});

  bool crashOnce = false;
  Future<void> Function()? before;

  @override
  Future<GoLiveOutcome> goLive(String providerId, {DateTime? at}) async {
    if (crashOnce) {
      crashOnce = false;
      throw StateError('the instance died');
    }
    final hook = before;
    before = null;
    if (hook != null) await hook();
    return super.goLive(providerId, at: at);
  }
}

/// MyWeli's decisions (B0.18 — docs/design/salon-go-live-approval.md §3.2,
/// §3.3, §3.5): validate, refuse, the queue and the detail.
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  /// A salon whose owner asked to go live.
  Future<({String id, String ownerId})> pending({
    bool phoneOwner = false,
    String name = 'Salon Awa',
  }) async {
    final s = await w.salon(phoneOwner: phoneOwner, name: name);
    final r = await w.provisioning.publish(s.id);
    expect(r.accepted, isTrue, reason: '${r.error} ${r.data}');
    w.adminMail.sent.clear();
    return s;
  }

  group('validate', () {
    test('no offer row → live, the trial starts AT THE VALIDATION (90 days, '
        'pro), `salon.approved`, one audit row, one notice', () async {
      final s = await pending();
      w.now = w.now.add(const Duration(days: 4));

      final r = await w.service.approve(
        s.id,
        from: 'pending',
        adminId: 'admin_7',
      );
      expect(r.ok, isTrue, reason: '${r.error} ${r.data}');
      expect((r.data! as Map)['salonStatus'], 'active');
      expect(((r.data! as Map)['validation'] as Map)['wentLive'], isTrue);
      expect(await w.isPublic(s.id), isTrue);

      final row = (await w.subs.byProvider(s.id))!;
      expect(row.tier, 'pro');
      expect(row.trialEndsAt, w.now.add(const Duration(days: 90)));

      expect(w.rebuild.reasons, ['salon.approved']);
      final audit = (await w.audit.list()).items;
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'salon.approve');
      expect(audit.single['actorAdminId'], 'admin_7');
      expect(audit.single['targetId'], s.id);

      // The notice: push, feed row, e-mail — the owner's, once each.
      final push = w.pushes.sends.single;
      expect(push.tokens, ['tok-${s.ownerId}']);
      expect(push.title, 'Salon Awa est en ligne');
      expect(
        push.body,
        'Vos clients peuvent maintenant trouver votre salon et réserver.',
      );
      expect(push.data, {
        'event': 'salon.validation.approved',
        'providerId': s.id,
        'route': '/pro/onboarding?salon=${s.id}',
      });
      final rows = await w.feed.listForUser(s.ownerId);
      expect(rows.single['type'], 'salonValidation');
      expect(rows.single['route'], '/pro/onboarding?salon=${s.id}');
      final mail = w.ownerMail.sent.single;
      expect(mail.subject, 'Salon Awa est en ligne');
      // 2026-11-16 + 90 days, in Abidjan's wall clock.
      expect(
        mail.text,
        contains('Votre essai gratuit court jusqu’au 14/02/2027.'),
      );
      expect(mail.text, contains('https://myweli.com/pro?salon=${s.id}'));
    });

    test(
      'a refused salon validated from « Refusés » (from: refused)',
      () async {
        final s = await pending();
        await w.service.refuse(s.id, code: 'photos', note: null, adminId: 'a');
        final r = await w.service.approve(s.id, from: 'refused', adminId: 'a');
        expect(r.ok, isTrue, reason: '${r.error}');
        expect(await w.statusOf(s.id), 'active');
        final v = (await w.validations.get(s.id))!;
        expect(v.state, 'approved');
        expect(v.refusalCode, isNull);
      },
    );

    group('each 409, with nothing written', () {
      Future<void> nothingWritten(String id) async {
        expect((await w.validations.get(id))?.state, 'pending');
        expect(await w.subs.byProvider(id), isNull);
        expect(await w.statusOf(id), isNot('active'));
        expect((await w.audit.list()).items, isEmpty);
        expect(w.rebuild.reasons, isEmpty);
        expect(w.pushes.sends, isEmpty);
      }

      test('suspended → provider_suspended', () async {
        final s = await pending();
        await w.providers.setStatus(s.id, 'suspended');
        final r = await w.service.approve(s.id, from: 'pending', adminId: 'a');
        expect(r.error, 'provider_suspended');
        await nothingWritten(s.id);
      });

      test('the gate re-run: incomplete since the request → incomplete + '
          'missing', () async {
        final s = await pending();
        await w.providers.updateProfile(s.id, {'latitude': null});
        final r = await w.service.approve(s.id, from: 'pending', adminId: 'a');
        expect(r.error, 'incomplete');
        expect((r.data! as Map)['missing'], ['location']);
        await nothingWritten(s.id);
      });

      test(
        'an offer row that is no longer live → incomplete [offer]',
        () async {
          final s = await pending();
          await w.subs.create(
            providerId: s.id,
            tier: 'pro',
            trialEndsAt: w.now.subtract(const Duration(days: 30)),
          );
          final r = await w.service.approve(
            s.id,
            from: 'pending',
            adminId: 'a',
          );
          expect(r.error, 'incomplete');
          expect((r.data! as Map)['missing'], ['offer']);
          expect((await w.validations.get(s.id))!.state, 'pending');
          expect(await w.statusOf(s.id), 'draft');
        },
      );

      test(
        'never asked, or the wrong `from` → validation_not_pending',
        () async {
          final s = await w.salon();
          expect(
            (await w.service.approve(
              s.id,
              from: 'pending',
              adminId: 'a',
            )).error,
            'validation_not_pending',
          );
          final p = await pending();
          expect(
            (await w.service.approve(
              p.id,
              from: 'refused',
              adminId: 'a',
            )).error,
            'validation_not_pending',
          );
          expect(
            (await w.service.approve(
              p.id,
              from: 'approved',
              adminId: 'a',
            )).error,
            'validation_not_pending',
          );
          await nothingWritten(p.id);
        },
      );

      test(
        'no active owner → no_owner, rolled back: approved, not live',
        () async {
          final s = await pending();
          await w.members.deleteAllForAccount(s.ownerId);
          final r = await w.service.approve(
            s.id,
            from: 'pending',
            adminId: 'a',
          );
          expect(r.error, 'no_owner');
          expect(await w.statusOf(s.id), 'draft');
          expect((await w.validations.get(s.id))!.wentLive, isFalse);
          expect(w.rebuild.reasons, isEmpty);
        },
      );
    });

    test('bad input: an unknown `from` → invalid_input; an unknown salon → '
        'not_found', () async {
      final s = await pending();
      for (final from in [null, 'live', 3]) {
        expect(
          (await w.service.approve(s.id, from: from, adminId: 'a')).error,
          'invalid_input',
        );
      }
      expect(
        (await w.service.approve('nope', from: 'pending', adminId: 'a')).error,
        'not_found',
      );
    });

    group('races', () {
      test('validate + refuse together → ONE winner; the loser writes '
          'nothing more', () async {
        final s = await pending();
        final rs = await Future.wait([
          w.service.approve(s.id, from: 'pending', adminId: 'a1'),
          w.service.refuse(s.id, code: 'photos', note: null, adminId: 'a2'),
        ]);
        expect(rs.where((r) => r.ok), hasLength(1));
        expect(
          rs.where((r) => r.error == 'validation_not_pending'),
          hasLength(1),
        );
        expect((await w.audit.list()).items, hasLength(1));
        final v = (await w.validations.get(s.id))!;
        final live = await w.statusOf(s.id) == 'active';
        expect(live, v.state == 'approved', reason: 'public iff validated');
        expect(w.pushes.sends, hasLength(1), reason: 'one notice');
      });

      test('a DOUBLE validate → one audit row, one going-live, one rebuild, '
          'one notice', () async {
        final s = await pending();
        final rs = await Future.wait([
          w.service.approve(s.id, from: 'pending', adminId: 'a'),
          w.service.approve(s.id, from: 'pending', adminId: 'a'),
        ]);
        expect(rs.where((r) => r.ok), hasLength(1));
        expect((await w.audit.list()).items, hasLength(1));
        expect(w.rebuild.reasons, ['salon.approved']);
        expect(w.pushes.sends, hasLength(1));
        expect(w.ownerMail.sent, hasLength(1));
      });

      test(
        'two « finish » calls → one going-live, one rebuild, one notice',
        () async {
          final s = await pending();
          await w.validations.decide(
            s.id,
            from: 'pending',
            to: 'approved',
            adminId: 'a',
          );
          final rs = await Future.wait([
            w.service.approve(s.id, from: 'approved', adminId: 'a'),
            w.service.approve(s.id, from: 'approved', adminId: 'a'),
          ]);
          expect(rs.where((r) => r.ok), hasLength(1));
          expect(
            rs.where((r) => r.error == 'validation_not_pending'),
            hasLength(1),
          );
          expect(w.rebuild.reasons, ['salon.approved']);
          expect(w.pushes.sends, hasLength(1));
          expect(
            (await w.audit.list()).items,
            isEmpty,
            reason:
                'finishing is not a new decision — it was audited when '
                'taken',
          );
        },
      );
    });

    group('crashes and late changes', () {
      late _GoLiveHooks hooks;

      setUp(() {
        w = ValidationWorld(
          validationsOf: (providers, members) =>
              hooks = _GoLiveHooks(providers: providers, members: members),
        );
      });

      test('a failure between the decision and the going-live → NOT public; '
          '« Validation à terminer »; finished by from: approved', () async {
        final s = await pending();
        hooks.crashOnce = true;
        await expectLater(
          w.service.approve(s.id, from: 'pending', adminId: 'a'),
          throwsA(isA<StateError>()),
        );
        expect(await w.isPublic(s.id), isFalse);
        final v = (await w.validations.get(s.id))!;
        expect(v.state, 'approved');
        expect(v.wentLive, isFalse, reason: '« Validation à terminer »');
        expect(w.pushes.sends, isEmpty);
        // The owner, meanwhile, reads « finishing », never « live ».
        expect((await w.provisioning.publish(s.id)).accepted, isTrue);

        final done = await w.service.approve(
          s.id,
          from: 'approved',
          adminId: 'a',
        );
        expect(done.ok, isTrue, reason: '${done.error}');
        expect(await w.isPublic(s.id), isTrue);
        expect(w.rebuild.reasons, ['salon.approved']);
        expect(w.pushes.sends, hasLength(1));
        expect(
          (await w.audit.list()).items,
          hasLength(1),
          reason: 'the decision was audited once, before the crash',
        );
      });

      test('suspended between the checks and the going-live → 409 '
          'provider_suspended, nothing public', () async {
        final s = await pending();
        hooks.before = () async {
          await w.providers.setStatus(s.id, 'suspended');
        };
        final r = await w.service.approve(s.id, from: 'pending', adminId: 'a');
        expect(r.error, 'provider_suspended');
        expect(await w.statusOf(s.id), 'suspended');
        expect(await w.isPublic(s.id), isFalse);
        expect((await w.validations.get(s.id))!.wentLive, isFalse);
        expect(w.rebuild.reasons, isEmpty);
        expect(w.pushes.sends, isEmpty);
      });
    });
  });

  group('refuse', () {
    for (final code in kRefusalCodes) {
      test('$code → refused, the code kept, final = '
          '${kFinalRefusalCodes.contains(code)}', () async {
        final s = await pending();
        final note = code == 'other' ? 'Une précision.' : null;
        final r = await w.service.refuse(
          s.id,
          code: code,
          note: note,
          adminId: 'a',
        );
        expect(r.ok, isTrue, reason: '${r.error}');
        final refusal =
            ((r.data! as Map)['validation'] as Map)['refusal'] as Map;
        expect(refusal['code'], code);
        expect(refusal['final'], kFinalRefusalCodes.contains(code));
        expect(await w.statusOf(s.id), 'draft');
        expect(w.rebuild.reasons, isEmpty, reason: 'a draft stays a draft');
      });
    }

    test('the checks: an unknown code, a note that is not text → '
        'invalid_input; `other` without a note → note_required; beyond 500 '
        'CODE POINTS → note_too_long', () async {
      final s = await pending();
      Future<String?> refuse(Object? code, Object? note) async =>
          (await w.service.refuse(
            s.id,
            code: code,
            note: note,
            adminId: 'a',
          )).error;
      expect(await refuse('rude', null), 'invalid_input');
      expect(await refuse(null, null), 'invalid_input');
      expect(await refuse('photos', 42), 'invalid_input');
      expect(await refuse('other', null), 'note_required');
      expect(await refuse('other', '   '), 'note_required');
      expect(await refuse('photos', 'x' * 501), 'note_too_long');
      // 500 emoji: 1,000 UTF-16 units, 500 code points — the server's count.
      expect(await refuse('photos', '😀' * 501), 'note_too_long');
      expect((await w.validations.get(s.id))!.state, 'pending');
      final ok = await w.service.refuse(
        s.id,
        code: 'photos',
        note: '  ${'😀' * 500}  ',
        adminId: 'a',
      );
      expect(ok.ok, isTrue, reason: '${ok.error}');
      expect((await w.validations.get(s.id))!.refusalNote, '😀' * 500);
    });

    test('from pending only → validation_not_pending (a second refuse, a '
        'validated salon)', () async {
      final s = await pending();
      await w.service.refuse(s.id, code: 'photos', note: null, adminId: 'a');
      expect(
        (await w.service.refuse(
          s.id,
          code: 'photos',
          note: null,
          adminId: 'a',
        )).error,
        'validation_not_pending',
      );
      final t = await pending();
      await w.service.approve(t.id, from: 'pending', adminId: 'a');
      expect(
        (await w.service.refuse(
          t.id,
          code: 'photos',
          note: null,
          adminId: 'a',
        )).error,
        'validation_not_pending',
      );
      expect(await w.statusOf(t.id), 'active');
    });

    test('the audit row holds the CODE ONLY — never the note', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'unconfirmed',
        note: 'Appelé le 0700000000, pas de réponse.',
        adminId: 'admin_3',
      );
      final row = (await w.audit.list()).items.single;
      expect(row['action'], 'salon.refuse');
      expect(row['actorAdminId'], 'admin_3');
      expect(row['metadata'], {'code': 'unconfirmed'});
      expect(jsonEncode(row), isNot(contains('0700000000')));
      expect(jsonEncode(row), isNot(contains('pas de réponse')));
    });

    test('the notice: push (the sentence), feed row (sentence + note), '
        'e-mail (sentence, note, what next)', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'photos',
        note: 'Ajoutez la devanture.',
        adminId: 'a',
      );
      final push = w.pushes.sends.single;
      expect(push.title, 'Mise en ligne de Salon Awa refusée');
      expect(push.body, kRefusalSentences['photos']);
      expect(push.data['event'], 'salon.validation.refused');
      final row = (await w.feed.listForUser(s.ownerId)).single;
      expect(row['type'], SalonDecisionNotifier.feedType);
      expect(
        row['body'],
        '${kRefusalSentences['photos']}\nAjoutez la devanture.',
      );
      final mail = w.ownerMail.sent.single;
      expect(mail.subject, 'Mise en ligne de Salon Awa refusée');
      expect(mail.text, contains(kRefusalSentences['photos']));
      expect(mail.text, contains('Ajoutez la devanture.'));
      expect(mail.text, contains(kResubmitSentence));
    });

    test('a FINAL code: no « renvoyez » in the e-mail; `other` pushes the '
        'note itself', () async {
      final s = await pending();
      await w.service.refuse(
        s.id,
        code: 'outside_ci',
        note: null,
        adminId: 'a',
      );
      expect(w.ownerMail.sent.single.text, isNot(contains(kResubmitSentence)));
      expect(w.ownerMail.sent.single.text, contains('Aide & Support'));

      final t = await pending(name: 'Salon Bintou');
      await w.service.refuse(
        t.id,
        code: 'other',
        note: 'Le nom ne correspond pas.',
        adminId: 'a',
      );
      expect(w.pushes.sends.last.body, 'Le nom ne correspond pas.');
    });

    test('a note with markup is ESCAPED in the e-mail (T73), kept as '
        'written in the text part', () async {
      final s = await pending(name: 'Salon "Awa" & <Co>');
      const note = '<script>alert(1)</script>\nDeuxième ligne';
      await w.service.refuse(s.id, code: 'other', note: note, adminId: 'a');
      final mail = w.ownerMail.sent.single;
      expect(mail.html, isNot(contains('<script>')));
      expect(mail.html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
      expect(mail.html, contains('&lt;script&gt;alert(1)&lt;/script&gt;<br>'));
      // The salon's name too (element escaping: quotes are harmless there).
      expect(mail.html, contains('Salon "Awa" &amp; &lt;Co&gt;'));
      expect(mail.html, isNot(contains('<Co>')));
      expect(mail.text, contains(note));
    });

    test('a salon an older image left ACTIVE (§9.3) → refuse puts it back '
        'to draft and asks for a rebuild', () async {
      final s = await pending();
      await w.providers.setStatus(s.id, 'active'); // the rollback's flip
      final r = await w.service.refuse(
        s.id,
        code: 'unconfirmed',
        note: null,
        adminId: 'a',
      );
      expect(r.ok, isTrue);
      expect(await w.statusOf(s.id), 'draft');
      expect(await w.isPublic(s.id), isFalse);
      expect(w.rebuild.reasons, ['salon.refused']);
    });
  });

  group('the queue', () {
    test(
      'pending: oldest first, suspended left out, each item hydrated — '
      'name, place, owner contact (a phone when no e-mail), KYC count',
      () async {
        final a = await pending(name: 'Salon A');
        w.now = w.now.add(const Duration(hours: 1));
        final b = await pending(name: 'Salon B', phoneOwner: true);
        w.now = w.now.add(const Duration(hours: 1));
        final c = await pending(name: 'Salon C');
        await w.providers.setStatus(c.id, 'suspended');
        await w.auth.submitKyc(a.ownerId, [
          {'type': 'idCard', 'key': 'kyc/${a.ownerId}/1.jpg'},
          {'type': 'selfie', 'key': 'kyc/${a.ownerId}/2.jpg'},
        ]);

        final r = await w.service.queue(state: 'pending');
        final data = r.data! as Map;
        expect(data['total'], 2);
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        expect(items.map((i) => i['providerId']), [a.id, b.id]);
        expect(items.first['name'], 'Salon A');
        expect(items.first['commune'], 'Cocody');
        expect(items.first['city'], 'Abidjan');
        expect(items.first['countryCode'], 'CI');
        expect(items.first['ownerContact'], contains('@'));
        expect(items.first['kycDocCount'], 2);
        expect((items.first['validation'] as Map)['state'], 'pending');
        expect(items.last['ownerContact'], startsWith('+225'));
        expect(items.last['kycDocCount'], 0);
      },
    );

    test('refused and approved tabs; page/pageSize clamped; an unknown '
        'state → invalid_input', () async {
      final a = await pending(name: 'Salon A');
      final b = await pending(name: 'Salon B');
      await w.service.refuse(a.id, code: 'photos', note: null, adminId: 'x');
      await w.service.approve(b.id, from: 'pending', adminId: 'x');
      final refused = (await w.service.queue(state: 'refused')).data! as Map;
      expect((refused['items'] as List).map((i) => (i as Map)['providerId']), [
        a.id,
      ]);
      final approved =
          (await w.service.queue(
                state: 'approved',
                page: 0,
                pageSize: 1000,
              )).data!
              as Map;
      expect(approved['page'], 1);
      expect(approved['pageSize'], 100);
      expect((approved['items'] as List).map((i) => (i as Map)['providerId']), [
        b.id,
      ]);
      expect((await w.service.queue(state: 'live')).error, 'invalid_input');
      expect((await w.service.queue(state: null)).error, 'invalid_input');
    });
  });

  group('the detail', () {
    test('the salon, the owner (contact, age, KYC, other salons), the '
        'validation with who decided, and its history', () async {
      final s = await pending();
      // A second salon of the same owner, already public.
      final other = await w.providers.createSalon(
        name: 'Salon Awa 2',
        category: 'salon',
        phoneNumber: '+2250700000010',
      );
      await w.members.ensureOwner(
        providerId: other['id'] as String,
        accountId: s.ownerId,
        email: (await w.auth.accountById(s.ownerId))!.email!,
      );
      await w.service.refuse(
        s.id,
        code: 'other',
        note: 'Voir.',
        adminId: 'adm',
      );

      final r = await w.service.detail(s.id);
      expect(r.ok, isTrue);
      final d = r.data! as Map;
      expect((d['salon'] as Map)['id'], s.id);
      expect((d['salon'] as Map)['latitude'], 5.35);
      final owner = d['owner'] as Map;
      expect(owner['accountId'], s.ownerId);
      expect(owner['contact'], contains('@'));
      expect(owner['kycStatus'], 'pending');
      expect(owner['kycDocCount'], 0);
      expect(owner['accountAgeDays'], isA<int>());
      expect((owner['otherSalons'] as List).map((o) => (o as Map)['id']), [
        other['id'],
      ]);
      final v = d['validation'] as Map;
      expect(v['state'], 'refused');
      expect(v['decidedBy'], 'adm');
      expect((v['refusal'] as Map)['note'], 'Voir.');
      expect((d['events'] as List).map((e) => (e as Map)['kind']), [
        'submitted',
        'refused',
      ]);
      expect((await w.service.detail('nope')).error, 'not_found');
    });
  });
}
