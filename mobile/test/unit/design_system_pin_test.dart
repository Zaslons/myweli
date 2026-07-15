import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The design-system literal firewall (docs/design/SYSTEM.md §20, §21 rows 4–7)
/// — the sweep-pin idiom (`salon_time_pin_test.dart`). Spacing and radius are
/// TOKENS (`AppTheme.spacing*` / `AppTheme.radius*`), never raw numbers: a hit
/// means new code hand-wrote a value the system already names, which is how
/// `12` came to appear 76× and `999` 21× before A2 named them.
///
/// If you are here because this went red: you did not break a test, you wrote a
/// literal the design system has a token for. The failure lists the file:line.
///
/// **Scope.** `lib/`, excluding:
///   · `core/theme/` — where the tokens are DEFINED (the literals are legal there).
///   · `screens/provider/features/` — the flag-hidden V2/V3 screens (SYSTEM.md
///     §22); their off-token values are fixed if/when those screens are un-shelved.
///
/// **The escape hatch.** A line carrying `// ds-ignore` is a declared exception —
/// a *fixed layout dimension* (e.g. scroll-bottom clearance for a sticky bar),
/// which §5 does not govern (it governs grid gaps, not overlay sizing). Use it
/// rarely, and say why on the line above.
///
/// Spacing/radius (§5/§6) closed in A2; type/icon-size (§4/§7) in A2b — so the
/// firewall is now complete: no raw colour / spacing / radius / type / icon literal
/// survives in `lib` outside `core/theme/`.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('/core/theme/'))
      .where((f) => !f.path.contains('/screens/provider/features/'))
      .toList();

  /// Every `path:line  <text>` in [dartFiles] whose line matches [pattern] and
  /// does not carry a `// ds-ignore` escape.
  List<String> offenders(RegExp pattern) {
    final hits = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('// ds-ignore')) continue;
        if (pattern.hasMatch(line)) {
          hits.add('${file.path}:${i + 1}  ${line.trim()}');
        }
      }
    }
    return hits;
  }

  group('design-system literal pins (SYSTEM.md §20)', () {
    test('spacing is a token — no raw SizedBox(height/width: N) (§5)', () {
      // Strict `)` so only single-arg SPACER boxes match; a multi-arg
      // `SizedBox(height: N, child: …)` is a *sized container* (a fixed
      // dimension), which §5 does not govern.
      expect(
        offenders(RegExp(r'SizedBox\((?:height|width): \d+(?:\.\d+)?\)')),
        isEmpty,
        reason: 'use AppTheme.spacing* (4/8/12/16/24/32/48/64). A raw spacer '
            'number is either off the 8pt grid or a token that already exists. '
            'A genuine fixed dimension declares `// ds-ignore`.',
      );
    });

    test('padding/margin is a token — no numeric EdgeInsets (§5)', () {
      expect(
        offenders(
          RegExp(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^()]*\d'),
        ),
        isEmpty,
        reason: 'use AppTheme.spacing* inside EdgeInsets.*',
      );
    });

    test('radius is a token — no raw BorderRadius.circular(N) (§6)', () {
      expect(
        offenders(RegExp(r'BorderRadius\.circular\(\d')),
        isEmpty,
        reason: 'use AppTheme.radius* (Small/Medium/Large/XL/XXL/Pill)',
      );
    });

    test('type is a token — no raw fontSize: in a screen (§4)', () {
      expect(
        offenders(RegExp(r'fontSize:')),
        isEmpty,
        reason: 'pick a scale entry (AppTextStyles.*) and .copyWith(color:) — '
            'never TextStyle(fontSize:). 11 (labelSmall) is the floor.',
      );
    });

    test('icon size is a token — no raw size: N (§7)', () {
      // `\b` keeps this off `fontSize:`/`iconSize:` (capital S). Every in-scope
      // `size:` value is icon-scale, so all of them are AppTheme.icon*.
      expect(
        offenders(RegExp(r'\bsize: \d')),
        isEmpty,
        reason: 'use AppTheme.icon* (XS/S/M/L/XL = 16/20/24/32/64)',
      );
    });
  });
}
