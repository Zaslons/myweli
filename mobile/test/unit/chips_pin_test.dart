import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/hygiene-batch9.md §2.7.4 (B9.8 F3, Q16–Q18) — a chip is
/// `AppChip`: chosen, a tag, an action, or a status. Pinned on the whole of
/// `lib/`, as the card and async pins are, so a chip written tomorrow by
/// hand fails here the day it is written.
///
/// `screens/provider/features/` is left out: V2/V3 screens behind
/// `FeatureFlags.futureProviderFeatures`, not polished until their phase.
void main() {
  const chipFile = 'lib/widgets/common/app_chip.dart';

  /// Every Dart file under `lib/` outside the V2/V3 screens, comments removed.
  Map<String, String> sources() => {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart') &&
          !f.path.contains('/screens/provider/features/'))
        f.path: f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'),
  };

  Iterable<String> decorations(String s) sync* {
    var from = 0;
    while (true) {
      final i = s.indexOf('BoxDecoration(', from);
      if (i < 0) return;
      var depth = 0;
      var j = i + 'BoxDecoration'.length;
      for (; j < s.length; j++) {
        if (s[j] == '(') depth++;
        if (s[j] == ')' && --depth == 0) break;
      }
      yield s.substring(i, j + 1);
      from = j;
    }
  }

  test('no Material chip outside `AppChip`', () {
    final chip = RegExp(
      r'(?<![A-Za-z_.])(FilterChip|ChoiceChip|ActionChip|InputChip|Chip)\(',
    );
    expect(
      {
        for (final MapEntry(key: path, value: s) in sources().entries)
          if (path != chipFile && chip.hasMatch(s)) path,
      },
      isEmpty,
      reason: 'a chip is AppChip.choice, .tag, .action or .status',
    );
  });

  test('no status badge drawn by hand: a tinted pill or box', () {
    // A tone's tint (`withValues(alpha: …)`) at the badge radius. Three
    // shapes said the same status before F3 (Q18).
    final tint = RegExp(r'withValues\(alpha: 0\.\d+\)');
    final badgeRadius = RegExp(r'radius(Pill|Small)\b');
    expect(
      {
        for (final MapEntry(key: path, value: s) in sources().entries)
          if (path != chipFile &&
              decorations(
                s,
              ).any((d) => tint.hasMatch(d) && badgeRadius.hasMatch(d)))
            path,
      },
      isEmpty,
      reason: 'a status is AppChip.status, its tone in AppChipTone',
    );
  });
}
