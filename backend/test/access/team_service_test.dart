import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

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

/// R2b — the invitation state machine (team-access-r2b-invitations.md §4):
/// invite → accept/decline/revoke/expire/resend, every gate (role, artist,
/// duplicate, offer, seats, rate limit), owner protection (T36), immediate
/// revocation (T38) and the no-enumeration invitee views (T37).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository memberships;
  late InMemorySalonSubscriptionRepository subs;
  late InMemoryProvidersRepository providers;
  late MembershipService resolver;
  late SalonSubscriptionService subscriptions;
  late _RecordingEmail email;
  late InMemoryProviderAuditLogRepository audit;
  late DateTime now;

  TeamService team({int maxInvitesPerDay = 20}) => TeamService(
    memberships,
    resolver,
    providers,
    subscriptions,
    email,
    audit,
    clock: () => now,
    maxInvitesPerDay: maxInvitesPerDay,
  );

  setUp(() {
    now = DateTime.now().toUtc();
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    memberships = InMemoryMembershipRepository();
    subs = InMemorySalonSubscriptionRepository();
    providers = InMemoryProvidersRepository([
      {
        'id': 'p1',
        'name': 'Chez Awa',
        'status': 'published',
        'artists': [
          {'id': 'a1', 'name': 'Awa'},
        ],
      },
      {
        'id': 'p2',
        'name': 'Studio Belle',
        'status': 'published',
        'artists': [
          {'id': 'b1', 'name': 'Aïcha'},
        ],
      },
    ]);
    resolver = MembershipService(memberships, auth);
    subscriptions = SalonSubscriptionService(
      subs,
      resolver,
      memberships,
      providers,
      auth,
    );
    email = _RecordingEmail();
    audit = InMemoryProviderAuditLogRepository();
  });

  /// A registered owner of [providerId] with a live Pro trial (5 seats).
  Future<String> owner({
    String providerId = 'p1',
    String emailAddr = 'owner@x.pro',
    String sub = 'sub-own',
    bool withOffer = true,
  }) async {
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250500000061',
      email: emailAddr,
      authProvider: 'google',
      googleSub: sub,
      providerId: providerId,
    );
    final id = reg.provider!.id;
    await memberships.ensureOwner(
      providerId: providerId,
      accountId: id,
      email: emailAddr,
    );
    if (withOffer) {
      await subscriptions.chooseOffer(id, providerId, 'pro');
    }
    return id;
  }

  group('invite — validation + gates', () {
    test('happy path: pending row, lowercased email, 7-day expiry, '
        'branded email, audited', () async {
      final ownerId = await owner();
      final r = await team().invite(
        ownerId,
        'p1',
        email: 'Ama.K@Gmail.com',
        role: 'manager',
      );
      expect(r.ok, isTrue);
      final row = r.data! as Map<String, dynamic>;
      expect(row['email'], 'ama.k@gmail.com');
      expect(row['status'], 'invited');
      expect(row['role'], 'manager');
      expect(row['resendsLeft'], 3);
      expect(
        DateTime.parse(row['expiresAt'] as String),
        now.add(TeamService.invitationValidity),
      );
      expect(email.sent.single.to, 'ama.k@gmail.com');
      expect(email.sent.single.subject, contains('Chez Awa'));
      final entries = await audit.entriesFor('p1');
      expect(entries.first['action'], 'members.invite');
      expect(entries.first['actorAccountId'], ownerId);
    });

    test(
      'bad email → invalid_input; owner/unknown role → invalid_role',
      () async {
        final ownerId = await owner();
        expect(
          (await team().invite(
            ownerId,
            'p1',
            email: 'nope',
            role: 'manager',
          )).error,
          'invalid_input',
        );
        expect(
          (await team().invite(
            ownerId,
            'p1',
            email: 'a@b.com',
            role: 'owner',
          )).error,
          'invalid_role',
        );
        expect(
          (await team().invite(
            ownerId,
            'p1',
            email: 'a@b.com',
            role: 'boss',
          )).error,
          'invalid_role',
        );
      },
    );

    test('staff needs a salon-owned artist: missing → artist_required, '
        'foreign → artist_not_found, own → linked', () async {
      final ownerId = await owner();
      expect(
        (await team().invite(
          ownerId,
          'p1',
          email: 'a@b.com',
          role: 'staff',
        )).error,
        'artist_required',
      );
      expect(
        (await team().invite(
          ownerId,
          'p1',
          email: 'a@b.com',
          role: 'staff',
          artistId: 'b1', // p2's artist
        )).error,
        'artist_not_found',
      );
      final ok = await team().invite(
        ownerId,
        'p1',
        email: 'a@b.com',
        role: 'staff',
        artistId: 'a1',
      );
      expect(ok.ok, isTrue);
      expect((ok.data! as Map)['artistId'], 'a1');
    });

    test('duplicate pending or active → member_exists; an EXPIRED '
        'invitation can be re-sent as a new invite', () async {
      final ownerId = await owner();
      await team().invite(ownerId, 'p1', email: 'a@b.com', role: 'manager');
      expect(
        (await team().invite(
          ownerId,
          'p1',
          email: 'A@B.com',
          role: 'reception',
        )).error,
        'member_exists',
      );

      // Backdate the clock so the next invite lands already expired, then
      // verify a fresh invite for that email is allowed again.
      now = DateTime.now().toUtc().subtract(const Duration(days: 8));
      await team().invite(ownerId, 'p1', email: 'late@b.com', role: 'manager');
      now = DateTime.now().toUtc();
      final again = await team().invite(
        ownerId,
        'p1',
        email: 'late@b.com',
        role: 'reception',
      );
      expect(again.ok, isTrue);
    });

    test('no live offer → offer_required (the R2a pricing pivot)', () async {
      final ownerId = await owner(withOffer: false);
      final r = await team().invite(
        ownerId,
        'p1',
        email: 'a@b.com',
        role: 'manager',
      );
      expect(r.error, 'offer_required');
    });

    test('seats full (Pro = 5, owner + 4 invited) → seat_limit', () async {
      final ownerId = await owner();
      for (var i = 0; i < 4; i++) {
        final r = await team().invite(
          ownerId,
          'p1',
          email: 'm$i@b.com',
          role: 'reception',
        );
        expect(r.ok, isTrue);
      }
      expect(
        (await team().invite(
          ownerId,
          'p1',
          email: 'm5@b.com',
          role: 'reception',
        )).error,
        'seat_limit',
      );
    });

    test('per-salon/day budget → invite_rate_limited; next day resets '
        '(T37)', () async {
      final ownerId = await owner();
      final t = team(maxInvitesPerDay: 2);
      await t.invite(ownerId, 'p1', email: 'a@b.com', role: 'manager');
      await t.invite(ownerId, 'p1', email: 'b@b.com', role: 'manager');
      expect(
        (await t.invite(
          ownerId,
          'p1',
          email: 'c@b.com',
          role: 'manager',
        )).error,
        'invite_rate_limited',
      );
      now = now.add(const Duration(days: 1));
      expect(
        (await t.invite(ownerId, 'p1', email: 'c@b.com', role: 'manager')).ok,
        isTrue,
      );
    });

    test('non-manager caller → forbidden (T36: members.manage only)', () async {
      await owner();
      final r = await team().invite(
        'stranger',
        'p1',
        email: 'a@b.com',
        role: 'manager',
      );
      expect(r.error, 'forbidden');
    });
  });

  group('list', () {
    test('owner first, artist names joined, expired flag set', () async {
      final ownerId = await owner();
      await team().invite(
        ownerId,
        'p1',
        email: 'staff@b.com',
        role: 'staff',
        artistId: 'a1',
      );
      final r = await team().list(ownerId, 'p1');
      expect(r.ok, isTrue);
      final items = ((r.data! as Map)['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(items.first['role'], 'owner');
      final staff = items.singleWhere((m) => m['role'] == 'staff');
      expect(staff['artistName'], 'Awa');
      expect(staff['expired'], isFalse);
    });

    test('a plain member cannot read the roster (T36)', () async {
      final ownerId = await owner();
      final inv = await team().invite(
        ownerId,
        'p1',
        email: 'mgr@b.com',
        role: 'manager',
      );
      final invId = (inv.data! as Map)['id'] as String;
      await team().accept(
        invId,
        accountId: 'acc-mgr',
        accountEmail: 'mgr@b.com',
      );
      expect((await team().list('acc-mgr', 'p1')).error, 'forbidden');
    });
  });

  group('changeRole / revoke / resend — owner protection + budgets', () {
    Future<String> invitedId(String ownerId, {String role = 'manager'}) async {
      final r = await team().invite(
        ownerId,
        'p1',
        email: 'm@b.com',
        role: role,
      );
      return ((r.data! as Map)['id']) as String;
    }

    test('changeRole to staff requires a valid artist; updates land', () async {
      final ownerId = await owner();
      final id = await invitedId(ownerId);
      expect(
        (await team().changeRole(ownerId, 'p1', id, role: 'staff')).error,
        'artist_required',
      );
      final ok = await team().changeRole(
        ownerId,
        'p1',
        id,
        role: 'staff',
        artistId: 'a1',
      );
      expect(ok.ok, isTrue);
      expect((ok.data! as Map)['role'], 'staff');
      expect((ok.data! as Map)['artistId'], 'a1');
    });

    test('the owner row is immutable: change/revoke/resend → '
        'owner_protected (T36)', () async {
      final ownerId = await owner();
      final rows = await memberships.listForProvider('p1');
      final ownerRow = rows.single.id;
      expect(
        (await team().changeRole(
          ownerId,
          'p1',
          ownerRow,
          role: 'manager',
        )).error,
        'owner_protected',
      );
      expect(
        (await team().revoke(ownerId, 'p1', ownerRow)).error,
        'owner_protected',
      );
      expect(
        (await team().resend(ownerId, 'p1', ownerRow)).error,
        'owner_protected',
      );
    });

    test('a member of ANOTHER salon is not reachable → not_found', () async {
      final owner1 = await owner();
      final owner2 = await owner(
        providerId: 'p2',
        emailAddr: 'own2@x.pro',
        sub: 'sub-own2',
      );
      final foreign = await team().invite(
        owner2,
        'p2',
        email: 'f@b.com',
        role: 'manager',
      );
      final foreignId = (foreign.data! as Map)['id'] as String;
      expect((await team().revoke(owner1, 'p1', foreignId)).error, 'not_found');
    });

    test('revoke is idempotent and kills capabilities on the NEXT check '
        '(T38)', () async {
      final ownerId = await owner();
      final id = await invitedId(ownerId);
      await team().accept(id, accountId: 'acc-m', accountEmail: 'm@b.com');
      expect(await resolver.can('acc-m', 'p1', 'journal.manage.all'), isTrue);

      final r = await team().revoke(ownerId, 'p1', id);
      expect(r.ok, isTrue);
      expect(await resolver.can('acc-m', 'p1', 'journal.manage.all'), isFalse);

      // Second revoke: still ok (idempotent).
      expect((await team().revoke(ownerId, 'p1', id)).ok, isTrue);
    });

    test(
      'resend re-emails, resets the window, and burns the budget of 3',
      () async {
        final ownerId = await owner();
        final id = await invitedId(ownerId);
        expect(email.sent, hasLength(1));
        for (var left = 2; left >= 0; left--) {
          final r = await team().resend(ownerId, 'p1', id);
          expect(r.ok, isTrue);
          expect((r.data! as Map)['resendsLeft'], left);
        }
        expect(email.sent, hasLength(4));
        expect(
          (await team().resend(ownerId, 'p1', id)).error,
          'invite_rate_limited',
        );
      },
    );

    test('resend on an ACTIVE member → invalid_state', () async {
      final ownerId = await owner();
      final id = await invitedId(ownerId);
      await team().accept(id, accountId: 'acc-m', accountEmail: 'm@b.com');
      expect((await team().resend(ownerId, 'p1', id)).error, 'invalid_state');
    });
  });

  group('the invitee side — accept / decline / pending cards', () {
    test('pendingInvitationsFor: cards with salon name + French role label; '
        'unknown email → [] (no enumeration, T37)', () async {
      final ownerId = await owner();
      await team().invite(ownerId, 'p1', email: 'ama@b.com', role: 'reception');
      final cards = await team().pendingInvitationsFor('Ama@b.com');
      expect(cards, hasLength(1));
      expect(cards.single['salonName'], 'Chez Awa');
      expect(cards.single['roleLabel'], 'Réception');
      expect(cards.single['expiresAt'], isNotNull);
      expect(await team().pendingInvitationsFor('ghost@b.com'), isEmpty);
    });

    test('accept: email must match (403-grade forbidden), expiry → '
        'invitation_expired, unknown/consumed id → not_found', () async {
      final ownerId = await owner();
      final inv = await team().invite(
        ownerId,
        'p1',
        email: 'ama@b.com',
        role: 'manager',
      );
      final id = (inv.data! as Map)['id'] as String;

      expect(
        (await team().accept(
          id,
          accountId: 'a1',
          accountEmail: 'evil@b.com',
        )).error,
        'forbidden',
      );
      final ok = await team().accept(
        id,
        accountId: 'acc-ama',
        accountEmail: 'Ama@b.com',
      );
      expect(ok.ok, isTrue);
      expect((ok.data! as Map)['status'], 'active');
      // Accepted rows are no longer pending — a second accept 404s.
      expect(
        (await team().accept(
          id,
          accountId: 'x',
          accountEmail: 'ama@b.com',
        )).error,
        'not_found',
      );
      expect(await team().pendingInvitationsFor('ama@b.com'), isEmpty);
    });

    test('an expired invitation cannot be accepted', () async {
      final ownerId = await owner();
      now = DateTime.now().toUtc().subtract(const Duration(days: 8));
      final inv = await team().invite(
        ownerId,
        'p1',
        email: 'late@b.com',
        role: 'manager',
      );
      final id = (inv.data! as Map)['id'] as String;
      expect(
        (await team().accept(
          id,
          accountId: 'a',
          accountEmail: 'late@b.com',
        )).error,
        'invitation_expired',
      );
    });

    test('decline deletes the row (re-invite possible) and requires the '
        'email proof (T37)', () async {
      final ownerId = await owner();
      final inv = await team().invite(
        ownerId,
        'p1',
        email: 'ama@b.com',
        role: 'manager',
      );
      final id = (inv.data! as Map)['id'] as String;
      expect(
        (await team().declineById(id, email: 'evil@b.com')).error,
        'forbidden',
      );
      expect((await team().declineById(id, email: 'AMA@b.com')).ok, isTrue);
      expect(await memberships.byId(id), isNull);
      // The owner can invite the same address again.
      expect(
        (await team().invite(
          ownerId,
          'p1',
          email: 'ama@b.com',
          role: 'staff',
          artistId: 'a1',
        )).ok,
        isTrue,
      );
    });
  });
}
