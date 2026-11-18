import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R8 in the Android release build — written out, not inherited
/// (docs/design/android-play-release.md §3.3, §6, §9; decisions 112, 135).
///
/// ## Why this file exists
///
/// Every Play build of this app has been minified by R8 since the first one:
/// Flutter's Gradle plugin turns `isMinifyEnabled` and `isShrinkResources` on
/// for release unless `--no-shrink` is passed (`FlutterPlugin.kt` 216–219 in
/// 3.47.9). Yet `app/build.gradle.kts` said the opposite, in a comment —
/// « R8 is deliberately NOT enabled here » — which is how a reader concludes
/// that Java and Kotlin crashes need no mapping file. They do, and Sentry can
/// only read them if the build names its mapping (`release_build.sh`'s
/// `SENTRY_PROGUARD_UUID`, held by `release_build_test.dart`).
///
/// So the release block now SAYS what the build does, and this test holds it:
/// a plugin release that stops turning R8 on, or a hand that writes `false`,
/// turns this red instead of shipping an unreadable crash report — or, worse,
/// an unshrunk bundle nobody measured.
void main() {
  final raw = File('android/app/build.gradle.kts').readAsStringSync();
  final code = _stripKotlinComments(raw);

  group('the release build type turns R8 on, in writing', () {
    final release = _block(_block(code, 'buildTypes'), 'release');

    test('isMinifyEnabled = true in release', () {
      expect(release, matches(RegExp(r'\bisMinifyEnabled\s*=\s*true\b')));
    });

    test('isShrinkResources = true in release', () {
      expect(release, matches(RegExp(r'\bisShrinkResources\s*=\s*true\b')));
    });

    test('nothing anywhere turns either off', () {
      expect(code, isNot(matches(RegExp(r'\bisMinifyEnabled\s*=\s*false\b'))));
      expect(
        code,
        isNot(matches(RegExp(r'\bisShrinkResources\s*=\s*false\b'))),
      );
    });

    test('the old comment that said the opposite is gone (read raw: the '
        'stripped text never holds a comment)', () {
      expect(raw, isNot(contains('deliberately NOT enabled')));
    });
  });

  group('the premise: the stripper and the block finder see what they '
      'claim to', () {
    test('a commented-out setting does not count', () {
      final stripped = _stripKotlinComments(
        'release {\n  // isMinifyEnabled = true\n  /* isShrinkResources = '
        'true */\n}\n',
      );
      expect(stripped, isNot(contains('isMinifyEnabled')));
      expect(stripped, isNot(contains('isShrinkResources')));
    });

    test('a URL inside a string is not a comment', () {
      final stripped = _stripKotlinComments('val u = "https://x.y" // gone\n');
      expect(stripped, contains('"https://x.y"'));
      expect(stripped, isNot(contains('gone')));
    });

    test('release is found inside buildTypes, not debug next to it', () {
      final b = _block(
        _block(
          'buildTypes {\n debug { isMinifyEnabled = true }\n release { a = 1 }\n}',
          'buildTypes',
        ),
        'release',
      );
      expect(b, contains('a = 1'));
      expect(b, isNot(contains('isMinifyEnabled')));
    });
  });
}

/// Kotlin comments out — `//` to the end of the line and `/* … */` — while
/// leaving string literals alone, so a `"https://…"` survives.
String _stripKotlinComments(String s) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  while (i < s.length) {
    final c = s[i];
    final next = i + 1 < s.length ? s[i + 1] : '';
    if (inString) {
      out.write(c);
      if (c == r'\' && next.isNotEmpty) {
        out.write(next);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
    } else if (c == '/' && next == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
    } else if (c == '/' && next == '*') {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// The body of the first `<name> {` block in [s], braces balanced; fails the
/// test loudly when there is none, rather than matching against nothing.
String _block(String s, String name) {
  final m = RegExp('\\b${RegExp.escape(name)}\\s*\\{').firstMatch(s);
  if (m == null) fail('no `$name {` block');
  var depth = 1;
  for (var i = m.end; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return s.substring(m.end, i);
  }
  fail('`$name {` is never closed');
}
