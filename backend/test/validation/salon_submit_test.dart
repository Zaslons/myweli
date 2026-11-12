import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// Lets a test run something « at that very moment » — between the
/// service's read of the validation and its upsert (§3.1's race).
class _RacingValidations extends InMemorySalonValidationRepository {
  _RacingValidations({required super.providers, required super.members});

  Future<void> Function()? beforeSubmit;

  @override
  Future<SubmitOutcome> submit(
    String providerId,
    DateTime at, {
    SalonValidation? seen,
  }) async {
    final hook = beforeSubmit;
    beforeSubmit = null;
    if (hook != null) await hook();
    return super.submit(providerId, at, seen: seen);
  }
}

/// What Postgres `updateProfile` hands back: the raw `data` blob, whose
/// `services` and `weeklySchedule` are the stale ones `createSalon` wrote —
/// the catalogue lives in its own tables since 0005.
class _StaleBlobProviders extends InMemoryProvidersRepository {
  _StaleBlobProviders() : super([]);

  @override
  Future<Map<String, dynamic>?> updateProfile(
    String providerId,
    Map<String, dynamic> changes,
  ) async {
    final fresh = await super.updateProfile(providerId, changes);
    if (fresh == null) return null;
    return {
      ...fresh,
      'services': const <Map<String, dynamic>>[],
      'availability': {'weeklySchedule': <String, dynamic>{}},
    };
  }
}

/// The owner's request to go live (B0.18 — docs/design/salon-go-live-approval.md
/// §3.1): `SalonProvisioningService.publish`, now the SUBMIT. Every row of
/// the branch table, the order of the checks, the admin's e-mail on a NEW
/// request only, and what it no longer does (no trial, no rebuild on a 202).
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  Map<String, dynamic> validationOf(SubmitResult r) =>
      (r.data! as Map)['validation'] as Map<String, dynamic>;

  group('never asked', () {
    test('→ 202 pending: an event, ONE admin e-mail, still draft, no trial, '
        'no rebuild', () async {
      final s = await w.salon();
      final r = await w.provisioning.publish(s.id);

      expect(r.ok, isTrue, reason: '${r.error} ${r.data}');
      expect(r.accepted, isTrue);
      expect(validationOf(r)['state'], 'pending');
      expect(validationOf(r)['submittedAt'], w.now.toIso8601String());
      expect(validationOf(r)['wentLive'], isFalse);
      expect(await w.statusOf(s.id), 'draft');
      expect(await w.isPublic(s.id), isFalse);
      final events = await w.validations.events(s.id);
      expect(events.map((e) => e.kind), ['submitted']);
      expect(w.adminMail.sent, hasLength(1));
      expect(await w.subs.byProvider(s.id), isNull, reason: 'no trial');
      expect(w.rebuild.reasons, isEmpty, reason: 'no rebuild on a 202');
      expect(w.ownerMail.sent, isEmpty);
    });

    test('the admin e-mail: « Nouveau salon à valider : {Salon} », the '
        'commune, the country and the hash link; logged WITHOUT the '
        'address', () async {
      final s = await w.salon(name: 'Salon <b>Awa</b>');
      await w.provisioning.publish(s.id);

      final mail = w.adminMail.sent.single;
      expect(mail.to, 'admin@myweli.com');
      expect(mail.subject, 'Nouveau salon à valider : Salon <b>Awa</b>');
      expect(mail.text, contains('Commune : Cocody, Abidjan'));
      expect(mail.text, contains('Pays : CI'));
      expect(
        mail.text,
        contains('https://admin.myweli.com/#/admin/salon-validations/${s.id}'),
      );
      expect(mail.html, contains('Salon &lt;b&gt;Awa&lt;/b&gt;'));
      expect(mail.html, isNot(contains('<b>Awa</b>')));
      expect(w.adminLogs.single, contains('outcome=sent'));
      expect(w.adminLogs.single, contains(s.id));
      for (final l in w.adminLogs) {
        expect(l, isNot(contains('admin@myweli.com')));
      }
    });

    test('a DOUBLE submit → one event, ONE admin e-mail; the second answers '
        '202 with the same request', () async {
      final s = await w.salon();
      final first = await w.provisioning.publish(s.id);
      w.now = w.now.add(const Duration(minutes: 1));
      final second = await w.provisioning.publish(s.id);

      expect(second.accepted, isTrue);
      expect(validationOf(second), validationOf(first));
      expect(await w.validations.events(s.id), hasLength(1));
      expect(w.adminMail.sent, hasLength(1));
    });

    test(
      'a double TAP (two requests at once) → one event, one e-mail',
      () async {
        final s = await w.salon();
        final both = await Future.wait([
          w.provisioning.publish(s.id),
          w.provisioning.publish(s.id),
        ]);
        expect(both.every((r) => r.accepted), isTrue);
        expect(await w.validations.events(s.id), hasLength(1));
        expect(w.adminMail.sent, hasLength(1));
      },
    );

    test('a failed admin e-mail never fails the request — logged', () async {
      w.adminMail.fail = true;
      final s = await w.salon();
      final r = await w.provisioning.publish(s.id);
      expect(r.accepted, isTrue);
      expect(w.adminLogs.single, contains('outcome=failed'));

      w.adminMail
        ..fail = false
        ..explode = true;
      final t = await w.salon();
      expect((await w.provisioning.publish(t.id)).accepted, isTrue);
      expect(w.adminLogs.last, contains('outcome=failed'));
      expect((await w.validations.get(t.id))!.state, 'pending');
    });

    test('ADMIN_EMAIL unset → nothing is sent, the request stands', () async {
      w.adminAddress = null;
      final s = await w.salon();
      expect((await w.provisioning.publish(s.id)).accepted, isTrue);
      expect(w.adminMail.sent, isEmpty);
      expect(w.adminLogs.single, contains('outcome=skipped'));
    });
  });

  group('refused', () {
    Future<String> refused(String code) async {
      final s = await w.salon();
      await w.provisioning.publish(s.id);
      final r = await w.service.refuse(
        s.id,
        code: code,
        note: code == 'other' ? 'Précisez votre adresse.' : null,
        adminId: 'admin_1',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      w.adminMail.sent.clear();
      return s.id;
    }

    test(
      'not final → pending again: a new event and a new admin e-mail',
      () async {
        final id = await refused('photos');
        final r = await w.provisioning.publish(id);
        expect(r.accepted, isTrue);
        expect(validationOf(r)['state'], 'pending');
        expect(validationOf(r).containsKey('refusal'), isFalse);
        expect((await w.validations.events(id)).map((e) => e.kind), [
          'submitted',
          'refused',
          'submitted',
        ]);
        expect(w.adminMail.sent, hasLength(1));
      },
    );

    for (final code in kFinalRefusalCodes) {
      test('FINAL ($code) → 409 validation_refused_final: no event, no '
          'e-mail, still refused', () async {
        final id = await refused(code);
        final r = await w.provisioning.publish(id);
        expect(r.ok, isFalse);
        expect(r.error, 'validation_refused_final');
        expect(await w.validations.events(id), hasLength(2));
        expect(w.adminMail.sent, isEmpty);
        expect((await w.validations.get(id))!.state, 'refused');
      });
    }
  });

  group('already pending', () {
    test('→ 202, the same body, no new event, no notification', () async {
      final s = await w.salon();
      final first = await w.provisioning.publish(s.id);
      w.adminMail.sent.clear();
      final again = await w.provisioning.publish(s.id);
      expect(again.accepted, isTrue);
      expect(validationOf(again), validationOf(first));
      expect(await w.validations.events(s.id), hasLength(1));
      expect(w.adminMail.sent, isEmpty);
    });
  });

  group('validated', () {
    test('was live, draft, a LIVE offer → 200 live (the republish): '
        'unpublished_at cleared, `salon.republished`, and the scheduler can '
        'unpublish it again', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      // Unpublished for non-payment, then paid without the republish (the
      // salon was suspended meanwhile, say): draft, an unpublish mark, a
      // live offer.
      await w.providers.setStatus(s.id, 'draft');
      await w.subs.update(s.id, unpublishedAt: w.now);
      w.rebuild.reasons.clear();
      w.adminMail.sent.clear();

      final r = await w.provisioning.publish(s.id);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.accepted, isFalse, reason: 'live: the 200');
      expect((r.data! as Map)['status'], 'active');
      expect(await w.isPublic(s.id), isTrue);
      expect((await w.subs.byProvider(s.id))!.unpublishedAt, isNull);
      expect(w.rebuild.reasons, ['salon.republished']);
      expect(w.adminMail.sent, isEmpty, reason: 'nothing to validate');
      expect(await w.validations.events(s.id), hasLength(2));

      // The trial runs out, grace ends: the scheduler unpublishes it AGAIN —
      // which it could not while the mark stayed set.
      w.now = w.now.add(const Duration(days: 120));
      final tick = await w.scheduler(enforce: true).tick(w.now);
      expect(tick.unpublished, 1);
      expect(await w.statusOf(s.id), 'draft');
    });

    test('was live, draft, the offer row EXPIRED → 409 incomplete [offer], '
        'never a second trial', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await w.providers.setStatus(s.id, 'draft');
      final before = (await w.subs.byProvider(s.id))!.trialEndsAt;
      w.now = w.now.add(const Duration(days: 120));
      w.rebuild.reasons.clear();

      final r = await w.provisioning.publish(s.id);
      expect(r.error, 'incomplete');
      expect((r.data! as Map)['missing'], ['offer']);
      expect((await w.subs.byProvider(s.id))!.trialEndsAt, before);
      expect(await w.statusOf(s.id), 'draft');
      expect(w.rebuild.reasons, isEmpty);
    });

    test(
      'was live, draft, NO offer row at all → 409 incomplete [offer]',
      () async {
        // The gate adds `offer` only for a row that exists; the validated
        // branch is what refuses a salon with none (§3.1's second row).
        final s = await w.salon();
        await w.validations.submit(s.id, w.now);
        await w.validations.decide(
          s.id,
          from: 'pending',
          to: 'approved',
          adminId: 'admin_1',
        );
        expect(await w.validations.goLive(s.id), GoLiveOutcome.live);
        await w.providers.setStatus(s.id, 'draft');
        expect(await w.subs.byProvider(s.id), isNull);

        final r = await w.provisioning.publish(s.id);
        expect(r.error, 'incomplete');
        expect((r.data! as Map)['missing'], ['offer']);
        expect(await w.statusOf(s.id), 'draft');
      },
    );

    test('NEVER live (the admin\'s validation is finishing) → 202 with the '
        'validation; nothing written, nothing fired', () async {
      final s = await w.salon();
      await w.provisioning.publish(s.id);
      await w.validations.decide(
        s.id,
        from: 'pending',
        to: 'approved',
        adminId: 'admin_1',
      );
      w.adminMail.sent.clear();

      final r = await w.provisioning.publish(s.id);
      expect(r.accepted, isTrue);
      expect(validationOf(r)['state'], 'approved');
      expect(validationOf(r)['wentLive'], isFalse);
      expect(await w.statusOf(s.id), 'draft');
      expect(w.rebuild.reasons, isEmpty);
      expect(w.adminMail.sent, isEmpty);
    });

    test('already ACTIVE → 200, idempotent: no event, no e-mail, no '
        'rebuild', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      w.rebuild.reasons.clear();
      w.adminMail.sent.clear();

      final r = await w.provisioning.publish(s.id);
      expect(r.ok, isTrue);
      expect(r.accepted, isFalse);
      expect((r.data! as Map)['status'], 'active');
      expect(await w.validations.events(s.id), hasLength(2));
      expect(w.rebuild.reasons, isEmpty);
      expect(w.adminMail.sent, isEmpty);
    });
  });

  group(
    'the admin decided at that very moment (the upsert returns no row)',
    () {
      late _RacingValidations racing;

      setUp(() {
        w = ValidationWorld(
          validationsOf: (providers, members) => racing = _RacingValidations(
            providers: providers,
            members: members,
          ),
        );
      });

      Future<String> refusedFor(String code) async {
        final s = await w.salon();
        await w.provisioning.publish(s.id);
        await w.service.refuse(s.id, code: code, note: null, adminId: 'a');
        w.adminMail.sent.clear();
        return s.id;
      }

      test('validated AND taken live from « Refusés » in between → 200 live, '
          'no admin e-mail', () async {
        final id = await refusedFor('photos');
        racing.beforeSubmit = () async {
          final r = await w.service.approve(id, from: 'refused', adminId: 'a');
          expect(r.ok, isTrue, reason: '${r.error}');
        };
        final r = await w.provisioning.publish(id);
        expect(r.ok, isTrue);
        expect(r.accepted, isFalse, reason: 'the real state is live');
        expect((r.data! as Map)['status'], 'active');
        expect(w.adminMail.sent, isEmpty);
      });

      test('a SLOW SECOND TAP: it read « never asked », the first tap\'s '
          'request was refused meanwhile → 202 with the REAL state '
          '(refused); the refusal stands, no second admin e-mail', () async {
        final s = await w.salon();
        racing.beforeSubmit = () async {
          // The first tap lands whole, then the admin refuses it — all
          // while the second tap is between its read and its upsert.
          final first = await w.provisioning.publish(s.id);
          expect(first.accepted, isTrue);
          final refused = await w.service.refuse(
            s.id,
            code: 'photos',
            note: null,
            adminId: 'a',
          );
          expect(refused.ok, isTrue, reason: '${refused.error}');
        };
        final second = await w.provisioning.publish(s.id);
        expect(second.accepted, isTrue);
        expect(validationOf(second)['state'], 'refused');
        expect((validationOf(second)['refusal'] as Map)['code'], 'photos');
        expect((await w.validations.get(s.id))!.state, 'refused');
        expect((await w.validations.events(s.id)).map((e) => e.kind), [
          'submitted',
          'refused',
        ]);
        expect(w.adminMail.sent, hasLength(1));
      });

      test('a request that read one refusal never reopens a NEWER one the '
          'owner has not read', () async {
        final id = await refusedFor('photos');
        racing.beforeSubmit = () async {
          // Another device asks again, and the admin refuses that request
          // too — a new decision, at a new time.
          w.now = w.now.add(const Duration(hours: 1));
          final again = await w.provisioning.publish(id);
          expect(validationOf(again)['state'], 'pending');
          w.now = w.now.add(const Duration(hours: 1));
          final r = await w.service.refuse(
            id,
            code: 'unconfirmed',
            note: null,
            adminId: 'a',
          );
          expect(r.ok, isTrue, reason: '${r.error}');
          w.adminMail.sent.clear();
        };
        final stale = await w.provisioning.publish(id);
        expect(stale.accepted, isTrue);
        expect(validationOf(stale)['state'], 'refused');
        expect((validationOf(stale)['refusal'] as Map)['code'], 'unconfirmed');
        expect((await w.validations.get(id))!.state, 'refused');
        expect(w.adminMail.sent, isEmpty);
      });

      test('validated but not yet live in between → 202, the real state '
          '(approved, finishing)', () async {
        final id = await refusedFor('photos');
        racing.beforeSubmit = () async {
          await racing.decide(
            id,
            from: 'refused',
            to: 'approved',
            adminId: 'a',
          );
        };
        final r = await w.provisioning.publish(id);
        expect(r.accepted, isTrue);
        expect(validationOf(r)['state'], 'approved');
        expect(validationOf(r)['wentLive'], isFalse);
        expect(w.adminMail.sent, isEmpty);
      });
    },
  );

  group('the order of the checks', () {
    test('THE DEMO 403 FIRST — before the suspension and the gate; no '
        'request recorded', () async {
      final s = await w.salon(complete: false, email: kDemoProviderEmail);
      await w.providers.setStatus(s.id, 'suspended');
      final r = await w.provisioning.publish(s.id);
      expect(r.error, 'demo_account_locked');
      expect(await w.validations.get(s.id), isNull);
      expect(w.adminMail.sent, isEmpty);
    });

    test('suspended → 403 provider_suspended before the gate; nothing '
        'recorded', () async {
      final s = await w.salon(complete: false);
      await w.providers.setStatus(s.id, 'suspended');
      final r = await w.provisioning.publish(s.id);
      expect(r.error, 'provider_suspended');
      expect(await w.validations.get(s.id), isNull);
      expect(await w.statusOf(s.id), 'suspended');
    });

    test("the gate's 409 → incomplete + missing; nothing recorded, nobody "
        'e-mailed', () async {
      final s = await w.salon(complete: false);
      final r = await w.provisioning.publish(s.id);
      expect(r.error, 'incomplete');
      expect(
        (r.data! as Map)['missing'],
        containsAll(['profile', 'location', 'services', 'photos']),
      );
      expect(await w.validations.get(s.id), isNull);
      expect(w.adminMail.sent, isEmpty);
    });

    test('unknown salon → not_found', () async {
      expect((await w.provisioning.publish('nope')).error, 'not_found');
    });

    test('WITHOUT the validation repository it throws — never the old '
        'direct flip to active', () async {
      final s = await w.salon();
      final legacy = SalonProvisioningService(w.providers, w.auth, w.members);
      await expectLater(legacy.publish(s.id), throwsA(isA<StateError>()));
      expect(await w.statusOf(s.id), 'draft');
    });
  });

  test('the area self-heal is followed by a RE-READ: a stale blob from '
      'updateProfile no longer answers a false incomplete', () async {
    w = ValidationWorld(providers: _StaleBlobProviders());
    final s = await w.salon();
    expect(
      (await w.providers.byId(s.id))!['areaId'],
      isNull,
      reason: 'setup: a legacy salon the self-heal will stamp',
    );

    final r = await w.provisioning.publish(s.id);
    expect(r.ok, isTrue, reason: '${r.error} ${r.data}');
    expect(r.accepted, isTrue);
    expect((await w.providers.byId(s.id))!['areaId'], 'cocody');
  });
}
