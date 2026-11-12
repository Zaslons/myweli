import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The repository reads and writes B0.18's services added (stage 2), run
/// against both twins — the in-memory one here, the Postgres one in
/// `test/db/postgres_repositories_test.dart`:
///
/// - `ProvidersRepository.compareAndSetStatus` — the validated republish and
///   the rollback's refuse, never written over a suspension;
/// - `MembershipRepository.activeOwnersOf` and
///   `ProviderAuthRepository.accountsByIds` — the admin queue's hydration,
///   one round trip each.
void validationReadsContract({
  required ProvidersRepository Function() providers,
  required MembershipRepository Function() members,
  required ProviderAuthRepository Function() accounts,
  required Future<String> Function({bool withOwner}) salon,
}) {
  group('compareAndSetStatus', () {
    test(
      'draft → active only from draft; active → draft only from active',
      () async {
        final repo = providers();
        final id = await salon(withOwner: false);
        final up = await repo.compareAndSetStatus(
          id,
          from: 'draft',
          to: 'active',
        );
        expect(up?['status'], 'active');
        expect(
          await repo.compareAndSetStatus(id, from: 'draft', to: 'active'),
          isNull,
          reason: 'no longer draft: the loser writes nothing',
        );
        final down = await repo.compareAndSetStatus(
          id,
          from: 'active',
          to: 'draft',
        );
        expect(down?['status'], 'draft');
      },
    );

    test(
      'never over a suspension — and the suspension keeps its memory',
      () async {
        final repo = providers();
        final id = await salon(withOwner: false);
        await repo.setStatus(id, 'suspended');
        expect(
          await repo.compareAndSetStatus(id, from: 'draft', to: 'active'),
          isNull,
        );
        expect((await repo.byId(id))!['status'], 'suspended');
        expect(await repo.suspendedFrom(id), 'draft');
      },
    );

    test('an unknown salon → null; a suspension is not its door '
        '(ArgumentError)', () async {
      final repo = providers();
      expect(
        await repo.compareAndSetStatus('nope', from: 'draft', to: 'active'),
        isNull,
      );
      final id = await salon(withOwner: false);
      await expectLater(
        repo.compareAndSetStatus(id, from: 'draft', to: 'suspended'),
        throwsArgumentError,
      );
      await expectLater(
        repo.compareAndSetStatus(id, from: 'suspended', to: 'active'),
        throwsArgumentError,
      );
      expect((await repo.byId(id))!['status'], 'draft');
    });
  });

  test('activeOwnersOf: the active owner of each salon asked, none for a '
      'salon without one, none for nothing asked', () async {
    final m = members();
    final a = await salon();
    final b = await salon();
    final c = await salon(withOwner: false);
    final owners = await m.activeOwnersOf([a, b, c, 'nope']);
    expect(owners.keys.toSet(), {a, b});
    for (final id in [a, b]) {
      final expected = (await m.listForProvider(
        id,
      )).singleWhere((x) => x.role == 'owner');
      expect(owners[id]!.id, expected.id);
      expect(owners[id]!.accountId, expected.accountId);
    }
    expect(await m.activeOwnersOf(const []), isEmpty);

    // A revoked owner is no owner.
    await m.revoke(owners[a]!.id);
    expect((await m.activeOwnersOf([a])).keys, isEmpty);
  });

  test('accountsByIds: the accounts asked that exist', () async {
    final m = members();
    final a = await salon();
    final b = await salon();
    final owners = await m.activeOwnersOf([a, b]);
    final ids = [for (final o in owners.values) o.accountId!];
    final got = await accounts().accountsByIds([...ids, 'nope']);
    expect(got.keys.toSet(), ids.toSet());
    for (final id in ids) {
      expect(got[id]!.id, id);
      expect(got[id]!.phoneNumber, isNotEmpty);
    }
    expect(await accounts().accountsByIds(const []), isEmpty);
  });
}
