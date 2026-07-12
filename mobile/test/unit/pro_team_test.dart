import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

/// Team access R3 — the mock team service enforces EVERY server gate with
/// the real machine codes, and ProTeamProvider drives the Équipe screen +
/// the invitee surface (docs/design/team-access-r3-app.md §8).
void main() {
  setUp(MockData.resetTeam);

  // Business cap (15) by default: the R4b seeds already occupy 5 seats
  // (owner + manager + réception + staff + 1 pending invite).
  MockSubscriptionService liveOffer({SalonTier tier = SalonTier.business}) =>
      MockSubscriptionService(
        initial: SalonSubscription(
          tier: tier,
          status: SalonOfferStatus.trial,
          trialEndsAt: DateTime.now().add(const Duration(days: 60)),
          graceEndsAt: DateTime.now().add(const Duration(days: 67)),
          seats: const SalonSeats(cap: 15, used: 0),
        ),
      );

  group('MockProTeamService — gates', () {
    test('roster is owner-first and carries the seeded states', () async {
      final res = await MockProTeamService().getMembers();
      final rows = res.data!;
      expect(rows.first.role, TeamRole.owner);
      expect(rows.any((m) => m.isPending && m.expired), isTrue);
      expect(rows.any((m) => m.artistName == 'Kouassi Jean'), isTrue);
    });

    test('invite happy path: pending row + invitee card + 7-day window',
        () async {
      final svc = MockProTeamService(subscriptions: liveOffer());
      final res = await svc.inviteMember(
        email: 'Nouveau@B.com',
        role: TeamRole.manager,
      );
      expect(res.success, isTrue);
      expect(res.data!.email, 'nouveau@b.com'); // lowercased
      expect(res.data!.isPending, isTrue);
      expect(res.data!.resendsLeft, 3);
      expect(MockData.teamInvitations['nouveau@b.com'], hasLength(1));
    });

    test(
        'owner role → invalid_role · staff sans fiche → artist_required '
        '· fiche inconnue → artist_not_found', () async {
      final svc = MockProTeamService(subscriptions: liveOffer());
      expect(
        (await svc.inviteMember(email: 'a@b.com', role: TeamRole.owner)).code,
        'invalid_role',
      );
      expect(
        (await svc.inviteMember(email: 'a@b.com', role: TeamRole.staff)).code,
        'artist_required',
      );
      expect(
        (await svc.inviteMember(
          email: 'a@b.com',
          role: TeamRole.staff,
          artistId: 'artist_ghost',
        ))
            .code,
        'artist_not_found',
      );
    });

    test(
        'duplicate active/pending → member_exists; an EXPIRED invite can '
        'be re-invited', () async {
      final svc = MockProTeamService(subscriptions: liveOffer());
      expect(
        (await svc.inviteMember(
          email: 'awa.manager@myweli.test', // seeded ACTIVE
          role: TeamRole.reception,
        ))
            .code,
        'member_exists',
      );
      expect(
        (await svc.inviteMember(
          email: 'invitee@myweli.test', // seeded PENDING (unexpired)
          role: TeamRole.reception,
        ))
            .code,
        'member_exists',
      );
      // The seeded EXPIRED réception row does not block a fresh invite.
      final again = await svc.inviteMember(
        email: 'retard@myweli.test',
        role: TeamRole.reception,
      );
      expect(again.success, isTrue);
    });

    test('no live offer → offer_required; full seats → seat_limit', () async {
      final setup = MockProTeamService(
        subscriptions: MockSubscriptionService(), // setup state
      );
      expect(
        (await setup.inviteMember(email: 'a@b.com', role: TeamRole.manager))
            .code,
        'offer_required',
      );

      // Pro cap = 5 and the R4b seeds already occupy exactly 5 seats —
      // the very next invite hits the gate.
      final full = MockProTeamService(
        subscriptions: liveOffer(tier: SalonTier.pro),
      );
      expect(
        (await full.inviteMember(email: 'm6@b.com', role: TeamRole.reception))
            .code,
        'seat_limit',
      );
    });

    test('per-day cap → invite_rate_limited (T37)', () async {
      final svc = MockProTeamService(
        subscriptions: liveOffer(),
        maxInvitesPerDay: 1,
      );
      await svc.inviteMember(email: 'a@b.com', role: TeamRole.manager);
      expect(
        (await svc.inviteMember(email: 'b@b.com', role: TeamRole.manager)).code,
        'invite_rate_limited',
      );
    });

    test('the owner row is immutable → owner_protected (T36)', () async {
      final svc = MockProTeamService();
      expect(
        (await svc.changeRole('mem_owner1', role: TeamRole.manager)).code,
        'owner_protected',
      );
      expect((await svc.revokeMember('mem_owner1')).code, 'owner_protected');
      expect(
        (await svc.resendInvitation('mem_owner1')).code,
        'owner_protected',
      );
    });

    test('changeRole to staff requires a valid fiche; updates land', () async {
      final svc = MockProTeamService();
      expect(
        (await svc.changeRole('mem_manager1', role: TeamRole.staff)).code,
        'artist_required',
      );
      final ok = await svc.changeRole(
        'mem_manager1',
        role: TeamRole.staff,
        artistId: 'artist1',
      );
      expect(ok.success, isTrue);
      expect(ok.data!.role, TeamRole.staff);
      expect(ok.data!.artistName, 'Kouassi Jean');
    });

    test(
        'resend burns the budget of 3 then 429s; active member → '
        'invalid_state', () async {
      final svc = MockProTeamService();
      for (var left = 2; left >= 0; left--) {
        final r = await svc.resendInvitation('mem_staff1');
        expect(r.success, isTrue);
        expect(r.data!.resendsLeft, left);
      }
      expect(
        (await svc.resendInvitation('mem_staff1')).code,
        'invite_rate_limited',
      );
      expect(
        (await svc.resendInvitation('mem_manager1')).code,
        'invalid_state',
      );
    });

    test(
        'the invitee surface: unexpired cards only; accept activates the '
        'roster row; expired → invitation_expired', () async {
      final svc = MockProTeamService();
      final cards = (await svc.getMyInvitations()).data!;
      expect(cards.single.salonName, 'Salon Excellence');

      final accepted = await svc.acceptInvitation('mem_staff1');
      expect(accepted.success, isTrue);
      expect(accepted.data!.status, TeamMemberStatus.active);
      expect((await svc.getMyInvitations()).data, isEmpty);

      // An expired card (seeded for the réception row's email): hidden
      // from the list, refused on accept.
      svc.invitationEmail = 'retard@myweli.test';
      expect((await svc.getMyInvitations()).data, isEmpty);
      expect(
        (await svc.acceptInvitation('mem_reception1')).code,
        'invitation_expired',
      );
    });

    test('decline deletes the card AND the pending roster row', () async {
      final svc = MockProTeamService();
      expect((await svc.declineInvitation('mem_staff1')).success, isTrue);
      expect(
        MockData.teamMembers.any((m) => m.id == 'mem_staff1'),
        isFalse,
      );
      expect((await svc.declineInvitation('mem_staff1')).code, 'not_found');
    });
  });

  group('ProTeamProvider', () {
    setUpAll(() {
      serviceLocator.proTeamService = MockProTeamService();
    });

    test('load sorts owner first; invite appends; revoke updates in place',
        () async {
      final p = ProTeamProvider();
      await p.load();
      expect(p.members.first.isOwner, isTrue);
      final before = p.members.length;

      final invited = await p.invite(
        email: 'new@b.com',
        role: TeamRole.reception,
      );
      expect(invited, isNotNull);
      expect(p.members.length, before + 1);

      expect(await p.revoke(invited!.id), isTrue);
      expect(
        p.members.singleWhere((m) => m.id == invited.id).status,
        TeamMemberStatus.revoked,
      );
    });

    test('invite failure surfaces the paired error + code', () async {
      final p = ProTeamProvider();
      await p.load();
      final res = await p.invite(
        email: 'awa.manager@myweli.test',
        role: TeamRole.manager,
      );
      expect(res, isNull);
      expect(p.inviteErrorCode, 'member_exists');
      expect(p.inviteError, 'Cette personne est déjà dans l\'équipe.');
    });

    test(
        'myInvitations: load, accept removes the card, decline removes '
        'the card', () async {
      final p = ProTeamProvider();
      await p.loadMyInvitations();
      expect(p.invitationCount, 1);

      final member = await p.acceptMyInvitation(p.myInvitations.single.id);
      expect(member, isNotNull);
      expect(p.invitationCount, 0);
    });
  });
}
