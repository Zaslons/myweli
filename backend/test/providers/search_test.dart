import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import 'search_contract.dart';

/// The in-memory run of [searchContract]; the Postgres run is in
/// `db/postgres_repositories_test.dart`. docs/design/consumer-search.md §8.
void main() {
  group('InMemoryProvidersRepository — what a search finds', () {
    searchContract(
      repo: () => InMemoryProvidersRepository([]),
      created: (_) {},
    );
  });

  // The contract's order case cannot reach this twin: createSalon's ids
  // follow insertion order. A seed written out of id order can.
  test('order: equal salons come in id order, whatever the insertion order '
      '(in memory)', () async {
    Map<String, dynamic> salon(String id) => {
      'id': id,
      'name': 'Salon $id',
      'status': 'active',
      'featured': false,
      'rating': 4.5,
    };
    final repo = InMemoryProvidersRepository([
      salon('b'),
      salon('c'),
      salon('a'),
    ]);
    expect(
      [for (final p in await repo.query()) p['id']],
      ['a', 'b', 'c'],
      reason: '[order] the default order ends on the id',
    );
  });
}
