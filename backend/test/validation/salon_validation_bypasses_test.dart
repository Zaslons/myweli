import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// Every other way a salon reached `active`, closed to salons MyWeli did not
/// validate (B0.18 — docs/design/salon-go-live-approval.md §3.4), and the
/// two rules that ride with it: erasure (§3.4) and the scheduler (R10).
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  group('« Lever la suspension » (restore)', () {
    test('a salon that is NOT suspended → not_suspended; nothing written, '
        'nothing rebuilt, nothing audited', () async {
      final draft = await w.salon();
      final live = await w.salon();
      await w.validateLive(live.id);
      w.rebuild.reasons.clear();
      final auditBefore = (await w.audit.list()).total;

      for (final id in [draft.id, live.id]) {
        final r = await w.admin.restore('admin_1', id);
        expect(r.ok, isFalse);
        expect(r.error, 'not_suspended');
      }
      expect(await w.statusOf(draft.id), 'draft', reason: 'never published');
      expect(await w.statusOf(live.id), 'active');
      expect(w.rebuild.reasons, isEmpty);
      expect((await w.audit.list()).total, auditBefore);
      expect((await w.admin.restore('admin_1', 'nope')).error, 'not_found');
    });

    test('validated + live + offer + owner → suspend → restore → ACTIVE, '
        '`provider.restore`, audited with the result', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await w.admin.suspend('admin_1', s.id, 'contrôle');
      w.rebuild.reasons.clear();

      final r = await w.admin.restore('admin_1', s.id);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.data, {'status': 'active', 'reason': null});
      expect(await w.isPublic(s.id), isTrue);
      expect(w.rebuild.reasons, ['provider.restore']);
      final row = (await w.audit.list()).items.first;
      expect(row['action'], 'provider.restore');
      expect(row['metadata'], {'status': 'active'});
    });

    test('a SECOND suspension keeps the first `suspended_from` — the salon '
        'still comes back online', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await w.admin.suspend('admin_1', s.id, 'un');
      await w.admin.suspend('admin_1', s.id, 'deux');
      expect(await w.providers.suspendedFrom(s.id), 'active');
      final r = await w.admin.restore('admin_1', s.id);
      expect((r.data! as Map)['status'], 'active');
    });

    group('→ DRAFT, with its reason, and no rebuild', () {
      Future<void> liftsToDraft(String id, String reason) async {
        w.rebuild.reasons.clear();
        final r = await w.admin.restore('admin_1', id);
        expect(r.ok, isTrue, reason: '${r.error}');
        expect(r.data, {'status': 'draft', 'reason': reason});
        expect(await w.statusOf(id), 'draft');
        expect(await w.isPublic(id), isFalse);
        expect(w.rebuild.reasons, isEmpty);
        expect((await w.audit.list()).items.first['metadata'], {
          'status': 'draft',
          'reason': reason,
        });
      }

      test(
        'a never-validated draft (the old suspend → restore bypass)',
        () async {
          final s = await w.salon();
          await w.admin.suspend('admin_1', s.id, null);
          await liftsToDraft(s.id, RestoreReasons.notValidated);
        },
      );

      test('a pending request is not a validation', () async {
        final s = await w.salon();
        await w.provisioning.publish(s.id);
        await w.admin.suspend('admin_1', s.id, null);
        await liftsToDraft(s.id, RestoreReasons.notValidated);
      });

      test('a salon unpublished for non-payment', () async {
        final s = await w.salon();
        await w.validateLive(s.id);
        // Unpublished for non-payment, then paid again but suspended: the
        // mark is still set.
        await w.providers.setStatus(s.id, 'draft');
        await w.subs.update(s.id, unpublishedAt: w.now);
        await w.admin.suspend('admin_1', s.id, null);
        await liftsToDraft(s.id, RestoreReasons.unpaid);
      });

      test('an offer that lapsed while suspended', () async {
        final s = await w.salon();
        await w.validateLive(s.id);
        await w.admin.suspend('admin_1', s.id, null);
        w.now = w.now.add(const Duration(days: 200));
        await liftsToDraft(s.id, RestoreReasons.offerNotLive);
      });

      test("an erased owner's salon", () async {
        final s = await w.salon();
        await w.validateLive(s.id);
        await w.admin.suspend('admin_1', s.id, null);
        await w.members.deleteAllForAccount(s.ownerId);
        await liftsToDraft(s.id, RestoreReasons.noOwner);
      });

      test('a salon suspended before migration 0044 (its earlier state '
          'unknown)', () async {
        final s = await w.salon();
        await w.validateLive(s.id);
        // What an image before 0044 wrote: the status alone.
        (await w.providers.byId(s.id))!['status'] = 'suspended';
        expect(await w.providers.suspendedFrom(s.id), isNull);
        await liftsToDraft(s.id, RestoreReasons.unknownPrior);
      });

      test('a salon that was OFFLINE when suspended stays offline', () async {
        final s = await w.salon();
        await w.validateLive(s.id);
        await w.providers.setStatus(s.id, 'draft');
        await w.admin.suspend('admin_1', s.id, null);
        expect(await w.providers.suspendedFrom(s.id), 'draft');
        await liftsToDraft(s.id, RestoreReasons.unknownPrior);
      });
    });
  });

  group('« Marquer payé » (markPaid)', () {
    Future<void> unpaid(String id) async {
      await w.providers.setStatus(id, 'draft');
      await w.subs.update(id, unpublishedAt: w.now);
      w.rebuild.reasons.clear();
    }

    test('republishes a validated salon unpublished for non-payment', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await unpaid(s.id);
      final r = await w.subscriptions.markPaid(s.id, months: 1);
      expect(r.ok, isTrue);
      expect(await w.statusOf(s.id), 'active');
      expect(w.rebuild.reasons, ['salon.republished']);
    });

    test('does NOT republish an UNVALIDATED salon — the payment is recorded, '
        'the salon stays draft', () async {
      final s = await w.salon();
      await w.subscriptions.chooseOffer(s.ownerId, s.id, 'pro');
      await unpaid(s.id);
      final r = await w.subscriptions.markPaid(s.id, months: 1);
      expect(r.ok, isTrue);
      expect(r.data!['status'], 'paid');
      expect(await w.statusOf(s.id), 'draft');
      expect(r.data!['unpublishedForBilling'], isTrue);
      expect(w.rebuild.reasons, isEmpty);
    });

    test('…nor a pending one', () async {
      final s = await w.salon();
      await w.subscriptions.chooseOffer(s.ownerId, s.id, 'pro');
      await w.provisioning.publish(s.id);
      await unpaid(s.id);
      await w.subscriptions.markPaid(s.id, months: 1);
      expect(await w.statusOf(s.id), 'draft');
    });

    test('does NOT lift a SUSPENSION (the old write went over it)', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await unpaid(s.id);
      await w.admin.suspend('admin_1', s.id, null);
      w.rebuild.reasons.clear();
      final r = await w.subscriptions.markPaid(s.id, months: 1);
      expect(r.ok, isTrue);
      expect(await w.statusOf(s.id), 'suspended');
      expect(w.rebuild.reasons, isEmpty);
    });
  });

  group('account erasure', () {
    ProviderAccountService erasure() => ProviderAccountService(
      w.auth,
      w.providers,
      InMemoryAppointmentRepository(),
      FakeStorageService(),
      w.members,
      validations: w.validations,
    );

    test('a PENDING request leaves the queue', () async {
      final s = await w.salon();
      await w.provisioning.publish(s.id);
      expect((await w.validations.queue('pending')).total, 1);

      final r = await erasure().deleteAccount(s.ownerId);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(await w.validations.get(s.id), isNull);
      expect((await w.validations.queue('pending')).total, 0);
      expect(await w.statusOf(s.id), 'draft');
    });

    test('the admin\'s notes are cleared — on the state row AND the history; '
        'the code stays', () async {
      final s = await w.salon();
      await w.provisioning.publish(s.id);
      await w.service.refuse(
        s.id,
        code: 'unconfirmed',
        note: 'Appelé au 0700000000.',
        adminId: 'a',
      );
      await erasure().deleteAccount(s.ownerId);
      final v = (await w.validations.get(s.id))!;
      expect(v.state, 'refused');
      expect(v.refusalCode, 'unconfirmed');
      expect(v.refusalNote, isNull);
      for (final e in await w.validations.events(s.id)) {
        expect(e.refusalNote, isNull);
      }
      expect(
        (await w.validations.events(s.id)).last.refusalCode,
        'unconfirmed',
      );
    });

    test('a VALIDATED salon keeps its validation — and cannot come back '
        'online without an owner', () async {
      final s = await w.salon();
      await w.validateLive(s.id);
      await erasure().deleteAccount(s.ownerId);
      final v = (await w.validations.get(s.id))!;
      expect(v.state, 'approved');
      expect(v.wentLive, isTrue);
      expect(await w.statusOf(s.id), 'draft');
      await w.admin.suspend('admin_1', s.id, null);
      final r = await w.admin.restore('admin_1', s.id);
      expect((r.data! as Map)['reason'], RestoreReasons.noOwner);
    });
  });

  group('the scheduler (R10)', () {
    test('a salon NOT validated-and-live gets no billing notice — even with '
        'a running trial; once validated and live, the current one', () async {
      final s = await w.salon();
      // An offer chosen on the website first (Q2): its clock runs.
      await w.subscriptions.chooseOffer(s.ownerId, s.id, 'pro');
      await w.provisioning.publish(s.id);
      w.now = w.now.add(const Duration(days: 80)); // J-14 window
      final waiting = await w.scheduler().tick(w.now);
      expect(waiting.notices, 0);
      expect(w.ownerMail.sent, isEmpty);
      expect(w.pushes.sends, isEmpty);

      final r = await w.service.approve(s.id, from: 'pending', adminId: 'a');
      expect(r.ok, isTrue, reason: '${r.error}');
      w.ownerMail.sent.clear();
      w.pushes.sends.clear();
      final live = await w.scheduler().tick(w.now);
      expect(live.notices, 1, reason: 'not burnt while it waited');
      expect(w.ownerMail.sent.single.subject, contains('14 jours'));
    });

    test('a refused salon gets none either', () async {
      final s = await w.salon();
      await w.subscriptions.chooseOffer(s.ownerId, s.id, 'pro');
      await w.provisioning.publish(s.id);
      await w.service.refuse(s.id, code: 'photos', note: null, adminId: 'a');
      w.ownerMail.sent.clear();
      w.pushes.sends.clear();
      w.now = w.now.add(const Duration(days: 95)); // grace
      expect((await w.scheduler().tick(w.now)).notices, 0);
      expect(w.ownerMail.sent, isEmpty);
    });
  });
}
