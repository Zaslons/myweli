import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The contract of [ProvidersRepository.replaceServices], run against BOTH
/// twins: the in-memory one (`replace_services_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each
/// caller runs it inside its own group.
///
/// docs/design/demo-reset-restore.md §5.2, §5.4 (B16.2, decision 250). The
/// demo salon's weekly reset puts the curated catalogue back with it: one
/// transaction, the snapshot's list in its order, never taking a service
/// another salon owns.
///
/// Each case has its own reason text in brackets, so a failure names the
/// property it is about. Services are written in the stored shape (every key
/// `byId` returns for one), so « each field equal » means the same on both
/// twins; their ids are unique to the run, since ids are global in Postgres
/// and the seed already holds `service1`–`service8`.
///
/// [repo] builds the repository under test. [created] is called with the id
/// of each salon a case creates (Postgres deletes them on teardown).
/// [createdAt], Postgres only, reads each stored service's `created_at` for a
/// salon, by service id; the in-memory twin has no such column.
void replaceServicesContract({
  required ProvidersRepository Function() repo,
  required void Function(String id) created,
  Future<Map<String, DateTime>> Function(String providerId)? createdAt,
}) {
  final tag = DateTime.now().microsecondsSinceEpoch;
  var n = 0;
  String sid(String name) => 'b16_2_${name}_${tag}_${n++}';

  Map<String, dynamic> service(
    String id,
    String name,
    double price,
    String providerId,
  ) => {
    'id': id,
    'name': name,
    'description': '',
    'price': price,
    'priceMax': null,
    'durationMinutes': 30,
    'durationVariants': <String, dynamic>{},
    'providerId': providerId,
    'artistIds': <dynamic>[],
    'active': true,
  };

  Future<String> salon(ProvidersRepository r) async {
    final s = await r.createSalon(
      name: 'Salon Contrat Prestations',
      category: 'salon',
      phoneNumber: '+2250700001602',
    );
    final id = s['id'] as String;
    created(id);
    return id;
  }

  Future<List<Map<String, dynamic>>> services(
    ProvidersRepository r,
    String id,
  ) async => [
    for (final s in ((await r.byId(id))!['services'] as List))
      Map<String, dynamic>.from(s as Map),
  ];

  /// A salon holding three services, A, B and C, in that order.
  Future<
    ({
      String id,
      Map<String, dynamic> a,
      Map<String, dynamic> b,
      Map<String, dynamic> c,
    })
  >
  threeServices(ProvidersRepository r) async {
    final id = await salon(r);
    final a = service(sid('a'), 'Coupe', 5000, id);
    final b = service(sid('b'), 'Brushing', 7000, id);
    final c = service(sid('c'), 'Tresses', 15000, id);
    for (final s in [a, b, c]) {
      await r.addService(id, Map<String, dynamic>.from(s));
    }
    return (id: id, a: a, b: b, c: c);
  }

  test('[replace] the list given, in its order, each field equal: one '
      'dropped, a deleted one back under its id, a price changed', () async {
    final r = repo();
    final s = await threeServices(r);
    await r.deleteService(s.id, s.a['id'] as String);
    final cRepriced = {...s.c, 'price': 12000.0};
    final wanted = [cRepriced, s.a];

    final returned = await r.replaceServices(s.id, [
      for (final x in wanted) Map<String, dynamic>.from(x),
    ]);

    expect(returned, wanted, reason: '[replace] the returned list');
    expect(
      await services(r, s.id),
      wanted,
      reason: '[replace] what byId lists afterwards',
    );
  });

  test(
    '[empty] an empty list leaves none, and answers [] (not null)',
    () async {
      final r = repo();
      final s = await threeServices(r);
      final returned = await r.replaceServices(s.id, const []);
      expect(returned, isNotNull, reason: '[empty] null means no salon');
      expect(returned, isEmpty, reason: '[empty] the returned list');
      expect(await services(r, s.id), isEmpty, reason: '[empty] byId');
    },
  );

  test('[later add] a service added afterwards sorts last', () async {
    final r = repo();
    final s = await threeServices(r);
    await r.replaceServices(s.id, [
      Map<String, dynamic>.from(s.c),
      Map<String, dynamic>.from(s.a),
    ]);
    final d = service(sid('d'), 'Manucure', 8000, s.id);
    await r.addService(s.id, Map<String, dynamic>.from(d));
    expect(
      [for (final x in await services(r, s.id)) x['id']],
      [s.c['id'], s.a['id'], d['id']],
      reason: '[later add] the order after a later addService',
    );
  });

  test('[other salon] another salon\'s services are untouched', () async {
    final r = repo();
    final s = await threeServices(r);
    final other = await threeServices(r);
    final before = await services(r, other.id);
    await r.replaceServices(s.id, [Map<String, dynamic>.from(s.b)]);
    expect(
      await services(r, other.id),
      before,
      reason: '[other salon] the other salon changed',
    );
  });

  test('[foreign id] an id another salon owns is refused, and neither salon '
      'changes', () async {
    final r = repo();
    final s = await threeServices(r);
    final other = await threeServices(r);
    final mine = await services(r, s.id);
    final theirs = await services(r, other.id);
    final taken = {...other.a, 'providerId': s.id};

    await expectLater(
      r.replaceServices(s.id, [Map<String, dynamic>.from(s.b), taken]),
      throwsA(isNot(isA<UnimplementedError>())),
      reason: '[foreign id] a service id another salon owns was accepted',
    );
    expect(
      await services(r, s.id),
      mine,
      reason: '[foreign id] the salon changed',
    );
    expect(
      await services(r, other.id),
      theirs,
      reason: '[foreign id] the other salon changed',
    );
  });

  test('[unknown salon] null, as for every writer', () async {
    expect(
      await repo().replaceServices('b16_2_no_such_salon_$tag', const []),
      isNull,
      reason: '[unknown salon]',
    );
  });

  test(
    '[copy] changing the argument afterwards changes nothing stored',
    () async {
      final r = repo();
      final s = await threeServices(r);
      final arg = [
        Map<String, dynamic>.from(s.c),
        Map<String, dynamic>.from(s.a),
      ];
      final wanted = [for (final x in arg) Map<String, dynamic>.from(x)];
      await r.replaceServices(s.id, arg);
      arg.first['price'] = 1.0;
      arg.add(service(sid('x'), 'Ajout après coup', 1, s.id));

      expect(
        await services(r, s.id),
        wanted,
        reason: '[copy] the stored list followed the argument',
      );
    },
  );

  final readCreatedAt = createdAt;
  if (readCreatedAt != null) {
    test('[order] created_at strictly increasing in the given order', () async {
      final r = repo();
      final s = await threeServices(r);
      final order = [s.c, s.a, s.b];
      await r.replaceServices(s.id, [
        for (final x in order) Map<String, dynamic>.from(x),
      ]);
      final at = await readCreatedAt(s.id);
      for (var i = 1; i < order.length; i++) {
        final prev = at[order[i - 1]['id']]!;
        final cur = at[order[i]['id']]!;
        expect(
          cur.isAfter(prev),
          isTrue,
          reason:
              '[order] ${order[i]['name']} ($cur) is not after '
              '${order[i - 1]['name']} ($prev)',
        );
      }
    });
  }
}
