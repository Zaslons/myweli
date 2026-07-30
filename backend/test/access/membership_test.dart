import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

/// Module `access` R1: the membership rows + the per-request resolver
/// (docs/design/team-access-r1-foundation.md).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository members;
  late MembershipService service;

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    members = InMemoryMembershipRepository();
    service = MembershipService(members, auth);
  });

  Future<String> register({String? providerId, String? email}) async {
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250500000091',
      email: email ?? 'owner@test.pro',
      authProvider: 'google',
      googleSub: 'sub-${email ?? 'owner'}',
      providerId: providerId,
    );
    return reg.provider!.id;
  }

  group('repository', () {
    test('ensureOwner is idempotent and lowercases the email', () async {
      final a = await members.ensureOwner(
        providerId: 'p1',
        accountId: 'acc1',
        email: 'Owner@Test.PRO',
      );
      final b = await members.ensureOwner(
        providerId: 'p1',
        accountId: 'acc1',
        email: 'owner@test.pro',
      );
      expect(a.id, b.id);
      expect(a.email, 'owner@test.pro');
      expect(a.role, 'owner');
      expect(a.status, 'active');
      expect((await members.listForProvider('p1')), hasLength(1));
    });

    test('revokeAllForAccount flips every row and stamps revoked_at', () async {
      await members.ensureOwner(
        providerId: 'p1',
        accountId: 'acc1',
        email: 'a@x.pro',
      );
      await members.ensureOwner(
        providerId: 'p2',
        accountId: 'acc1',
        email: 'a@x.pro',
      );
      await members.revokeAllForAccount('acc1');
      final rows = await members.listForAccount('acc1');
      expect(rows, hasLength(2));
      expect(rows.every((m) => m.status == 'revoked'), isTrue);
      expect(rows.every((m) => m.revokedAt != null), isTrue);
      expect(await members.activeMember('acc1', 'p1'), isNull);
      expect(await members.firstActiveForAccount('acc1'), isNull);
    });
  });

  group('service — per-request resolution (deny by default)', () {
    test('a backfilled/explicit owner holds the full owner preset', () async {
      final id = await register(providerId: 'p1');
      await members.ensureOwner(
        providerId: 'p1',
        accountId: id,
        email: 'owner@test.pro',
      );
      expect(await service.can(id, 'p1', Cap.catalogueManage), isTrue);
      expect(await service.can(id, 'p1', Cap.salonPublish), isTrue);
      expect(await service.can(id, 'p1', Cap.financesView), isTrue);
      // Another salon → nothing.
      expect(await service.can(id, 'p2', Cap.catalogueManage), isFalse);
    });

    test(
      'legacy self-heal: a LINKED account without a row gets its owner '
      'row on first touch (the runtime mirror of the 0027 backfill)',
      () async {
        final id = await register(providerId: 'p1');
        expect(await members.listForAccount(id), isEmpty);

        expect(await service.can(id, 'p1', Cap.journalViewAll), isTrue);

        final rows = await members.listForAccount(id);
        expect(rows, hasLength(1));
        expect(rows.single.role, 'owner');
        // And never for a salon the account is NOT linked to.
        expect(await service.can(id, 'p9', Cap.journalViewAll), isFalse);
        expect(await members.listForAccount(id), hasLength(1));
      },
    );

    test(
      'revoked members are outsiders on their very NEXT request (T38)',
      () async {
        final id = await register(providerId: 'p1');
        await members.ensureOwner(
          providerId: 'p1',
          accountId: id,
          email: 'owner@test.pro',
        );
        // Sever the legacy link too so only the membership row answers.
        await members.revokeAllForAccount(id);
        // (The account keeps providerId='p1', so the self-heal would restore
        // an owner — that is CORRECT for owners. Assert the pure-membership
        // path with an unlinked account instead.)
        final stray = await auth.register(
          businessName: 'Y',
          businessType: 'salon',
          phoneNumber: '+2250500000092',
          email: 'staff@test.pro',
          authProvider: 'google',
          googleSub: 'sub-staff',
        );
        final staffId = stray.provider!.id;
        await members.ensureOwner(
          providerId: 'p1',
          accountId: staffId,
          email: 'staff@test.pro',
        );
        expect(await service.can(staffId, 'p1', Cap.journalViewAll), isTrue);
        await members.revokeAllForAccount(staffId);
        expect(await service.can(staffId, 'p1', Cap.journalViewAll), isFalse);
      },
    );

    test('unknown accounts hold nothing', () async {
      expect(await service.can('ghost', 'p1', Cap.journalViewOwn), isFalse);
      expect(await service.activeSalonFor('ghost'), isNull);
      expect(await service.hasAnyMembership('ghost'), isFalse);
    });

    test('activeSalonFor: the linked salon for owners, the first active '
        'membership for members', () async {
      final owner = await register(providerId: 'p1');
      expect(await service.activeSalonFor(owner), 'p1');

      final member = await auth.register(
        businessName: 'Z',
        businessType: 'salon',
        phoneNumber: '+2250500000093',
        email: 'm@test.pro',
        authProvider: 'google',
        googleSub: 'sub-m',
      );
      final memberId = member.provider!.id;
      // Unlinked account (no salon of its own) with a membership elsewhere.
      await members.ensureOwner(
        providerId: 'p7',
        accountId: memberId,
        email: 'm@test.pro',
      );
      expect(await service.activeSalonFor(memberId), 'p7');
      expect(await service.hasAnyMembership(memberId), isTrue);
    });
  });

  group('salonForRequest — the R6 explicit selector', () {
    test('explicit id: an active member gets the selected salon', () async {
      final memberId = await register(email: 'multi@test.pro');
      await members.ensureOwner(
        providerId: 'p8',
        accountId: memberId,
        email: 'multi@test.pro',
      );
      expect(await service.salonForRequest(memberId, salonId: 'p8'), 'p8');
    });

    test('explicit id: a linked owner WITHOUT a row yet self-heals', () async {
      final owner = await register(providerId: 'p1');
      // No ensureOwner call — memberOf's self-heal must create the row.
      expect(await service.salonForRequest(owner, salonId: 'p1'), 'p1');
      expect(await members.activeMember(owner, 'p1'), isNotNull);
    });

    test('explicit id: revoked-there → null (uniform denial, T55)', () async {
      final memberId = await register(email: 'rev@test.pro');
      await members.ensureOwner(
        providerId: 'p9',
        accountId: memberId,
        email: 'rev@test.pro',
      );
      await members.revokeAllForAccount(memberId);
      expect(await service.salonForRequest(memberId, salonId: 'p9'), isNull);
    });

    test('explicit id: never-a-member and unknown salons → null', () async {
      final owner = await register(providerId: 'p1');
      expect(await service.salonForRequest(owner, salonId: 'p2'), isNull);
      expect(
        await service.salonForRequest(owner, salonId: 'no-such-salon'),
        isNull,
      );
    });

    test('absent/empty id → the legacy activeSalonFor fallback', () async {
      final owner = await register(providerId: 'p1');
      expect(await service.salonForRequest(owner), 'p1');
      expect(await service.salonForRequest(owner, salonId: ''), 'p1');
      expect(await service.salonForRequest('ghost'), isNull);
    });

    test('an owner of TWO salons reaches both explicitly; the fallback '
        'stays the linked one', () async {
      final owner = await register(providerId: 'p1');
      await members.ensureOwner(
        providerId: 'p2',
        accountId: owner,
        email: 'owner@test.pro',
      );
      expect(await service.salonForRequest(owner, salonId: 'p1'), 'p1');
      expect(await service.salonForRequest(owner, salonId: 'p2'), 'p2');
      expect(await service.salonForRequest(owner), 'p1');
    });
  });
}
