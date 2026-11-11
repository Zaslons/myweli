import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// Every app bar title in `lib/` is a [ScreenTitle] — a heading a phone reads.
///
/// ## Why this file exists
///
/// From Flutter 3.47, `AppBar`'s own `Semantics(header: true)` makes a heading
/// on no phone: iOS reads `headingLevel` only, as Android has since 3.38. On
/// iOS the bar also passes `namesRoute: null`, so a bare `Text` title leaves a
/// VoiceOver user no way to find the screen's name — WCAG 1.3.1, level A
/// (docs/design/mobile-flutter-3.47-upgrade.md §3.1, SYSTEM.md §13.4).
/// `ScreenTitle` puts `headingLevel: 1` on the title; this keeps every bar on it.
///
/// ## Why it parses instead of matching a line
///
/// A line regex for `AppBar(title: Text(` misses a third of the bars: `dart
/// format` splits any call with a `leading:` or `actions:`, putting `title:` on
/// its own line (`my_bookings_screen.dart`). And a line regex sees the same
/// text inside a comment. So: comments stripped with the shared scanner, every
/// `AppBar(` and `SliverAppBar(` read to its balanced closing parenthesis, and
/// its top-level `title:` argument checked.
///
/// A bar with no title is allowed only where it is listed below, with the
/// reason — the salon page's title is the salon's name, which carries its own
/// heading (pinned by salon_cover_test.dart). A new title-less bar fails here
/// until someone decides where its heading lives.
void main() {
  final lib = Directory(
    Directory.current.path.endsWith('mobile') ? 'lib' : 'mobile/lib',
  );

  /// Title-less bars, by file and kind, and why each has no title.
  const untitledAllowed = <String, List<String>>{
    // The cover and the no-photo header: the salon's name, in
    // `_SalonIdentity`, is the page's level-1 heading.
    'screens/providers/provider_detail_screen.dart': [
      'SliverAppBar',
      'SliverAppBar',
    ],
    // « No title: the salon's name is real data with no width budget in a
    // bar »; the gate's message names the salon.
    'widgets/provider/pro_salon_gate.dart': ['AppBar'],
  };

  ({List<String> offenders, int titled, Map<String, List<String>> untitled})
  sweep() {
    final offenders = <String>[];
    final untitled = <String, List<String>>{};
    var titled = 0;
    final files =
        lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final bar = RegExp(r'(?<![A-Za-z0-9_$])(Sliver)?AppBar\(');
    for (final file in files) {
      final code = stripDartComments(file.readAsStringSync());
      final rel = file.path.substring(lib.path.length + 1);
      for (final m in bar.allMatches(code)) {
        final kind = m.group(1) == null ? 'AppBar' : 'SliverAppBar';
        final title = _namedArgument(code, m.end - 1, 'title');
        final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
        if (title == null) {
          (untitled[rel] ??= []).add(kind);
        } else {
          titled++;
          if (!RegExp(r'^(const\s+)?ScreenTitle\(').hasMatch(title)) {
            offenders.add('$rel:$line ($kind) title: ${_oneLine(title)}');
          }
        }
      }
    }
    return (offenders: offenders, titled: titled, untitled: untitled);
  }

  test('the sweep sees every titled bar (at least the 60 of 2026-11-11)', () {
    // An empty sweep — a moved directory, a parser that stops early — must
    // not pass the test below by checking nothing.
    expect(sweep().titled, greaterThanOrEqualTo(60));
  });

  test('every titled app bar shows a ScreenTitle', () {
    expect(
      sweep().offenders,
      isEmpty,
      reason:
          'a bare title is no heading for VoiceOver or TalkBack: use '
          'ScreenTitle (lib/widgets/common/screen_title.dart)',
    );
  });

  test('a bar without a title is one whose heading lives elsewhere', () {
    expect(
      sweep().untitled,
      untitledAllowed,
      reason:
          'a new title-less bar needs its heading decided — on the page '
          '(as the salon page does) or with a reason here',
    );
  });
}

/// The source of argument [name] in the call whose `(` is at [open], or null.
String? _namedArgument(String code, int open, String name) {
  final args = <String>[];
  var depth = 0;
  var start = open + 1;
  var i = open;
  while (i < code.length) {
    final c = code[i];
    if (c == '"' || c == "'") {
      i = _skipString(code, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        args.add(code.substring(start, i));
        break;
      }
    } else if (c == ',' && depth == 1) {
      args.add(code.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  final named = RegExp('^\\s*$name\\s*:\\s*');
  for (final arg in args) {
    final m = named.firstMatch(arg);
    if (m != null) return arg.substring(m.end).trim();
  }
  return null;
}

/// The index just past the string literal that opens at [i] (quote, triple
/// quote, raw), skipping `${…}` interpolations with their own strings.
int _skipString(String code, int i) {
  final raw = i > 0 && code[i - 1] == 'r';
  final q = code[i];
  final triple = code.startsWith(q * 3, i);
  final close = triple ? q * 3 : q;
  var j = i + close.length;
  while (j < code.length) {
    if (!raw && code[j] == r'\') {
      j += 2;
      continue;
    }
    if (!raw && code.startsWith(r'${', j)) {
      var depth = 1;
      j += 2;
      while (j < code.length && depth > 0) {
        if (code[j] == '"' || code[j] == "'") {
          j = _skipString(code, j);
          continue;
        }
        if (code[j] == '{') depth++;
        if (code[j] == '}') depth--;
        j++;
      }
      continue;
    }
    if (code.startsWith(close, j)) return j + close.length;
    j++;
  }
  return j;
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
