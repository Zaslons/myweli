import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

import '../support/frozen_clock.dart';

/// docs/design/hygiene-batch9.md §2.5 (B9.6) — the mocks behave like the
/// server, so what the app is built and tested against is the contract:
/// - the daily invitation caps: per salon, then per salon and address, a UTC
///   day on [AppClock] (the counter never reset, and knew neither);
/// - a salon born in the mock starts as the server makes one: empty, at a
///   0 % deposit;
/// - the catalogue, the artists and the member writes act in the session's
///   salon, keep what is written, and refuse another salon's records;
/// - ids never collide under a frozen clock.
void main() {
  final auth = MockAuthService();
  final subs = MockSubscriptionService();

  setUpAll(() {
    serviceLocator.authService = auth;
    serviceLocator.subscriptionService = subs;
  });

  setUp(() async {
    MockData.resetTeam();
    subs.resetForTests();
    await auth.logoutProvider();
  });

  Future<void> signIn(String email) async {
    await auth.requestProviderEmailOtp(email);
    final res = await auth.verifyProviderEmailOtp(
      email,
      MockAuthService.demoOtp,
    );
    expect(res.signedIn, isTrue, reason: 'the scenario: $email');
  }

  /// Jean, owner of provider1, with a Réseau trial — « Ajouter un salon »
  /// is gated on one — adds a second salon. Returns its id.
  Future<String> jeanAddsASalon({String name = 'Salon Neuf'}) async {
    await signIn('jean@salon-excellence.test');
    subs.startTrialIfAbsent('provider1', tier: SalonTier.reseau);
    final added = await MockProService().addSalon(
      businessName: name,
      businessType: BusinessType.salon,
    );
    expect(added.success, isTrue, reason: '${added.error}');
    return added.data!.salonId;
  }

  Service firstServiceOf(String salonId) =>
      MockData.providers.singleWhere((p) => p.id == salonId).services.first;

  group('the daily invitation caps (server T37)', () {
    late MockProTeamService team;
    setUp(() {
      freezeClock(kFixedNow);
      team = MockProTeamService();
    });

    Future<String?> inviteThenRevoke(String email) async {
      final res = await team.inviteMember(
        email: email,
        role: TeamRole.reception,
      );
      if (!res.success) return res.code;
      await team.revokeMember(res.data!.id);
      return null;
    }

    test('per address: the 4th invitation of one person in a day is refused, '
        'the next day it passes', () async {
      expect(await inviteThenRevoke('meme.personne@b.com'), isNull);
      expect(await inviteThenRevoke('meme.personne@b.com'), isNull);
      expect(await inviteThenRevoke('meme.personne@b.com'), isNull);
      expect(
        await inviteThenRevoke('meme.personne@b.com'),
        'invite_rate_limited',
      );

      AppClock.freeze(kFixedNow.add(const Duration(days: 1)));
      expect(
        await inviteThenRevoke('meme.personne@b.com'),
        isNull,
        reason: 'a new UTC day',
      );
    });

    test('one person\'s aliases share the address bucket, the server\'s '
        'way (+tag, Gmail dots, googlemail.com)', () async {
      expect(await inviteThenRevoke('ama@gmail.com'), isNull);
      expect(await inviteThenRevoke('ama+salon@gmail.com'), isNull);
      expect(await inviteThenRevoke('a.ma@googlemail.com'), isNull);
      expect(
        await inviteThenRevoke('A.M.A+x@Gmail.com'),
        'invite_rate_limited',
      );
    });

    test('per salon: the 21st invitation of the day is refused', () async {
      for (var i = 0; i < 20; i++) {
        final res = await team.inviteMember(
          email: 'p$i@b.com',
          role: TeamRole.reception,
        );
        expect(res.success, isTrue, reason: 'invitation ${i + 1}');
      }
      final last = await team.inviteMember(
        email: 'p20@b.com',
        role: TeamRole.reception,
      );
      expect(last.code, 'invite_rate_limited');
    });

    test('the salon\'s bucket is hit first: an invitation the address '
        'refuses still counts there, as on the server', () async {
      for (var i = 0; i < 3; i++) {
        expect(await inviteThenRevoke('x@b.com'), isNull);
      }
      expect(await inviteThenRevoke('x@b.com'), 'invite_rate_limited');
      // 4 attempts so far: 16 more fill the salon's 20.
      for (var i = 0; i < 16; i++) {
        expect(await inviteThenRevoke('y$i@b.com'), isNull, reason: 'y$i');
      }
      expect(await inviteThenRevoke('z@b.com'), 'invite_rate_limited');
    });

    test('the buckets are per salon: another salon has its own', () async {
      final other = await jeanAddsASalon();
      for (var i = 0; i < 3; i++) {
        expect(await inviteThenRevoke('x@b.com'), isNull);
      }
      for (var i = 0; i < 17; i++) {
        expect(await inviteThenRevoke('y$i@b.com'), isNull, reason: 'y$i');
      }
      expect(await inviteThenRevoke('z@b.com'), 'invite_rate_limited');

      await auth.setSelectedProviderSalon(other);
      expect(await inviteThenRevoke('x@b.com'), isNull);
    });

    test('the caps start again with the roster (MockData.resetTeam)', () async {
      for (var i = 0; i < 20; i++) {
        await team.inviteMember(email: 'q$i@b.com', role: TeamRole.reception);
      }
      MockData.resetTeam();
      final res = await team.inviteMember(
        email: 'q20@b.com',
        role: TeamRole.reception,
      );
      expect(res.success, isTrue);
    });
  });

  group('a salon born in the mock is the server\'s new salon: empty, at a '
      '0 % deposit', () {
    test('« Ajouter un salon »', () async {
      final id = await jeanAddsASalon();
      final policy = await MockProService().getDepositPolicy(id);
      expect(policy.data!.depositRequired, isFalse);
      expect(policy.data!.depositPercentage, 0);

      expect((await MockProService().getProviderServices(id)).data, isEmpty);
      expect((await MockProArtistService().getArtists(id)).data, isEmpty);
      final salon = MockData.providers.singleWhere((p) => p.id == id);
      expect(salon.imageUrls, isEmpty);
      expect(salon.rating, 0);
      expect(salon.reviewCount, 0);
      expect(salon.availability.weeklySchedule, isEmpty);
      expect(salon.category, 'salon');
    });

    test('registration', () async {
      await auth.requestProviderEmailOtp('neuf@salon.ci');
      final reg = await auth.registerProviderWithEmail(
        email: 'neuf@salon.ci',
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000099',
        businessName: 'Ongles Neufs',
        businessType: BusinessType.nailSalon,
      );
      expect(reg.success, isTrue, reason: '${reg.error}');
      final id = reg.data!.providerId!;
      final policy = await MockProService().getDepositPolicy(id);
      expect(policy.data!.depositRequired, isFalse);
      expect(policy.data!.depositPercentage, 0);
      final salon = MockData.providers.singleWhere((p) => p.id == id);
      expect(salon.services, isEmpty);
      expect(salon.artists, isEmpty);
      expect(salon.phoneNumber, '+2250700000099');
      expect(salon.category, 'nails');
    });
  });

  group('the bare manager: the catalogue and the artists act in the '
      'session\'s salon', () {
    // Awa is a Gérant of provider1 with no salon of her own.
    test('a service written is kept, and read back', () async {
      await signIn('awa.manager@myweli.test');
      final pro = MockProService();
      final made = await pro.createService('provider1', {
        'name': 'Tresses',
        'price': 15000,
        'durationMinutes': 120,
      });
      expect(made.success, isTrue, reason: '${made.error}');
      final updated = await pro.updateService(made.data!.id, {
        'name': 'Tresses longues',
        'price': 20000,
      });
      expect(updated.success, isTrue, reason: '${updated.error}');
      expect(
        updated.data!.durationMinutes,
        120,
        reason: 'a PATCH keeps what it does not carry',
      );
      expect(
        (await pro.setServiceActive(made.data!.id, false)).success,
        isTrue,
      );

      final read = (await pro.getProviderServices('provider1')).data!;
      final mine = read.singleWhere((s) => s.id == made.data!.id);
      expect(mine.name, 'Tresses longues');
      expect(mine.price, 20000);
      expect(mine.active, isFalse);

      expect((await pro.deleteService(made.data!.id)).success, isTrue);
      expect(
        (await pro.getProviderServices('provider1')).data!.map((s) => s.id),
        isNot(contains(made.data!.id)),
      );
    });

    test(
      'another salon\'s service is « not_found », and stays as it was',
      () async {
        await signIn('awa.manager@myweli.test');
        final pro = MockProService();
        final before = firstServiceOf('provider2');
        expect(before.id, 'service4');

        final update = await pro.updateService('service4', {'name': 'Pris'});
        expect(update.code, 'not_found');
        expect(update.error, 'Introuvable.');
        expect(
          (await pro.setServiceActive('service4', false)).code,
          'not_found',
        );
        expect((await pro.deleteService('service4')).code, 'not_found');

        expect(firstServiceOf('provider2'), before);
      },
    );

    test('another salon\'s artist is « not_found », and stays', () async {
      await signIn('awa.manager@myweli.test');
      final artists = MockProArtistService();
      expect(
        (await artists.updateArtist('artist3', {'name': 'Pris'})).code,
        'not_found',
      );
      expect((await artists.deleteArtist('artist3')).code, 'not_found');
      final provider2 = (await artists.getArtists('provider2')).data!;
      expect(
        provider2.singleWhere((a) => a.id == 'artist3').name,
        isNot('Pris'),
      );
    });

    test('her own salon\'s artist is updated', () async {
      await signIn('awa.manager@myweli.test');
      final artists = MockProArtistService();
      final res = await artists.updateArtist('artist1', {'name': 'Renommé'});
      expect(res.success, isTrue, reason: '${res.error}');
      expect(res.data!.name, 'Renommé');
    });

    test('the salon comes from her membership, not the seeded one', () async {
      // Awa's only row, moved to provider2: the session has no selection,
      // no salon of its own, and no cached membership yet — the server
      // would take that row's salon.
      final i = MockData.teamMembers.indexWhere((m) => m.id == 'mem_manager1');
      final row = MockData.teamMembers[i];
      MockData.teamMembers[i] = TeamMember(
        id: row.id,
        providerId: 'provider2',
        email: row.email,
        role: TeamRole.manager,
        status: TeamMemberStatus.active,
        invitedAt: row.invitedAt,
        accountId: row.accountId,
        acceptedAt: row.acceptedAt,
      );
      await signIn('awa.manager@myweli.test');
      final pro = MockProService();
      expect((await pro.setServiceActive('service4', false)).success, isTrue);
      expect((await pro.setServiceActive('service1', false)).code, 'not_found');
    });
  });

  group('the selected salon, the capabilities and the member writes', () {
    test('a write by id acts in the SELECTED salon', () async {
      final other = await jeanAddsASalon();
      await auth.setSelectedProviderSalon(other);
      final pro = MockProService();
      expect(
        (await pro.updateService('service1', {'name': 'Pris'})).code,
        'not_found',
        reason: 'service1 is provider1\'s, and Jean acts in the new salon',
      );
      final made = await pro.createService(other, {
        'name': 'Pose',
        'price': 8000,
        'durationMinutes': 60,
      });
      expect(
        (await pro.updateService(made.data!.id, {'price': 9000})).success,
        isTrue,
      );
      expect((await pro.getProviderServices(other)).data!.single.price, 9000);
    });

    test('a receptionist may not touch the catalogue: « forbidden », as '
        'on the server', () async {
      await signIn('fatou.reception@myweli.test');
      final pro = MockProService();
      final create = await pro.createService('provider1', {
        'name': 'X',
        'price': 1000,
        'durationMinutes': 30,
      });
      expect(create.code, 'forbidden');
      expect(create.error, 'Action non autorisée pour ce salon.');
      expect(
        (await pro.updateService('service1', {'price': 1})).code,
        'forbidden',
      );
      final artists = MockProArtistService();
      expect(
        (await artists.createArtist('provider1', {'name': 'X'})).code,
        'forbidden',
      );
      expect(
        (await artists.updateArtist('artist1', {'name': 'X'})).code,
        'forbidden',
      );
      expect((await artists.deleteArtist('artist1')).code, 'forbidden');
      expect(firstServiceOf('provider1').price, 5000);
    });

    test('a member write acts in the acting salon: another salon\'s row is '
        '« not_found », and stays', () async {
      final other = await jeanAddsASalon();
      await auth.setSelectedProviderSalon(other);
      final team = MockProTeamService();
      expect((await team.revokeMember('mem_manager1')).code, 'not_found');
      expect(
        (await team.changeRole('mem_manager1', role: TeamRole.reception)).code,
        'not_found',
      );
      expect((await team.resendInvitation('mem_staff1')).code, 'not_found');
      final awa = MockData.teamMembers.singleWhere(
        (m) => m.id == 'mem_manager1',
      );
      expect(awa.status, TeamMemberStatus.active);
      expect(awa.role, TeamRole.manager);
    });
  });

  group('one store: what the Pro writes is what the client reads', () {
    test('a service written shows on the salon, and the reset restores the '
        'seed', () async {
      await signIn('jean@salon-excellence.test');
      final made = await MockProService().createService('provider1', {
        'name': 'Locks',
        'price': 12000,
        'durationMinutes': 90,
      });
      List<String> ids() => MockData.providers
          .singleWhere((p) => p.id == 'provider1')
          .services
          .map((s) => s.id)
          .toList();
      expect(ids(), contains(made.data!.id));

      MockData.resetTeam();
      expect(ids(), ['service1', 'service2', 'service3']);
    });

    test('a deleted artist leaves the salon', () async {
      await signIn('jean@salon-excellence.test');
      expect(
        (await MockProArtistService().deleteArtist('artist2')).success,
        isTrue,
      );
      expect(
        MockData.providers
            .singleWhere((p) => p.id == 'provider1')
            .artists
            .map((a) => a.id),
        isNot(contains('artist2')),
      );
    });
  });

  group('ids never collide under a frozen clock', () {
    test('two services, two artists, two bookings, two salons', () async {
      freezeClock(kFixedNow);
      await signIn('jean@salon-excellence.test');
      final pro = MockProService();
      final s1 = await pro.createService('provider1', {
        'name': 'A',
        'price': 1000,
        'durationMinutes': 30,
      });
      final s2 = await pro.createService('provider1', {
        'name': 'B',
        'price': 1000,
        'durationMinutes': 30,
      });
      expect(s1.data!.id, isNot(s2.data!.id));

      final artists = MockProArtistService();
      final a1 = await artists.createArtist('provider1', {'name': 'A'});
      final a2 = await artists.createArtist('provider1', {'name': 'B'});
      expect(a1.data!.id, isNot(a2.data!.id));

      final at = kFixedNow.add(const Duration(days: 2));
      final b1 = await pro.createManualBooking(
        providerId: 'provider1',
        serviceIds: const ['service1'],
        appointmentDateTime: at,
        clientName: 'A',
      );
      final b2 = await pro.createManualBooking(
        providerId: 'provider1',
        serviceIds: const ['service1'],
        appointmentDateTime: at.add(const Duration(hours: 2)),
        clientName: 'B',
      );
      expect(b1.data!.id, isNot(b2.data!.id));

      final n1 = await jeanAddsASalon(name: 'Un');
      final n2 = await jeanAddsASalon(name: 'Deux');
      expect(n1, isNot(n2));
    });

    test('two invitations: accepting the second accepts THAT one', () async {
      freezeClock(kFixedNow);
      final team = MockProTeamService();
      final first = await team.inviteMember(
        email: 'un@b.com',
        role: TeamRole.reception,
      );
      final second = await team.inviteMember(
        email: 'deux@b.com',
        role: TeamRole.manager,
      );
      expect(first.data!.id, isNot(second.data!.id));

      team.invitationEmail = 'deux@b.com';
      final accepted = await team.acceptInvitation(second.data!.id);
      expect(accepted.data!.email, 'deux@b.com');
      expect(accepted.data!.role, TeamRole.manager);
    });
  });
}
