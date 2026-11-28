import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:test/test.dart';

/// Gives the accounts [ids] the same creation time [at]. Each twin does it
/// its own way: the in-memory twin through a test seam, Postgres by SQL.
typedef PlantCreatedAt =
    Future<void> Function(AuthRepository repo, List<String> ids, DateTime at);

/// The admin console's user list (`listUsers`, `GET /admin/users`), run
/// against BOTH twins: in memory (`user_list_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself.
///
/// docs/design/auth-store-twins.md §5.3 (B16.4, decision 286). Newest first,
/// a tie broken by the id in byte order, both descending; `q` matches name,
/// phone or e-mail each on its own, case ignored; `%`, `_` and `\` and
/// accents taken as typed.
///
/// Each case starts from an empty store (Postgres: the file's `setUp`
/// truncates `users`), so every total is exact.
void userListContract({
  required AuthRepository Function() repo,
  required PlantCreatedAt plantCreatedAt,
}) {
  final run = DateTime.now().microsecondsSinceEpoch;
  var n = 0;
  String phone() =>
      '+22507${((run ~/ 1000 + n++) % 100000000).toString().padLeft(8, '0')}';

  Future<AuthUser> user(AuthRepository r, String name) async {
    final p = phone();
    final v = await r.verifyOtp(p, (await r.requestOtp(p)).devCode!);
    expect(v.ok, isTrue, reason: 'the premise: ${v.error}');
    final named = await r.updateUser(v.user!.id, name: name);
    // Distinct creation times, so the order is the rule's and not a tie's.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return named!;
  }

  Future<List<String>> namesOf(
    AuthRepository r, {
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async => [
    for (final u in (await r.listUsers(
      q: q,
      page: page,
      pageSize: pageSize,
    )).items)
      u.name!,
  ];

  test('[order] newest first', () async {
    final r = repo();
    for (final name in ['Awa', 'Bintou', 'Chloé']) {
      await user(r, name);
    }
    expect(await namesOf(r), [
      'Chloé',
      'Bintou',
      'Awa',
    ], reason: '[order] the list must be newest first');
  });

  test('[tie] accounts created at the same instant come by id, descending, '
      'in byte order', () async {
    final r = repo();
    final made = [
      for (final name in ['T1', 'T2', 'T3']) await user(r, name),
    ];
    await plantCreatedAt(r, [
      for (final u in made) u.id,
    ], DateTime.utc(2026, 1, 1));
    final byIdDesc = [...made]..sort((a, b) => b.id.compareTo(a.id));
    expect(
      [for (final u in byIdDesc) u.id],
      isNot([for (final u in made) u.id]),
      reason:
          'the premise: insertion order must differ from the expected '
          'order, or the case cannot fail',
    );
    expect(await namesOf(r), [
      for (final u in byIdDesc) u.name,
    ], reason: '[tie] a tie must be broken by the id, descending');
  });

  test('[page 2] the second page of two holds the oldest', () async {
    final r = repo();
    for (final name in ['Awa', 'Bintou', 'Chloé']) {
      await user(r, name);
    }
    final page = await r.listUsers(page: 2, pageSize: 2);
    expect([for (final u in page.items) u.name], ['Awa'], reason: '[page 2]');
    expect(page.total, 3);
  });

  test('[each field on its own] a query across two fields finds nothing; '
      'each field alone finds its account', () async {
    final r = repo();
    final awa = await user(r, 'Awa');
    expect(
      await namesOf(r, q: 'Awa ${awa.phoneNumber!.substring(0, 6)}'),
      isEmpty,
      reason: '[each field on its own] name and phone matched as one string',
    );
    expect(await namesOf(r, q: 'awa'), ['Awa'], reason: 'the name alone');
    expect(await namesOf(r, q: awa.phoneNumber!.substring(4)), [
      'Awa',
    ], reason: 'the phone alone');
  });

  test('[wildcards] %, _ and \\ are taken as typed', () async {
    final r = repo();
    for (final name in ['Awa 100%', 'Bintou_K', r'Chloé\D', 'Djeneba']) {
      await user(r, name);
    }
    expect(await namesOf(r, q: '%'), [
      'Awa 100%',
    ], reason: '[wildcards] « % » matched as a wildcard');
    expect(await namesOf(r, q: '_'), [
      'Bintou_K',
    ], reason: '[wildcards] « _ » matched as a wildcard');
    expect(await namesOf(r, q: r'\'), [
      r'Chloé\D',
    ], reason: r'[wildcards] « \ » read as an escape');
  });

  test(
    '[case] case is ignored, accented letters included (a control)',
    () async {
      final r = repo();
      await user(r, 'Élodie');
      expect(await namesOf(r, q: 'élodie'), ['Élodie']);
      expect(await namesOf(r, q: 'ÉLODIE'), ['Élodie']);
    },
  );

  test('[accents as typed] « elodie » does not find « Élodie » '
      '(a control: not folded)', () async {
    final r = repo();
    await user(r, 'Élodie');
    expect(await namesOf(r, q: 'elodie'), isEmpty);
  });
}
