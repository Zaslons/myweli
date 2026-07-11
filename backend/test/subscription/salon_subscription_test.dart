import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:myweli_backend/src/subscription/subscription_scheduler.dart';
import 'package:test/test.dart';

class _MockPush extends Mock implements PushService {}

class _RecordingEmail implements EmailProvider {
  final List<({String to, String subject})> sent = [];

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
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
  DateTime now = DateTime.utc(2026, 7, 11, 12);

  SalonSubscriptionService service() => SalonSubscriptionService(
    subs,
    memberService,
    memberships,
    providers,
    auth,
    clock: () => now,
  );

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    memberships = InMemoryMembershipRepository();
    subs = InMemorySalonSubscriptionRepository();
    providers = InMemoryProvidersRepository();
    memberService = MembershipService(memberships, auth);
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
      // The notice cycle reopened.
      expect(await subs.markNoticeIfNew(realId, 'grace'), isTrue);
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
        expect(legacy.tier, 'pro'); // business maps into the legacy enum
        expect(legacy.status, 'trial');
        expect(legacy.trialDaysLeft, 90);
      },
    );

    test('expired salon → free', () async {
      final owner = await registerOwner();
      await service().chooseOffer(owner, 'p1', 'pro');
      now = now.add(const Duration(days: 100));
      expect((await service().legacySubscriptionFor(owner)).tier, 'free');
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
      expect(legacy.status, 'trial'); // fresh account age
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

      final again = await scheduler(enforce: true).tick(now);
      expect(again.unpublished, 0);
      expect(again.notices, 0);
    });
  });

  group('publish offer gate', () {
    test('publish without a live offer → incomplete with the offer key; '
        'with one → active', () async {
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
      await providers.updateProfile(id, {
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

      final provisioning = SalonProvisioningService(
        providers,
        auth,
        memberships,
        subscriptions: service(),
      );
      final blocked = await provisioning.publish(id);
      expect(blocked.ok, isFalse);
      expect(blocked.error, 'incomplete');
      expect((blocked.data! as Map)['missing'], contains('offer'));

      await service().chooseOffer(owner, id, 'pro');
      final ok = await provisioning.publish(id);
      expect(ok.ok, isTrue);
    });
  });
}
