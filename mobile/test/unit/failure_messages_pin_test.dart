import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/app-failure-messages.md §4 — what the app says when something
/// fails, pinned on the WHOLE tree rather than a list of the files someone
/// remembered (the lesson of the backend's `no_secret_in_url_test`): a new
/// provider or screen that shows an exception's text, the retired sentence, a
/// bare « Erreur » or the server's own `message` fails here the day it is
/// written.
void main() {
  /// Every Dart file under [dir], with its code lines only — the comments may
  /// still say what was retired, and should.
  Map<String, List<(int, String)>> codeLines(String dir, {bool mocks = true}) {
    final out = <String, List<(int, String)>>{};
    for (final f in Directory(
      dir,
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (!mocks && f.path.contains('/services/mock/')) continue;
      final lines = f.readAsLinesSync();
      out[f.path] = [
        for (var i = 0; i < lines.length; i++)
          if (!lines[i].trimLeft().startsWith('//')) (i + 1, lines[i]),
      ];
    }
    return out;
  }

  List<String> offenders(
    Map<String, List<(int, String)>> files,
    bool Function(String line) bad,
  ) => [
    for (final MapEntry(key: path, value: lines) in files.entries)
      for (final (n, line) in lines)
        if (bad(line)) '$path:$n  ${line.trim()}',
  ];

  test(
    'no exception text reaches a screen: no e.toString() in providers or screens',
    () {
      final raw = RegExp(r'\b(e|error|err)\.toString\(\)');
      for (final dir in ['lib/providers', 'lib/screens', 'lib/widgets']) {
        expect(offenders(codeLines(dir), raw.hasMatch), isEmpty, reason: dir);
      }
    },
  );

  test('one sentence for « nothing answered »: the retired one is gone', () {
    expect(
      offenders(
        codeLines('lib'),
        (l) => l.contains('Connexion au serveur impossible'),
      ),
      isEmpty,
    );
  });

  test('no bare « Erreur » anywhere the app shows text (mocks aside)', () {
    final bare = RegExp(r'''['"]Erreur['"]''');
    expect(offenders(codeLines('lib', mocks: false), bare.hasMatch), isEmpty);
  });

  test('the server’s own `message` is never read to be shown', () {
    expect(
      offenders(
        codeLines('lib/services/api'),
        (l) => l.contains("['message']"),
      ),
      isEmpty,
    );
  });

  test('every service words its failures through the shared helpers', () {
    // A private copy is how « Erreur » and the two offline sentences came to
    // be: eleven `_errorFrom`s and eleven `_networkError`s, each its own.
    final copies = RegExp(r'ApiResponse<T> _(errorFrom|networkError)<T>\(');
    expect(offenders(codeLines('lib/services/api'), copies.hasMatch), isEmpty);
  });
}
