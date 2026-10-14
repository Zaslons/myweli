import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:test/test.dart';

/// The contract of [MembershipRepository.invite], run against BOTH twins —
/// the in-memory one (`membership_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself (no
/// `_test` suffix): each caller runs it inside its own group, with its own
/// isolation.
///
/// Why a shared body: the in-memory twin had no `UNIQUE (provider_id,
/// email)`, so it appended a second row where Postgres raised 23505 — every
/// test passed on behaviour production could not produce, and re-inviting
/// a revoked member answered 500 (docs/design/backend-team-reinvite.md).
///
/// [repo] builds the repository under test. [providerId] must be a salon
/// that exists for it (Postgres: a seeded provider). [account] returns the
/// id of an account holding [email] (Postgres: a real `provider_users` row,
/// for the `account_id` foreign key).
void inviteContract({
  required MembershipRepository Function() repo,
  required String providerId,
  required Future<String> Function(String email) account,
}) {
  final p = providerId;
  DateTime inDays(int days) => DateTime.now().toUtc().add(Duration(days: days));

  Future<List<Member>> rowsFor(MembershipRepository r, String email) async => [
    for (final m in await r.listForProvider(p))
      if (m.email == email) m,
  ];

  test('a new address gets a new invitation row', () async {
    final r = repo();
    final m = await r.invite(
      providerId: p,
      email: 'new@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    expect(m, isNotNull);
    expect(m!.status, 'invited');
    expect(m.resendsLeft, 3);
    expect(await rowsFor(r, 'new@contract.pro'), hasLength(1));
  });

  test('a still-valid invitation holds the address: null, nothing changes '
      '(any case)', () async {
    final r = repo();
    final first = await r.invite(
      providerId: p,
      email: 'Pending@Contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    final second = await r.invite(
      providerId: p,
      email: 'pending@contract.pro',
      role: 'reception',
      expiresAt: inDays(7),
    );
    expect(second, isNull);
    final rows = await rowsFor(r, 'pending@contract.pro');
    expect(rows, hasLength(1));
    expect(rows.single.id, first!.id);
    expect(rows.single.role, 'manager');
  });

  test('an active member holds the address: null', () async {
    final r = repo();
    final acc = await account('active@contract.pro');
    final inv = await r.invite(
      providerId: p,
      email: 'active@contract.pro',
      role: 'reception',
      expiresAt: inDays(7),
    );
    await r.activate(inv!.id, acc);
    final again = await r.invite(
      providerId: p,
      email: 'active@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    expect(again, isNull);
    final rows = await rowsFor(r, 'active@contract.pro');
    expect(rows.single.status, 'active');
    expect(rows.single.role, 'reception');
  });

  test('a REVOKED member is invited again on the SAME row — everything that '
      'was the old cycle starts over, the account link stays', () async {
    final r = repo();
    final acc = await account('back@contract.pro');
    final inv = await r.invite(
      providerId: p,
      email: 'back@contract.pro',
      role: 'staff',
      artistId: 'a1',
      invitedBy: 'owner-before',
      expiresAt: inDays(7),
    );
    await r.resendInvite(inv!.id, inDays(7)); // budget 3 → 2
    await r.activate(inv.id, acc);
    await r.revoke(inv.id);

    final expires = inDays(7);
    final again = await r.invite(
      providerId: p,
      email: 'back@contract.pro',
      role: 'manager',
      invitedBy: 'owner-now',
      expiresAt: expires,
    );

    expect(again, isNotNull, reason: 'a revoked row must not block');
    expect(again!.id, inv.id, reason: 'one row per (salon, email)');
    expect(again.status, 'invited');
    expect(again.role, 'manager');
    expect(again.artistId, isNull, reason: 'the old staff link is gone');
    expect(again.invitedBy, 'owner-now');
    expect(again.resendsLeft, 3);
    expect(again.acceptedAt, isNull);
    expect(again.revokedAt, isNull);
    expect(again.accountId, acc, reason: 'kept until activate rewrites it');
    expect(again.expiresAt!.difference(expires).inSeconds.abs(), lessThan(2));
    expect(again.isExpiredInvitation, isFalse);
    final rows = await rowsFor(r, 'back@contract.pro');
    expect(rows, hasLength(1));
    expect(rows.single.status, 'invited');
  });

  test('an EXPIRED invitation is invited again on the same row', () async {
    final r = repo();
    final inv = await r.invite(
      providerId: p,
      email: 'late@contract.pro',
      role: 'reception',
      expiresAt: inDays(-1),
    );
    expect(inv!.isExpiredInvitation, isTrue, reason: 'the control');

    final again = await r.invite(
      providerId: p,
      email: 'late@contract.pro',
      role: 'reception',
      expiresAt: inDays(7),
    );

    expect(again, isNotNull);
    expect(again!.id, inv.id);
    expect(again.status, 'invited');
    expect(again.isExpiredInvitation, isFalse);
    expect(await rowsFor(r, 'late@contract.pro'), hasLength(1));
  });

  test('two invitations of the same address at once: one row, one winner, '
      'no error', () async {
    // On Postgres the two run on two pool connections — the loser waits for
    // the winner's row, finds it live, and gets no row instead of a 23505.
    final r = repo();
    final results = await Future.wait([
      r.invite(
        providerId: p,
        email: 'race@contract.pro',
        role: 'manager',
        expiresAt: inDays(7),
      ),
      r.invite(
        providerId: p,
        email: 'race@contract.pro',
        role: 'reception',
        expiresAt: inDays(7),
      ),
    ]);
    expect(results.whereType<Member>(), hasLength(1));
    expect(await rowsFor(r, 'race@contract.pro'), hasLength(1));
  });

  test('two re-invitations of the same DEAD row at once: one revives it, '
      'the other finds it live', () async {
    final r = repo();
    final inv = await r.invite(
      providerId: p,
      email: 'race-dead@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    await r.revoke(inv!.id);
    final results = await Future.wait([
      for (final role in ['manager', 'reception'])
        r.invite(
          providerId: p,
          email: 'race-dead@contract.pro',
          role: role,
          expiresAt: inDays(7),
        ),
    ]);
    expect(results.whereType<Member>(), hasLength(1));
    expect(results.whereType<Member>().single.id, inv.id);
    final rows = await rowsFor(r, 'race-dead@contract.pro');
    expect(rows.single.status, 'invited');
  });

  test('declining a fresh invitation removes it', () async {
    final r = repo();
    final inv = await r.invite(
      providerId: p,
      email: 'no@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    await r.decline(inv!.id);
    expect(await rowsFor(r, 'no@contract.pro'), isEmpty);
  });

  test('declining the re-invitation of a FORMER member puts the row back to '
      'revoked — it never disappears', () async {
    // Deleting it would leave the former member's account with no row at
    // all, and GET /me/provider would then create a salon for it.
    final r = repo();
    final acc = await account('former@contract.pro');
    final inv = await r.invite(
      providerId: p,
      email: 'former@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    await r.activate(inv!.id, acc);
    await r.revoke(inv.id);
    final again = await r.invite(
      providerId: p,
      email: 'former@contract.pro',
      role: 'reception',
      expiresAt: inDays(7),
    );

    await r.decline(again!.id);

    final rows = await rowsFor(r, 'former@contract.pro');
    expect(rows, hasLength(1));
    expect(rows.single.id, inv.id);
    expect(rows.single.status, 'revoked');
    expect(rows.single.accountId, acc);
    expect(await r.listForAccount(acc), hasLength(1));
  });

  test("the OWNER's row is never revived, whatever its state", () async {
    final r = repo();
    final acc = await account('own@contract.pro');
    final owner = await r.ensureOwner(
      providerId: p,
      accountId: acc,
      email: 'own@contract.pro',
    );
    await r.revoke(owner.id);

    final again = await r.invite(
      providerId: p,
      email: 'own@contract.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );

    expect(again, isNull);
    final rows = await rowsFor(r, 'own@contract.pro');
    expect(rows, hasLength(1));
    expect(rows.single.role, 'owner');
    expect(rows.single.status, 'revoked');
  });
}
