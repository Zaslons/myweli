import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// What `GET /providers?q=` finds, run against BOTH twins: the in-memory one
/// (`search_test.dart`) and Postgres (`db/postgres_repositories_test.dart`).
/// Not a test file itself: each caller runs it inside its own group.
///
/// docs/design/consumer-search.md §3 and §8 (A4-api, decision 228): `q`
/// matches the salon's name, description, address and commune, and the names
/// of its active services, each field on its own; case and accents ignored;
/// spaces trimmed and collapsed; `%`, `_` and `\` match themselves; only the
/// first 100 characters count; every order ends on the salon id.
///
/// Every case asserts on ids, never on counts: Postgres keeps its seeded
/// salons between tests. [created] is called with the id of each salon a
/// case creates, so Postgres can delete it on teardown. Reasons start with
/// the rule in brackets, so a failure names the rule it is about.
void searchContract({
  required ProvidersRepository Function() repo,
  required void Function(String id) created,
}) {
  var phone = 1700;

  /// A public salon of the case's own, with the fields a search reads.
  Future<String> salon(
    ProvidersRepository r, {
    required String name,
    String? description,
    String? address,
    String? commune,
  }) async {
    final made = await r.createSalon(
      name: name,
      category: 'salon',
      phoneNumber: '+225070001${phone++}',
      address: address,
    );
    final id = made['id'] as String;
    created(id);
    await r.updateProfile(id, {
      'description': ?description,
      'commune': ?commune,
    });
    await r.setStatus(id, 'active');
    return id;
  }

  Future<bool> listed(ProvidersRepository r, String id, String q) async =>
      (await r.query(q: q)).any((p) => p['id'] == id);

  test('fields: name, description, address, commune and an active service '
      'each match; an inactive service does not', () async {
    final r = repo();
    final id = await salon(
      r,
      name: 'Salon Quarzo',
      description: 'Tresses africaines',
      address: 'Rue Vingt-Neuf',
      commune: 'Treichville',
    );
    await r.addService(id, {
      'id': '${id}_s1',
      'name': 'Manucure express',
      'description': '',
      'price': 5000,
      'durationMinutes': 30,
    });
    await r.addService(id, {
      'id': '${id}_s2',
      'name': 'Pose de vernis gel',
      'description': '',
      'price': 8000,
      'durationMinutes': 45,
    });
    await r.updateService(id, '${id}_s2', {'active': false});
    final services = ((await r.byId(id))!['services'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      services.map((s) => (s['name'], s['active'] ?? true)),
      containsAll([('Manucure express', true), ('Pose de vernis gel', false)]),
      reason: '[fields] control: both services stored, the second inactive',
    );

    expect(await listed(r, id, 'quarzo'), isTrue, reason: '[fields] name');
    expect(
      await listed(r, id, 'africaines'),
      isTrue,
      reason: '[fields] description',
    );
    expect(
      await listed(r, id, 'vingt-neuf'),
      isTrue,
      reason: '[fields] address',
    );
    expect(
      await listed(r, id, 'treichville'),
      isTrue,
      reason: '[fields] commune',
    );
    expect(
      await listed(r, id, 'manucure express'),
      isTrue,
      reason: '[fields] an active service',
    );
    expect(
      await listed(r, id, 'vernis gel'),
      isFalse,
      reason: '[fields] an inactive service must not match',
    );
    // A salon with no service: a service's name finds only its own salon.
    final other = await salon(r, name: 'Salon Quarzo Témoin');
    expect(
      await listed(r, other, 'quarzo'),
      isTrue,
      reason: '[fields] control: the other salon is public',
    );
    expect(
      await listed(r, other, 'manucure express'),
      isFalse,
      reason: '[fields] another salon\'s service does not list this one',
    );
  });

  test('accents and case: ignored on both sides of the comparison', () async {
    final r = repo();
    final accented = await salon(r, name: 'Beauté Divine Zola');
    final plain = await salon(r, name: 'Beaute Simple Zola');
    expect(
      await listed(r, accented, 'beaute divine'),
      isTrue,
      reason: '[accents] « beaute » finds « Beauté »',
    );
    expect(
      await listed(r, accented, 'BEAUTÉ DIVINE'),
      isTrue,
      reason: '[accents] upper case with an accent',
    );
    expect(
      await listed(r, plain, 'beauté simple'),
      isTrue,
      reason: '[accents] « beauté » finds « Beaute »',
    );
    expect(
      await listed(r, plain, 'BEAUTE SIMPLE'),
      isTrue,
      reason: '[case] upper case finds lower case',
    );
  });

  test('spaces: trimmed, and a run of them is one', () async {
    final r = repo();
    final id = await salon(r, name: 'Beauté Divine Kanga');
    expect(
      await listed(r, id, '  beaute   divine\u00a0 kanga  '),
      isTrue,
      reason: '[spaces] trimmed and collapsed, a no-break space included',
    );
    expect(
      await listed(r, id, '   '),
      isTrue,
      reason: '[spaces] a text of spaces is no filter',
    );
  });

  test("spaces: the salon's own runs of white space count as one", () async {
    final r = repo();
    final doubled = await salon(r, name: 'Beauté  Divine Nour');
    final narrow = await salon(r, name: 'Awa\u202f: coiffure Liza');
    final lines = await salon(
      r,
      name: 'Salon Lignes',
      description: 'Tresses\nafricaines Mia',
    );
    expect(
      await listed(r, doubled, 'beaute divine nour'),
      isTrue,
      reason: '[spaces] two spaces in the name',
    );
    expect(
      await listed(r, doubled, 'beaute  divine  nour'),
      isTrue,
      reason: '[spaces] typed exactly, two spaces',
    );
    expect(
      await listed(r, narrow, 'awa : coiffure liza'),
      isTrue,
      reason: '[spaces] a narrow no-break space before « : »',
    );
    expect(
      await listed(r, lines, 'tresses africaines mia'),
      isTrue,
      reason: '[spaces] a line break in the description',
    );
  });

  test('a text with nothing left once folded is no filter', () async {
    final r = repo();
    final id = await salon(r, name: 'Salon Accent Seul');
    expect(
      await listed(r, id, '\u0301'),
      isTrue,
      reason: '[fold] a lone combining accent folds to nothing: every salon',
    );
  });

  test(r'%, _ and \ match themselves, before and after folding', () async {
    final r = repo();
    final plain = await salon(r, name: 'Salon Nyota Plain');
    final marked = await salon(r, name: r'Studio_100% Kito\Bar');
    for (final q in ['_', '%', r'\', '＿', '％', '＼']) {
      expect(
        await listed(r, plain, q),
        isFalse,
        reason: '[wildcards] « $q » is not a wildcard',
      );
    }
    for (final q in ['_', '%', r'\', '0%', '＿', '％', '＼']) {
      expect(
        await listed(r, marked, q),
        isTrue,
        reason: '[wildcards] « $q » finds the salon that holds it',
      );
    }
  });

  test('length: only the first 100 characters count', () async {
    final r = repo();
    final t100 = List.generate(100, (i) => 'abcdefghij'[i % 10]).join();
    final id = await salon(r, name: 'Salon Long Texte', description: t100);
    expect(
      await listed(r, id, t100),
      isTrue,
      reason: '[length] control: the 100 characters themselves',
    );
    expect(
      await listed(r, id, '$t100${'Z' * 50}'),
      isTrue,
      reason: '[length] 150 characters behave as their first 100',
    );
    expect(
      await listed(r, id, '${t100.substring(0, 99)}Z'),
      isFalse,
      reason: '[length] the 100th character still counts',
    );

    final emoji = await salon(
      r,
      name: 'Salon Emoji Texte',
      description: '${t100.substring(0, 99)}😀',
    );
    expect(
      await listed(r, emoji, '${t100.substring(0, 99)}😀${'Z' * 10}'),
      isTrue,
      reason: '[length] an emoji at the cut is kept whole',
    );
  });

  test('fields: a text spanning two fields matches neither', () async {
    final r = repo();
    final id = await salon(
      r,
      name: 'Salon Alpha Kivu',
      description: 'Beta coiffure',
    );
    expect(
      await listed(r, id, 'alpha kivu'),
      isTrue,
      reason: '[fields] control: inside one field',
    );
    expect(
      await listed(r, id, 'kivu beta'),
      isFalse,
      reason: '[fields] the end of the name and the start of the description',
    );
  });

  test('fields: an empty field is not the text « null »', () async {
    final r = repo();
    final id = await salon(r, name: 'Salon Sans Commune');
    expect(
      (await r.byId(id))!['commune'],
      isNull,
      reason: '[fields] control: no commune',
    );
    expect(
      await listed(r, id, 'null'),
      isFalse,
      reason: '[fields] a missing field matches nothing',
    );
  });

  test('fold: ’, œ, æ and a decomposed accent fold like unaccent', () async {
    final r = repo();
    final curly = await salon(r, name: 'L’Atelier Sœurs Cæsar');
    final straight = await salon(r, name: "L'Ami Kora");
    expect(
      await listed(r, curly, "l'atelier"),
      isTrue,
      reason: '[fold] « ’ » (an iPhone apostrophe) is « \' »',
    );
    expect(
      await listed(r, curly, 'soeurs'),
      isTrue,
      reason: '[fold] « œ » is « oe »',
    );
    expect(
      await listed(r, curly, 'caesar'),
      isTrue,
      reason: '[fold] « æ » is « ae »',
    );
    expect(
      await listed(r, straight, 'l’ami'),
      isTrue,
      reason: '[fold] the other way: « ’ » in the search',
    );
    final cafe = await salon(r, name: 'Café Mona');
    expect(
      await listed(r, cafe, 'café mona'),
      isTrue,
      reason: '[fold] « é » typed as « e » plus a combining accent',
    );
  });

  test('order: equal salons come in id order', () async {
    final r = repo();
    final first = await r.createSalon(
      name: 'Salon Ordre Un',
      category: 'salon',
      phoneNumber: '+2250700001790',
    );
    final second = await r.createSalon(
      name: 'Salon Ordre Deux',
      category: 'salon',
      phoneNumber: '+2250700001791',
    );
    final a = first['id'] as String;
    final b = second['id'] as String;
    created(a);
    created(b);
    // Published in the reverse order: on Postgres the later UPDATE lands
    // later in the table, so without the tiebreak a scan meets [b] first.
    // In memory, createSalon's ids follow insertion order and this case
    // cannot tell; `search_test.dart` pins that twin with a hand-made seed.
    await r.setStatus(b, 'active');
    await r.setStatus(a, 'active');
    final ids = [for (final p in await r.query(q: 'salon ordre')) p['id']];
    final lower = a.compareTo(b) < 0 ? a : b;
    final higher = lower == a ? b : a;
    expect(ids, containsAll([a, b]), reason: '[order] control: both listed');
    expect(
      ids.indexOf(lower) < ids.indexOf(higher),
      isTrue,
      reason: '[order] equal rating and placement: the lower id first',
    );
  });
}
