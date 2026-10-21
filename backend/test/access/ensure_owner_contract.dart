import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:test/test.dart';

/// The contract of [MembershipRepository.ensureOwner], run against BOTH twins
/// — the in-memory one (`membership_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each
/// caller runs it inside its own group.
///
/// docs/design/backend-integrity-batch6.md §2.8 (B6.8a). The twins
/// disagreed: Postgres answered a clash on `(provider_id, email)` with
/// `DO UPDATE SET account_id` — a manager's, an invited or a revoked row
/// re-pointed at the caller, KEEPING its role — while the in-memory twin
/// appended a second row. Now both refuse by default: the caller's own
/// active owner row is returned, no row at all creates one, and anything
/// else is a refusal that writes nothing.
///
/// [repo] builds the repository under test. [providerId] must be a salon
/// that exists for it. [account] returns the id of an account holding
/// [email] (Postgres: a real `provider_users` row).
void ensureOwnerContract({
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

  test('no row for the address: an active owner row is created', () async {
    final r = repo();
    final id = await account('first@owner.pro');
    final m = await r.ensureOwner(
      providerId: p,
      accountId: id,
      email: 'First@Owner.pro',
    );
    expect(m.role, 'owner');
    expect(m.status, 'active');
    expect(m.accountId, id);
    expect(await rowsFor(r, 'first@owner.pro'), hasLength(1));
  });

  test('the caller’s own active owner row: returned, never a second', () async {
    final r = repo();
    final id = await account('again@owner.pro');
    final first = await r.ensureOwner(
      providerId: p,
      accountId: id,
      email: 'again@owner.pro',
    );
    final second = await r.ensureOwner(
      providerId: p,
      accountId: id,
      email: 'again@owner.pro',
    );
    expect(second.id, first.id);
    expect(await rowsFor(r, 'again@owner.pro'), hasLength(1));
  });

  test('an INVITED row for the address: refused, the row untouched', () async {
    final r = repo();
    final invited = await r.invite(
      providerId: p,
      email: 'invited@owner.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    final id = await account('invited@owner.pro');
    await expectLater(
      r.ensureOwner(providerId: p, accountId: id, email: 'invited@owner.pro'),
      throwsStateError,
    );
    final rows = await rowsFor(r, 'invited@owner.pro');
    expect(rows, hasLength(1));
    expect(rows.single.id, invited!.id);
    expect(rows.single.role, 'manager');
    expect(rows.single.status, 'invited');
    expect(rows.single.accountId, isNull);
  });

  test('a REVOKED member’s row for the address: refused, untouched', () async {
    final r = repo();
    final invited = await r.invite(
      providerId: p,
      email: 'former@owner.pro',
      role: 'reception',
      expiresAt: inDays(7),
    );
    final formerId = await account('former@owner.pro');
    await r.activate(invited!.id, formerId);
    await r.revoke(invited.id);
    await expectLater(
      r.ensureOwner(
        providerId: p,
        accountId: formerId,
        email: 'former@owner.pro',
      ),
      throwsStateError,
    );
    final rows = await rowsFor(r, 'former@owner.pro');
    expect(rows, hasLength(1));
    expect(rows.single.role, 'reception');
    expect(rows.single.status, 'revoked');
  });

  test('an ACTIVE member of another role: never promoted to owner', () async {
    final r = repo();
    final invited = await r.invite(
      providerId: p,
      email: 'manager@owner.pro',
      role: 'manager',
      expiresAt: inDays(7),
    );
    final managerId = await account('manager@owner.pro');
    await r.activate(invited!.id, managerId);
    await expectLater(
      r.ensureOwner(
        providerId: p,
        accountId: managerId,
        email: 'manager@owner.pro',
      ),
      throwsStateError,
    );
    final rows = await rowsFor(r, 'manager@owner.pro');
    expect(rows.single.role, 'manager');
  });
}
