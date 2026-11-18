import 'dart:io';

import 'dart_source.dart';

/// What the Pro binary is made of, as far as source can tell: its entry —
/// `lib/main_pro.dart`, the iOS app, unless [entry] names another — and
/// everything it reaches through `import`, `export` and `part`, followed
/// transitively, every `if (dart.library…)` alternative included.
///
/// [entry] exists for the Android app (`lib/main_pro_android.dart`,
/// pro-android-signup.md §5.1, P1): the iOS closure must hold nothing under
/// `lib/screens/provider/android/`, and the Android one must reach it.
///
/// A file outside this set cannot ship in MyWeli Pro. That is the reason it is
/// the scope of the pins that speak for the Pro app
/// (docs/design/app-review-round-2.md §10): the consumer app's own registration
/// and its legal links live in the same `lib/` and are not what App Review
/// cited, so a scan of all of `lib/` would either be wrong about them or need a
/// list of exceptions that nothing keeps true.
///
/// Returns file path (relative to `mobile/`) → its code with comments removed.
/// Run from `mobile/`, as `flutter test` is.
Map<String, String> proClosure([String entry = 'lib/main_pro.dart']) {
  final directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]([^;]*);''',
    multiLine: true,
  );
  final alternative = RegExp(r'''\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]''');

  final code = <String, String>{};
  final queue = [entry];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (code.containsKey(path)) continue;
    final file = File(path);
    if (!file.existsSync()) {
      // Loud, not skipped: a directive this reader resolved wrongly would
      // otherwise silently cut off everything below it.
      throw StateError('the closure reached $path, which does not exist');
    }
    code[path] = stripDartComments(file.readAsStringSync());
    for (final match in directive.allMatches(code[path]!)) {
      final uris = [
        match.group(1)!,
        for (final alt in alternative.allMatches(match.group(2)!))
          alt.group(1)!,
      ];
      for (final uri in uris) {
        final target = resolveDartUri(path, uri);
        if (target != null) queue.add(target);
      }
    }
  }
  return code;
}

/// The file [uri] names from [from], or null when it is outside this package
/// (`dart:`, another package). Public for the fence test, which resolves
/// every import in `lib/` the way this closure does.
String? resolveDartUri(String from, String uri) {
  const self = 'package:myweli/';
  if (uri.startsWith(self)) return 'lib/${uri.substring(self.length)}';
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  return Uri(path: from).resolve(uri).path;
}
