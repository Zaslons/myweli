import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/site/site_rebuild_notifier.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:myweli_backend/src/subscription/subscription_scheduler.dart';
import 'package:test/test.dart';

class _MockPush extends Mock implements PushService {}

/// Records what it was asked to do, so a call site can be observed.
class _RecordingNotifier implements SiteRebuildNotifier {
  final reasons = <String>[];
  @override
  Future<void> requestRebuild(String reason) async => reasons.add(reason);
}

class _RecordingEmail implements EmailProvider {
  final List<({String to, String subject})> sent = [];

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    sent.add((to: to, subject: subject));
    return (ok: true, providerMessageId: 'm1', error: null);
  }
}

/// R2a — the pricing pivot's server core (team-access-r2a-offers.md):
/// state boundaries, the one-trial rule, seats, markPaid + republish, the
/// legacy bridge, the scheduler's idempotent warnings + gated enforcement.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository memberships;
  late InMemorySalonSubscriptionRepository subs;
  late InMemoryProvidersRepository providers;
  late MembershipService memberService;
  late _RecordingNotifier rebuild;
  DateTime now = DateTime.utc(2026, 7, 11, 12);

  SalonSubscriptionService service() => SalonSubscriptionService(
    subs,
    memberService,
    memberships,
    providers,
    auth,
    clock: () => now,
    rebuild: rebuild,
  );

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
    memberships = InMemoryMembershipRepository();
    subs = InMemorySalonSubscriptionRepository();
    providers = InMemoryProvidersRepository();
    memberService = MembershipService(memberships, auth);
    rebuild = _RecordingNotifier();
    now = DateTime.utc(2026, 7, 11, 12);
  });

  Future<String> registerOwner({String providerId = 'p1'}) async {
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250500000041',
      email: 'owner@x.pro',
      authProvider: 'google',
      googleSub: 'sub-own',
      providerId: providerId,
    );
    final id = reg.provider!.id;
    await memberships.ensureOwner(
      providerId: providerId,
      accountId: id,
      email: 'owner@x.pro',
    );
    return id;
  }

  group('chooseOffer + state derivation', () {
    test(
      'first choice starts the ONE trial; switches keep the clock',
      () async {
        final owner = await registerOwner();
        final r = await service().chooseOffer(owner, 'p1', 'pro');
        expect(r.ok, isTrue);
        expect(r.data!['status'], 'trial');
        expect(r.data!['tier'], 'pro');
        final firstEnd = r.data!['trialEndsAt'];

        // Ten days later, switch to business: same clock, more seats.
        now = now.add(const Duration(days: 10));
        final switched = await service().chooseOffer(owner, 'p1', 'business');
        expect(switched.ok, isTrue);
        expect(switched.data!['tier'], 'business');
        expect(switched.data!['trialEndsAt'], firstEnd);
        expect((switched.data!['seats'] as Map)['cap'], 15);
      },
    );

    test('invalid tier → invalid_tier; non-owner → forbidden', () async {
      final owner = await registerOwner();
      expect(
        (await service().chooseOffer(owner, 'p1', 'gold')).error,
        'invalid_tier',
      );
      expect(
        (await service().chooseOffer('ghost', 'p1', 'pro')).error,
        'forbidden',
      );
    });

    test('the full lifecycle: trial → grace → expired; re-choice after '
        'expiry → trial_used', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');

      now = now.add(const Duration(days: 89));
      expect((await service().stateFor('p1'))!['status'], 'trial');

      now = now.add(const Duration(days: 2)); // past trialEnd (+90d)
      expect((await service().stateFor('p1'))!['status'], 'grace');

      now = now.add(const Duration(days: 7)); // past grace
      expect((await service().stateFor('p1'))!['status'], 'expired');

      final again = await service().chooseOffer(owner, 'p1', 'business');
      expect(again.ok, isFalse);
      expect(again.error, 'trial_used');
    });

    test('seats count invited + active members, owner included', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');
      final state = await service().stateFor('p1');
      expect((state!['seats'] as Map)['used'], 1); // the owner row
      expect((state['seats'] as Map)['cap'], 5);
    });

    test(
      'no offer chosen → stateFor null + hasLiveOffer false (setup state)',
      () async {
        await registerOwner();
        expect(await service().stateFor('p1'), isNull);
        expect(await service().hasLiveOffer('p1'), isFalse);
      },
    );
  });

  group('markPaid', () {
    test('extends from max(now, paidUntil), reopens notices, republishes a '
        'billing-unpublished salon when the gate passes', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');

      // Fabricate a publish-ready salon doc + billing-unpublish state.
      final salon = await providers.createSalon(
        name: 'Salon X',
        category: 'salon',
        phoneNumber: '+22500',
      );
      final realId = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: realId,
        accountId: owner,
        email: 'owner@x.pro',
      );
      await service().chooseOffer(owner, realId, 'pro');
      await providers.updateProfile(realId, {
        'description': 'desc',
        'address': 'Cocody',
        'commune': 'Cocody',
        'latitude': 5.3,
        'longitude': -4.0,
        'imageUrls': ['a', 'b', 'c'],
        'services': [
          {'id': 's1', 'name': 'A', 'active': true},
          {'id': 's2', 'name': 'B', 'active': true},
          {'id': 's3', 'name': 'C', 'active': true},
        ],
        'availability': {
          'weeklySchedule': {
            '0': [
              {'startTime': '09:00', 'endTime': '18:00'},
            ],
          },
        },
      });
      await providers.setStatus(realId, 'draft');
      await subs.update(realId, unpublishedAt: now);
      await subs.markNoticeIfNew(realId, 'grace');

      final r = await service().markPaid(realId, months: 2);
      expect(r.ok, isTrue);
      expect(r.data!['status'], 'paid');
      expect(r.data!['unpublishedForBilling'], isFalse);
      final doc = await providers.byId(realId);
      expect(doc!['status'], 'active');
      expect(
        rebuild.reasons,
        ['salon.republished'],
        reason:
            'the slug re-entered the prebuilt set — without this fire the '
            'republished salon keeps 404ing until an unrelated deploy',
      );
      // The notice cycle reopened.
      expect(await subs.markNoticeIfNew(realId, 'grace'), isTrue);
    });

    test('markPaid on an unpublished salon whose gate FAILS asks for NO '
        'rebuild — it stays draft', () async {
      // The mutation this catches: the fire hoisted out of the gate check
      // but still inside the unpublishedAt branch — every test with a
      // publish-ready salon stays green while an incomplete salon would
      // trigger a build for a page that stays 404.
      final owner = await registerOwner();
      final salon = await providers.createSalon(
        name: 'Salon Z',
        category: 'salon',
        phoneNumber: '+22502',
      );
      final id = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: id,
        accountId: owner,
        email: 'owner@x.pro',
      );
      await service().chooseOffer(owner, id, 'pro');
      // Billing-unpublished, and INCOMPLETE: the bare createSalon doc fails
      // the publish gate (no description, no photos, no schedule).
      await subs.update(id, unpublishedAt: now);

      final r = await service().markPaid(id, months: 1);
      expect(r.ok, isTrue);
      expect((await providers.byId(id))!['status'], 'draft');
      expect(rebuild.reasons, isEmpty);
    });

    test('markPaid with nothing unpublished asks for NO rebuild', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');
      final r = await service().markPaid('p1', months: 1);
      expect(r.ok, isTrue);
      expect(
        rebuild.reasons,
        isEmpty,
        reason: 'the set did not change, so nothing needs rebuilding',
      );
    });

    test('bounds: months outside 1..24 → invalid_input; unknown salon → '
        'not_found', () async {
      expect((await service().markPaid('p1', months: 0)).error, isNotNull);
      expect((await service().markPaid('nope', months: 2)).error, 'not_found');
    });
  });

  group('legacy /me/subscription bridge', () {
    test(
      'a salon on trial maps to the OLD shape (tier pro, status trial)',
      () async {
        final owner = await registerOwner();
        await service().chooseOffer(owner, 'p1', 'business');
        final legacy = await service().legacySubscriptionFor(owner);
        expect(legacy!.tier, 'pro'); // business maps into the legacy enum
        expect(legacy.status, 'trial');
        expect(legacy.trialDaysLeft, 90);
      },
    );

    test('expired salon → free', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');
      now = now.add(const Duration(days: 100));
      expect((await service().legacySubscriptionFor(owner))!.tier, 'free');
    });

    test('R6: an explicit salonId reflects THAT salon; per-salon clocks '
        'stay independent', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');
      // A second owned salon, offer chosen 0 days ago vs p1's later state.
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: owner,
        email: 'owner@x.pro',
      );
      now = now.add(const Duration(days: 100)); // p1's trial expires
      await service().chooseOffer(owner, 'p2', 'business');

      // The fallback (scalar p1) reads the EXPIRED salon…
      expect((await service().legacySubscriptionFor(owner))!.tier, 'free');
      // …the explicit selection reads p2's fresh trial.
      final p2 = await service().legacySubscriptionFor(owner, salonId: 'p2');
      expect(p2!.tier, 'pro');
      expect(p2.status, 'trial');
      // A forged selection → null (the route 403s).
      expect(
        await service().legacySubscriptionFor(owner, salonId: 'p_forged'),
        isNull,
      );
    });

    test('no salon → the old account-age derivation', () async {
      // The repo stamps createdAt with the REAL clock — align the service's.
      now = DateTime.now().toUtc();
      final bare = await auth.register(
        businessName: 'Y',
        businessType: 'salon',
        phoneNumber: '+2250500000042',
        email: 'y@x.pro',
        authProvider: 'google',
        googleSub: 'sub-y',
      );
      final legacy = await service().legacySubscriptionFor(bare.provider!.id);
      expect(legacy!.status, 'trial'); // fresh account age
    });
  });

  group('scheduler', () {
    late _RecordingEmail email;
    late _MockPush push;

    SubscriptionScheduler scheduler({bool enforce = false}) =>
        SubscriptionScheduler(
          subs,
          memberships,
          providers,
          email,
          push,
          enforce: enforce,
          rebuild: rebuild,
        );

    setUp(() {
      email = _RecordingEmail();
      push = _MockPush();
      when(
        () => push.sendToUser(
          any(),
          title: any(named: 'title'),
          body: any(named: 'body'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => 1);
    });

    Future<String> liveSalon() async {
      final owner = await registerOwner();
      final salon = await providers.createSalon(
        name: 'Salon X',
        category: 'salon',
        phoneNumber: '+22500',
      );
      final id = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: id,
        accountId: owner,
        email: 'owner@x.pro',
      );
      await providers.setStatus(id, 'active');
      await service().chooseOffer(owner, id, 'pro');
      return id;
    }

    test('warnings fire once per kind (J-14 → J-7 → J-1 → grace)', () async {
      await liveSalon();
      now = now.add(const Duration(days: 80)); // 10 days left → J-14 window
      var r = await scheduler().tick(now);
      expect(r.notices, 1);
      expect(email.sent.single.subject, contains('14 jours'));

      // Same day again → idempotent.
      r = await scheduler().tick(now);
      expect(r.notices, 0);

      now = now.add(const Duration(days: 5)); // 5 left → J-7
      expect((await scheduler().tick(now)).notices, 1);
      now = now.add(const Duration(days: 5)); // past end → grace
      expect((await scheduler().tick(now)).notices, 1);
      expect(email.sent.last.subject, contains('grâce'));
    });

    test(
      'enforcement OFF: past grace → warnings only, salon stays live',
      () async {
        final id = await liveSalon();
        now = now.add(const Duration(days: 100)); // way past grace
        final r = await scheduler().tick(now);
        expect(r.unpublished, 0);
        expect((await providers.byId(id))!['status'], 'active');
        expect(
          rebuild.reasons,
          isEmpty,
          reason: 'nothing was unpublished, so nothing needs rebuilding',
        );
      },
    );

    test('enforcement ON: past grace → unpublished (draft) + notice; '
        'idempotent on the next tick', () async {
      final id = await liveSalon();
      now = now.add(const Duration(days: 100));
      final r = await scheduler(enforce: true).tick(now);
      expect(r.unpublished, 1);
      expect((await providers.byId(id))!['status'], 'draft');
      expect(email.sent.last.subject, contains('plus visible'));
      expect(
        rebuild.reasons,
        ['salon.unpublished'],
        reason:
            'the slug left the prebuilt set — without this the stale page '
            'keeps serving a salon that is no longer live',
      );

      final again = await scheduler(enforce: true).tick(now);
      expect(again.unpublished, 0);
      expect(again.notices, 0);
      expect(rebuild.reasons, hasLength(1), reason: 'idempotent tick');
    });

    test('TWO expired salons in one tick → exactly ONE rebuild', () async {
      // Once per tick, not per salon: firing inside the loop would lean on
      // the notifier cooldown to coalesce, semantics this fire must not
      // depend on.
      final a = await liveSalon();
      // A second owner, registered directly: `registerOwner` hardcodes the
      // email and googleSub, and a second call collides with the first.
      final regB = await auth.register(
        businessName: 'Y',
        businessType: 'salon',
        phoneNumber: '+2250500000042',
        email: 'owner2@x.pro',
        authProvider: 'google',
        googleSub: 'sub-own2',
        providerId: 'p2',
      );
      final owner2 = regB.provider!.id;
      final salon2 = await providers.createSalon(
        name: 'Salon Y',
        category: 'salon',
        phoneNumber: '+22501',
      );
      final b = salon2['id'] as String;
      await memberships.ensureOwner(
        providerId: b,
        accountId: owner2,
        email: 'owner2@x.pro',
      );
      await providers.setStatus(b, 'active');
      await service().chooseOffer(owner2, b, 'pro');

      now = now.add(const Duration(days: 100));
      final r = await scheduler(enforce: true).tick(now);
      expect(r.unpublished, 2);
      expect((await providers.byId(a))!['status'], 'draft');
      expect((await providers.byId(b))!['status'], 'draft');
      expect(rebuild.reasons, ['salon.unpublished']);
    });
  });

  group('createIfAbsent (in-memory)', () {
    test('creates when absent; NEVER replaces an existing row', () async {
      final t1 = now.add(const Duration(days: 90));
      final created = await subs.createIfAbsent(
        providerId: 'px',
        tier: 'pro',
        trialEndsAt: t1,
      );
      expect(created.tier, 'pro');
      expect(created.trialEndsAt, t1);
      await subs.update('px', paidUntil: now.add(const Duration(days: 30)));

      // A second writer with different values gets the FIRST row back —
      // tier, clock and paid coverage all intact.
      final again = await subs.createIfAbsent(
        providerId: 'px',
        tier: 'reseau',
        trialEndsAt: now.add(const Duration(days: 400)),
      );
      expect(again.tier, 'pro');
      expect(again.trialEndsAt, t1);
      expect(again.paidUntil, now.add(const Duration(days: 30)));
      final stored = (await subs.byProvider('px'))!;
      expect(stored.tier, 'pro');
      expect(stored.trialEndsAt, t1);
      expect(await subs.all(), hasLength(1));
    });
  });

  /// The companion path (docs/design/pro-companion-path.md §3.1, §8): the
  /// Pro app no longer offers a choice, so a salon's ONE trial starts at its
  /// first successful publish when no offer row exists.
  group('publish starts the trial (companion path)', () {
    late String owner;

    SalonProvisioningService provisioning() => SalonProvisioningService(
      providers,
      auth,
      memberships,
      subscriptions: service(),
      rebuild: rebuild,
    );

    const completeProfile = <String, dynamic>{
      'description': 'desc',
      'address': 'Cocody',
      'commune': 'Cocody',
      'latitude': 5.3,
      'longitude': -4.0,
      'imageUrls': ['a', 'b', 'c'],
      'services': [
        {'id': 's1', 'name': 'A', 'active': true},
        {'id': 's2', 'name': 'B', 'active': true},
        {'id': 's3', 'name': 'C', 'active': true},
      ],
      'availability': {
        'weeklySchedule': {
          '0': [
            {'startTime': '09:00', 'endTime': '18:00'},
          ],
        },
      },
    };

    /// A draft salon owned by [ownerId] — publish-ready unless
    /// [complete] is false.
    Future<String> ownedSalon(
      String ownerId, {
      bool complete = true,
      String email = 'owner@x.pro',
    }) async {
      final salon = await providers.createSalon(
        name: 'Salon X',
        category: 'salon',
        phoneNumber: '+22500',
      );
      final id = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: id,
        accountId: ownerId,
        email: email,
      );
      if (complete) await providers.updateProfile(id, completeProfile);
      return id;
    }

    setUp(() async {
      owner = await registerOwner();
    });

    test('no offer row + complete → active, ONE trial on pro for 90 days, '
        'one rebuild', () async {
      final id = await ownedSalon(owner);
      expect(await subs.byProvider(id), isNull, reason: 'setup state');

      final r = await provisioning().publish(id);
      expect(r.ok, isTrue, reason: '${r.error} ${r.data}');
      expect((r.data! as Map)['status'], 'active');
      final row = (await subs.byProvider(id))!;
      expect(row.tier, 'pro');
      expect(row.trialEndsAt, now.add(const Duration(days: 90)));
      final state = (await service().stateFor(id))!;
      expect(state['status'], 'trial');
      expect(rebuild.reasons, ['salon.published']);
    });

    test(
      'a re-publish is idempotent: no second trial, no second rebuild',
      () async {
        final id = await ownedSalon(owner);
        await provisioning().publish(id);
        final firstEnd = (await subs.byProvider(id))!.trialEndsAt;

        now = now.add(const Duration(days: 10));
        final again = await provisioning().publish(id);
        expect(again.ok, isTrue);
        expect((await subs.byProvider(id))!.trialEndsAt, firstEnd);
        expect(rebuild.reasons, hasLength(1));
      },
    );

    test('no offer row + INCOMPLETE → incomplete WITHOUT `offer`, and no '
        'trial is minted', () async {
      final id = await ownedSalon(owner, complete: false);
      final r = await provisioning().publish(id);
      expect(r.ok, isFalse);
      expect(r.error, 'incomplete');
      final missing = (r.data! as Map)['missing'] as List;
      expect(missing, containsAll(['profile', 'services', 'photos']));
      expect(
        missing,
        isNot(contains('offer')),
        reason:
            'the app may not send a setup salon anywhere to choose — the '
            'trial starts at publish, so `offer` is not a missing step',
      );
      expect(
        await subs.byProvider(id),
        isNull,
        reason: 'minting a trial still takes a complete salon',
      );
      expect(rebuild.reasons, isEmpty);
    });

    test(
      'an EXPIRED offer → incomplete [offer]; never a second trial',
      () async {
        final id = await ownedSalon(owner);
        await service().chooseOffer(owner, id, 'business');
        final before = (await subs.byProvider(id))!;

        now = now.add(const Duration(days: 100)); // past trial + grace
        final r = await provisioning().publish(id);
        expect(r.ok, isFalse);
        expect(r.error, 'incomplete');
        expect((r.data! as Map)['missing'], ['offer']);
        final after = (await subs.byProvider(id))!;
        expect(after.tier, 'business');
        expect(after.trialEndsAt, before.trialEndsAt, reason: 'one trial');
        expect((await providers.byId(id))!['status'], 'draft');
        expect(rebuild.reasons, isEmpty);
      },
    );

    test(
      'a web choice made FIRST is untouched — its tier and its clock',
      () async {
        final id = await ownedSalon(owner);
        await service().chooseOffer(owner, id, 'business');
        final chosen = (await subs.byProvider(id))!;

        now = now.add(const Duration(days: 3));
        final r = await provisioning().publish(id);
        expect(r.ok, isTrue);
        final row = (await subs.byProvider(id))!;
        expect(row.tier, 'business');
        expect(row.trialEndsAt, chosen.trialEndsAt);
      },
    );

    test("a Réseau owner's SECOND salon starts on reseau", () async {
      final first = await ownedSalon(owner);
      await service().chooseOffer(owner, first, 'reseau');
      final second = await ownedSalon(owner);

      final r = await provisioning().publish(second);
      expect(r.ok, isTrue);
      final row = (await subs.byProvider(second))!;
      expect(row.tier, 'reseau');
      expect(row.trialEndsAt, now.add(const Duration(days: 90)));
    });

    test('the Réseau default needs the OWNER\'s other salon on a LIVE '
        'Réseau offer — expired → pro', () async {
      final first = await ownedSalon(owner);
      await service().chooseOffer(owner, first, 'reseau');
      now = now.add(const Duration(days: 100)); // first's offer expired
      final second = await ownedSalon(owner);

      await provisioning().publish(second);
      expect((await subs.byProvider(second))!.tier, 'pro');
    });

    test('…and a live NON-Réseau offer elsewhere → pro', () async {
      final first = await ownedSalon(owner);
      await service().chooseOffer(owner, first, 'business');
      final second = await ownedSalon(owner);

      await provisioning().publish(second);
      expect((await subs.byProvider(second))!.tier, 'pro');
    });

    test(
      "…and ANOTHER account's live Réseau → pro (no cross-account read)",
      () async {
        final reg = await auth.register(
          businessName: 'Y',
          businessType: 'salon',
          phoneNumber: '+2250500000042',
          email: 'owner2@x.pro',
          authProvider: 'google',
          googleSub: 'sub-own2',
        );
        final owner2 = reg.provider!.id;
        final theirs = await ownedSalon(owner2, email: 'owner2@x.pro');
        await service().chooseOffer(owner2, theirs, 'reseau');
        final mine = await ownedSalon(owner);

        await provisioning().publish(mine);
        expect((await subs.byProvider(mine))!.tier, 'pro');
      },
    );

    test('…and a Réseau salon the owner only MANAGES → pro (owned, not '
        'joined)', () async {
      final reg = await auth.register(
        businessName: 'Y',
        businessType: 'salon',
        phoneNumber: '+2250500000042',
        email: 'owner2@x.pro',
        authProvider: 'google',
        googleSub: 'sub-own2',
      );
      final owner2 = reg.provider!.id;
      final theirs = await ownedSalon(owner2, email: 'owner2@x.pro');
      await service().chooseOffer(owner2, theirs, 'reseau');
      final inv = await memberships.invite(
        providerId: theirs,
        email: 'owner@x.pro',
        role: 'manager',
        expiresAt: now.add(const Duration(days: 7)),
      );
      await memberships.activate(inv.id, owner);
      final mine = await ownedSalon(owner);

      await provisioning().publish(mine);
      expect((await subs.byProvider(mine))!.tier, 'pro');
    });

    test("…and a Réseau salon linked ONLY by the account's scalar (a legacy "
        'owner with no membership row there) → reseau', () async {
      // Owned = the scalar link ∪ active owner rows — this pins the scalar
      // half, which every test above reaches through a membership row.
      final sibling = await providers.createSalon(
        name: 'Salon Historique',
        category: 'salon',
        phoneNumber: '+22501',
      );
      final siblingId = sibling['id'] as String;
      final reg = await auth.register(
        businessName: 'Z',
        businessType: 'salon',
        phoneNumber: '+2250500000043',
        email: 'legacy@x.pro',
        authProvider: 'google',
        googleSub: 'sub-legacy',
        providerId: siblingId,
      );
      final legacy = reg.provider!.id;
      await subs.create(
        providerId: siblingId,
        tier: 'reseau',
        trialEndsAt: now.add(const Duration(days: 90)),
      );
      expect(
        await memberships.listForProvider(siblingId),
        isEmpty,
        reason: 'the scalar is the only link',
      );
      final second = await ownedSalon(legacy, email: 'legacy@x.pro');

      final r = await provisioning().publish(second);
      expect(r.ok, isTrue);
      expect((await subs.byProvider(second))!.tier, 'reseau');
    });

    test('…and a live Réseau salon whose owner row was REVOKED → pro '
        '(active owner rows only)', () async {
      final first = await ownedSalon(owner);
      await service().chooseOffer(owner, first, 'reseau');
      final ownerRow = (await memberships.listForProvider(
        first,
      )).singleWhere((m) => m.role == 'owner');
      await memberships.revoke(ownerRow.id);
      final second = await ownedSalon(owner);

      await provisioning().publish(second);
      expect((await subs.byProvider(second))!.tier, 'pro');
    });

    test(
      'an ALREADY-ACTIVE salon with no offer row gets its trial at '
      'publish — and asks for no rebuild (the public set is unchanged)',
      () async {
        // A legacy salon live before the pricing pivot: the first successful
        // publish is the start, whatever the status was (spec §3.1).
        final id = await ownedSalon(owner);
        await providers.setStatus(id, 'active');

        final r = await provisioning().publish(id);
        expect(r.ok, isTrue);
        final row = (await subs.byProvider(id))!;
        expect(row.tier, 'pro');
        expect(row.trialEndsAt, now.add(const Duration(days: 90)));
        expect((await providers.byId(id))!['status'], 'active');
        expect(rebuild.reasons, isEmpty);
      },
    );

    test('A SUSPENDED salon with no offer row → provider_suspended: no '
        'trial, still suspended, no rebuild', () async {
      // T17: only the audited admin restore lifts a suspension. Publish
      // flipped every non-active status to `active`, so one owner call undid
      // it — and since the companion path would also have minted a trial.
      final id = await ownedSalon(owner);
      await providers.setStatus(id, 'suspended');

      final r = await provisioning().publish(id);
      expect(r.ok, isFalse);
      expect(r.error, 'provider_suspended');
      expect(
        await subs.byProvider(id),
        isNull,
        reason: 'a suspended salon writes no billing state',
      );
      expect((await providers.byId(id))!['status'], 'suspended');
      expect(rebuild.reasons, isEmpty);
    });

    test('…and with a LIVE offer → refused too (the pre-companion '
        'un-suspend)', () async {
      final id = await ownedSalon(owner);
      await service().chooseOffer(owner, id, 'pro');
      await providers.setStatus(id, 'suspended');

      final r = await provisioning().publish(id);
      expect(r.error, 'provider_suspended');
      expect((await providers.byId(id))!['status'], 'suspended');
      expect(rebuild.reasons, isEmpty);
    });

    test('THE DEMO SALON: its lock answers BEFORE the trial start — no row, '
        'still draft, no rebuild', () async {
      // T69 + T54: the publish-time start runs only after the demo lock. A
      // lock moved below the start would refuse the publish but leave a
      // trial behind on the public-credential salon.
      final id = await ownedSalon('acc-demo', email: kDemoProviderEmail);
      expect(await subs.byProvider(id), isNull);

      final r = await provisioning().publish(id);
      expect(r.ok, isFalse);
      expect(r.error, 'demo_account_locked');
      expect(await subs.byProvider(id), isNull, reason: 'no trial minted');
      expect((await providers.byId(id))!['status'], 'draft');
      expect(rebuild.reasons, isEmpty);
    });

    test('insert-if-absent under a race: a web choice that lands between '
        "publish's read and its insert keeps its tier", () async {
      final racing = _RacingSubscriptions();
      subs = racing;
      final id = await ownedSalon(owner);
      racing.racer = (
        tier: 'business',
        trialEndsAt: now.add(const Duration(days: 90)),
      );

      final r = await provisioning().publish(id);
      expect(r.ok, isTrue);
      expect((await subs.byProvider(id))!.tier, 'business');
    });

    test('…and the row that won is RE-CHECKED: a non-live winner keeps the '
        'salon draft', () async {
      // Not reachable through today's writers (a new row is always a fresh
      // trial) — which is exactly why the re-check needs its own test: a
      // publish that assumed its insert won would go live on a row it
      // never wrote.
      final racing = _RacingSubscriptions();
      subs = racing;
      final id = await ownedSalon(owner);
      racing.racer = (
        tier: 'pro',
        trialEndsAt: now.subtract(const Duration(days: 30)),
      );

      final r = await provisioning().publish(id);
      expect(r.ok, isFalse);
      expect((r.data! as Map)['missing'], ['offer']);
      expect((await providers.byId(id))!['status'], 'draft');
      expect(rebuild.reasons, isEmpty);
    });
  });

  /// T69 (docs/design/pro-companion-path.md §3.2): the demo credential is
  /// public and the web dashboard accepts it.
  group('THE DEMO SALON CANNOT CHOOSE OR SWITCH ITS OFFER', () {
    Future<String> demoSalon() async {
      final salon = await providers.createSalon(
        name: 'Salon Démo MyWeli',
        category: 'salon',
        phoneNumber: '+2250700000100',
      );
      final id = salon['id'] as String;
      await memberships.ensureOwner(
        providerId: id,
        accountId: 'acc-demo',
        email: kDemoProviderEmail,
      );
      return id;
    }

    test('a first choice → demo_account_locked, no row written', () async {
      final id = await demoSalon();
      final r = await service().chooseOffer('acc-demo', id, 'reseau');
      expect(r.ok, isFalse);
      expect(r.error, 'demo_account_locked');
      expect(await subs.byProvider(id), isNull);
    });

    test('a switch → demo_account_locked, the tier stays', () async {
      final id = await demoSalon();
      await subs.create(
        providerId: id,
        tier: 'pro',
        trialEndsAt: now.add(const Duration(days: 90)),
      );
      final r = await service().chooseOffer('acc-demo', id, 'reseau');
      expect(r.error, 'demo_account_locked');
      expect((await subs.byProvider(id))!.tier, 'pro');
    });

    test('the capability check still answers first for a stranger', () async {
      final id = await demoSalon();
      final r = await service().chooseOffer('ghost', id, 'pro');
      expect(r.error, 'forbidden');
    });

    test('an ordinary owner is not caught by the lock', () async {
      final owner = await registerOwner();
      final r = await service().chooseOffer(owner, 'p1', 'reseau');
      expect(r.ok, isTrue);
    });
  });
}

/// Simulates another request (a web choice) inserting the row between
/// publish's `stateFor` read and its `createIfAbsent` — the window the
/// insert-if-absent write exists for.
class _RacingSubscriptions extends InMemorySalonSubscriptionRepository {
  ({String tier, DateTime trialEndsAt})? racer;

  @override
  Future<SalonSubscriptionRow> createIfAbsent({
    required String providerId,
    required String tier,
    required DateTime trialEndsAt,
  }) async {
    final r = racer;
    if (r != null) {
      await create(
        providerId: providerId,
        tier: r.tier,
        trialEndsAt: r.trialEndsAt,
      );
    }
    return super.createIfAbsent(
      providerId: providerId,
      tier: tier,
      trialEndsAt: trialEndsAt,
    );
  }
}
