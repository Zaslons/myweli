import 'package:myweli_backend/src/db/postgres_providers_repository.dart'
    show kProviderDocumentColumns;
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The contract of [ProvidersRepository.updateProfile] against the filters of
/// [ProvidersRepository.query], run against BOTH twins: the in-memory one
/// (`profile_filters_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each
/// caller runs it inside its own group.
///
/// docs/design/provider-category-column.md §5.3 (B16.1, decisions 224–226).
/// Postgres copies some document fields into columns, for the filters. A
/// field `updateProfile` forgets to copy leaves the salon listed under its
/// old value while its page shows the new one: production had it for the
/// category (one salon of nine, read 2026-11-24). The in-memory twin filters
/// on the document, so only the Postgres run can catch a column left behind.
///
/// **One case per column, written out by hand**, not generated from
/// [kProviderDocumentColumns]: a case built from the list would vanish with
/// the column it tests, and stay green on exactly the mutation it is for.
/// The last test ties the cases to the list instead.
///
/// Each case reads the document first (the control): a red after that line
/// can only be the column. Reasons start with the column in brackets, so a
/// failure names the column it is about.
///
/// [repo] builds the repository under test. [created] is called with the id
/// of each salon a case creates (Postgres deletes them on teardown: the
/// `providers` table keeps its seed between tests, so cases assert on ids,
/// never on counts).
void profileFiltersContract({
  required ProvidersRepository Function() repo,
  required void Function(String id) created,
}) {
  // A salon of the case's own, made public: the filters hide drafts.
  Future<String> activeSalon(
    ProvidersRepository r, {
    String category = 'barber',
  }) async {
    final salon = await r.createSalon(
      name: 'Salon Contrat Filtres',
      category: category,
      phoneNumber: '+2250700001601',
    );
    final id = salon['id'] as String;
    created(id);
    await r.setStatus(id, 'active');
    return id;
  }

  Future<bool> listed(
    ProvidersRepository r,
    String id, {
    String? q,
    String? commune,
    String? category,
  }) async => (await r.query(
    q: q,
    commune: commune,
    category: category,
  )).any((p) => p['id'] == id);

  test('category: a changed category is the one the filter lists', () async {
    final r = repo();
    final id = await activeSalon(r, category: 'barber');
    await r.updateProfile(id, {'category': 'nails'});
    expect(
      (await r.byId(id))?['category'],
      'nails',
      reason: '[category] control: the document holds the new category',
    );
    expect(
      await listed(r, id, category: 'barber'),
      isFalse,
      reason: '[category] listed under the old category',
    );
    expect(
      await listed(r, id, category: 'nails'),
      isTrue,
      reason: '[category] not listed under the new category',
    );
  });

  test('commune: a changed commune is the one the filter lists', () async {
    final r = repo();
    final id = await activeSalon(r);
    await r.updateProfile(id, {'commune': 'Bingerville'});
    expect(
      await listed(r, id, commune: 'Bingerville'),
      isTrue,
      reason: '[commune] not listed under its first commune (setup)',
    );
    await r.updateProfile(id, {'commune': 'Anyama'});
    expect(
      (await r.byId(id))?['commune'],
      'Anyama',
      reason: '[commune] control: the document holds the new commune',
    );
    expect(
      await listed(r, id, commune: 'Bingerville'),
      isFalse,
      reason: '[commune] listed under the old commune',
    );
    expect(
      await listed(r, id, commune: 'Anyama'),
      isTrue,
      reason: '[commune] not listed under the new commune',
    );
  });

  // The free-text search reads name, description and address. Plain letters,
  // no `%` or `_`, no word inside another: the twins' matching differs on
  // those (survey A-P3, B16.8), and must not decide a case here.
  Future<void> textCase(String column, String first, String second) async {
    final r = repo();
    final id = await activeSalon(r);
    await r.updateProfile(id, {column: first});
    expect(
      await listed(r, id, q: first),
      isTrue,
      reason: '[$column] not found by its first value (setup)',
    );
    await r.updateProfile(id, {column: second});
    expect(
      (await r.byId(id))?[column],
      second,
      reason: '[$column] control: the document holds the new value',
    );
    expect(
      await listed(r, id, q: second),
      isTrue,
      reason: '[$column] not found by the new value',
    );
    expect(
      await listed(r, id, q: first),
      isFalse,
      reason: '[$column] still found by the old value',
    );
  }

  test(
    'name: the search finds the new name, not the old',
    () => textCase('name', 'Velkorin', 'Darvenilo'),
  );
  test(
    'description: the search finds the new description, not the old',
    () => textCase('description', 'Quessandor', 'Plimbaret'),
  );
  test(
    'address: the search finds the new address, not the old',
    () => textCase('address', 'Tornevique', 'Habulmira'),
  );

  test('every column updateProfile keeps has its case above', () {
    expect(
      kProviderDocumentColumns.toSet(),
      {'category', 'commune', 'name', 'description', 'address'},
      reason:
          '[coverage] a column updateProfile keeps has no case here, or a '
          'case here has no column: write the case, or remove it',
    );
  });
}
