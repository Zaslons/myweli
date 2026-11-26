import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:test/test.dart';

/// `ClientsRepository.displayNamesFor` — the revenue ledger's batched client
/// names (docs/design/pro-revenue-analytics.md §7.2), on BOTH twins: the
/// in-memory one (`clients_repository_display_names_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Each caller runs it on an empty
/// `salon_clients`.
void displayNamesContract({required ClientsRepository Function() repo}) {
  Map<String, dynamic> client(
    String id, {
    String providerId = 'p_names',
    String? userId,
    String? phone,
    required String name,
  }) => {
    'id': id,
    'providerId': providerId,
    'userId': userId,
    'displayName': name,
    'phone': phone,
    'tags': const <String>[],
    'lastVisitAt': null,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };

  test('displayNamesFor: by user id and by phone, this salon only', () async {
    final r = repo();
    await r.create(client('c-online', userId: 'u1', name: 'Aïcha'));
    await r.create(client('c-guest', phone: '+2250700000001', name: 'Bintou'));
    await r.create(
      client('c-both', userId: 'u2', phone: '+2250700000002', name: 'Chloé'),
    );
    // Erasure unlinks the row (user_id NULL): nothing finds it by user.
    await r.create(client('c-erased', name: 'Client'));
    // Another salon's clients, with the same identifiers.
    await r.create(
      client('c-other-1', providerId: 'p_else', userId: 'u1', name: 'Autre'),
    );
    await r.create(
      client(
        'c-other-2',
        providerId: 'p_else',
        phone: '+2250700000001',
        name: 'Autre',
      ),
    );

    final names = await r.displayNamesFor(
      'p_names',
      userIds: {'u1', 'u-unknown'},
      phones: {'+2250700000001', '+2250700000009'},
    );
    expect(names.byUserId, {'u1': 'Aïcha'});
    expect(names.byPhone, {'+2250700000001': 'Bintou'});

    final both = await r.displayNamesFor(
      'p_names',
      userIds: {'u2'},
      phones: {'+2250700000002'},
    );
    expect(both.byUserId, {'u2': 'Chloé'});
    expect(both.byPhone, {'+2250700000002': 'Chloé'});
  });

  test('displayNamesFor: nothing asked, nothing read', () async {
    final r = repo();
    await r.create(client('c1', userId: 'u1', name: 'Aïcha'));
    final names = await r.displayNamesFor(
      'p_names',
      userIds: const {},
      phones: const {},
    );
    expect(names.byUserId, isEmpty);
    expect(names.byPhone, isEmpty);
  });

  test('displayNamesFor: one kind of identifier only', () async {
    final r = repo();
    await r.create(client('c1', userId: 'u1', name: 'Aïcha'));
    await r.create(client('c2', phone: '+2250700000001', name: 'Bintou'));
    expect(
      (await r.displayNamesFor(
        'p_names',
        userIds: {'u1'},
        phones: const {},
      )).byUserId,
      {'u1': 'Aïcha'},
    );
    expect(
      (await r.displayNamesFor(
        'p_names',
        userIds: const {},
        phones: {'+2250700000001'},
      )).byPhone,
      {'+2250700000001': 'Bintou'},
    );
  });
}
