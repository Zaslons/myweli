import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/slug.dart';

/// The app's `slugify` is the backend's twin (R8 — docs/design/
/// salon-go-live-approval.md §6.3): « Configuration » judges a commune typed
/// by hand the way the server's publish gate does (`seedAreaForCommuneName`:
/// `slugify(commune)` against each area's slug and name). A rule that drifts
/// — an accent the server folds and the app does not — ticks « Profil de
/// l’entreprise » for a salon the server then refuses with every row ticked,
/// or blocks one it would publish.
///
/// So this reads backend/lib/src/slug.dart itself: its accent table, entry
/// for entry, and its function's body, token for token.
void main() {
  final backend = File('../backend/lib/src/slug.dart').readAsStringSync();
  final app = File('lib/core/utils/slug.dart').readAsStringSync();

  /// The `{ 'x': 'y', … }` entries of the map literal that follows [start].
  Map<String, String> accentTable(String source, String start) {
    final at = source.indexOf(start);
    expect(at, isNonNegative, reason: '« $start » not found');
    final block = source.substring(at, source.indexOf('};', at));
    return {
      for (final m in RegExp(r"'([^']+)':\s*'([^']*)'").allMatches(block))
        m.group(1)!: m.group(2)!,
    };
  }

  /// `String slugify(String input) { … }`, its whitespace collapsed and the
  /// accent table's name made neutral — what the function DOES.
  String body(String source, String table) {
    final at = source.indexOf('String slugify(String input) {');
    expect(at, isNonNegative, reason: 'no slugify in the file');
    final end = source.indexOf('\n}', at);
    return source
        .substring(at, end + 2)
        .replaceAll(table, 'ACCENTS')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  test('the accent table is the backend\'s, entry for entry — œ and æ '
      'included', () {
    final server = accentTable(backend, 'const _accents = {');
    expect(server, isNotEmpty, reason: 'the parser read nothing');
    expect(server['œ'], 'oe');
    expect(server['æ'], 'ae');
    expect(kSlugAccents, server);
    // And the app's own literal says the same (the const is what runs).
    expect(
      accentTable(app, 'const Map<String, String> kSlugAccents = {'),
      server,
    );
  });

  test('the function is the backend\'s, rule for rule', () {
    expect(body(app, 'kSlugAccents'), body(backend, '_accents'));
  });

  // What both answer — the server's own examples, the communes of the
  // seed, and the edges a hand-typed commune brings.
  const table = {
    'Beauté Divine': 'beaute-divine',
    'Nails & Co': 'nails-co',
    'Cocody': 'cocody',
    'Port-Bouët': 'port-bouet',
    'Port Bouet': 'port-bouet',
    '  ADJAMÉ  ': 'adjame',
    'Attécoubé': 'attecoube',
    'Cœur de Treichville': 'coeur-de-treichville',
    'Ænéa': 'aenea',
    'L’Île — Plateau': 'l-ile-plateau',
    'Yopougon 2': 'yopougon-2',
    '---': '',
    '': '',
  };
  for (final MapEntry(key: input, value: slug) in table.entries) {
    test('« $input » → « $slug »', () => expect(slugify(input), slug));
  }
}
