import 'dart:io';

import 'package:test/test.dart';

/// **No route casts a body field** (docs/design/phone-leftovers.md §3).
///
/// `(body['x'] as String?)` throws a `TypeError` on `{"x": 5}`, and a
/// `TypeError` is what the observability middleware answers as a server fault:
/// a 500 and an error report for a malformed request. Sixty-six such reads
/// lived in twenty-seven routes — every text field of the API. They now go
/// through `optionalString` / `optionalList` (`lib/src/http/body_fields.dart`),
/// whose `BodyFieldTypeError` the middleware answers `400 invalid_body`.
///
/// Walks the whole route tree with no exemptions, like
/// `no_secret_in_url_test.dart`: a guard over the files someone remembered is
/// a guard over nothing else.
///
/// The pattern, declared ONCE so the proof below exercises the object the scan
/// runs. A `!` before `as` is the same hazard.
final castPattern = RegExp(
  r'''\bbody\s*\[\s*(['"])[^'"]*\1\s*\]\s*!?\s*as\b''',
);

/// Comments are stripped before scanning: a comment that quotes the old cast
/// to explain why it is gone must not fail the rule it explains. Crude on
/// purpose (`//` to end of line, `/* … */`) — a `//` inside a string literal
/// cuts the rest of that line, which can only hide a match on it, never
/// invent one.
String stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  List<File> routeFiles() => Directory('routes')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('the route tree is not empty — the scan must not pass vacuously', () {
    final files = routeFiles();
    expect(files.length, greaterThan(20), reason: '${files.length} files');
    // And the readers are what replaced the casts, not a deleted route tree.
    expect(
      files.where((f) => f.readAsStringSync().contains('optionalString(')),
      isNotEmpty,
    );
  });

  test('NO route reads a body field with a cast', () {
    final offenders = <String>[];
    for (final file in routeFiles()) {
      final source = stripComments(file.readAsStringSync());
      for (final m in castPattern.allMatches(source)) {
        offenders.add('${file.path}: ${m.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a cast throws a TypeError on a wrong JSON type, which answers 500. '
          'Read it with optionalString / optionalList '
          '(lib/src/http/body_fields.dart) — a wrong type is then a '
          '400 invalid_body.',
    );
  });

  test('the scan can actually fail — proven against the SHARED pattern', () {
    for (final line in [
      // Verbatim the shapes that were in the tree.
      "final phone = (body['phoneNumber'] as String?)?.trim() ?? '';",
      "notes: body['notes'] as String?,",
      "(body['serviceIds'] as List?)?.whereType<String>()",
      // The near-spellings.
      'body["email"] as String?',
      "body['x']! as String",
      "body[ 'x' ] as String",
    ]) {
      expect(castPattern.hasMatch(line), isTrue, reason: line);
    }
    expect(
      castPattern.hasMatch(
        stripComments("// was: (body['phoneNumber'] as String?)\nfinal a = 1;"),
      ),
      isFalse,
      reason: 'a comment quoting the old cast is not a cast',
    );
  });

  test('the pattern does not match the legitimate reads', () {
    for (final line in [
      "final phone = optionalString(body, 'phoneNumber')?.trim() ?? '';",
      "if (body['serviceIds'] != null && body['serviceIds'] is! List) {",
      'body = await context.request.json() as Map<String, dynamic>;',
      "rating: body['rating'],",
      // Not a body: a stored row, typed by our own schema.
      "tzName: salon?['timezone'] as String?,",
    ]) {
      expect(castPattern.hasMatch(line), isFalse, reason: line);
    }
  });

  test('what this pin does NOT catch, stated rather than implied', () {
    // A regex over source text. It catches the literal reintroduction and the
    // near-spellings above, in `routes/`. It does NOT catch a body bound to
    // another name (`final b = body; b['x'] as String?`), a cast inside a
    // service the body is handed to (those were audited by hand when the
    // readers landed: three unchecked casts — a service's `description`, an
    // artist's `specialization`, a review's `text` — now go through the
    // readers too), or a field passed on as `Object?` and cast later. The
    // readers are the rule; this is the tripwire for its most likely breach.
    expect(castPattern.pattern, contains('body'));
  });
}
