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
  List<String> offenders(RegExp pattern, {List<String> allow = const []}) {
    final hits = <String>[];
    for (final file in dartFiles) {
      if (allow.any(file.path.contains)) continue;
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
    // ── A6: feedback has ONE entry point each (SYSTEM.md §15, §21 rows 17/18).
    //
    // Measured at the slice's base (b4d3dbe), these four went red at 116 · 111
    // · 13 · 13 — that is the rows' whole reason for existing. They are usage
    // pins, not literal pins: the failure is "you built your own", not "you
    // typed a number".
    const snackBarComponent = '/widgets/common/app_snack_bar.dart';
    const dialogComponent = '/widgets/common/confirm_dialog.dart';

    test('one snackbar entry point — no raw showSnackBar (§15)', () {
      expect(
        offenders(RegExp(r'\.showSnackBar\('), allow: [snackBarComponent]),
        isEmpty,
        reason: 'feedback goes through AppSnackBar.show/showOn/outcome. It '
            'owns §15\'s kind→colour+icon+duration table; a hand-rolled bar '
            'picks its own tone (30 of 61 errors used to render ink-black) '
            'and its own duration (2s/1s/4s — §15 says 3/6/10).',
      );
    });

    test('no hand-built SnackBar (§15)', () {
      expect(
        offenders(RegExp(r'(?:^|[^A-Za-z0-9_])SnackBar\('),
            allow: [snackBarComponent]),
        isEmpty,
        reason: 'constructing a SnackBar is building the component again.',
      );
    });

    test('one ConfirmDialog — no hand-built AlertDialog (§15)', () {
      expect(
        offenders(RegExp(r'(?:^|[^A-Za-z0-9_])AlertDialog\('),
            allow: [dialogComponent]),
        isEmpty,
        reason: 'use showConfirmDialog / showInputDialog. The component owns '
            'the ladder (verb label, consequence, type-to-confirm), the '
            'destructive classification, cancel-takes-focus (§13.5) and the '
            'controller\'s lifetime — all things the 13 copies got wrong '
            'severally.',
      );
    });

    test('…and its entry points (§15)', () {
      expect(
        offenders(RegExp(r'showDialog<(?:bool|String)>'),
            allow: [dialogComponent]),
        isEmpty,
        reason: 'a bool/String dialog IS a confirm or an input — both belong '
            'to ConfirmDialog. (showDialog<void> for a lightbox is fine.)',
      );
    });

    // ── A7: validation has ONE mechanism (SYSTEM.md §14, §21 row 19).
    //
    // Measured at the slice's base (49d406a): `validator:` went red at **13**
    // across 5 screens, and the loose inline e-mail regex at **5** copies. Both
    // are usage pins — the failure is "you reached for Flutter's Form instead
    // of FieldErrors", or "you wrote your own idea of a valid e-mail".
    //
    // `AppTextField` no longer declares `validator`, so the first rule also
    // guards the deletion: re-adding the parameter is what would let callers
    // come back.

    test('validation goes through FieldErrors — no Form validators (§14)', () {
      expect(
        offenders(RegExp(r'(?:^|[^A-Za-z0-9_])validator:')),
        isEmpty,
        reason: 'a `validator:` cannot express §14 rule 2 (it fires on every '
            'change once touched — the form that yells at `s@`), gives no '
            'per-field map, and cannot carry a server fault to its field. '
            'Worse, its result silently overwrites `decoration.errorText`, so '
            'mixing the two erases pinned server errors. Use FieldErrors.',
      );
    });

    test('one definition of a valid e-mail (§14)', () {
      expect(
        offenders(RegExp(r"RegExp\(r'\^\[\^@")),
        isEmpty,
        reason: 'five copies of the e-mail rule shipped in one app, and they '
            'disagreed: the loose one accepted a single-character TLD the '
            'strict one rejects. Validators.email is the definition.',
      );
    });

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

    // ── A8: motion is a token too (SYSTEM.md §9, §21 row 8).
    //
    // **Scoped to `screens/` + `widgets/`, and the scope is the whole design.**
    // The obvious pin — `duration:` and `Duration(` on one line — was measured
    // and REJECTED: after A8's reduced-motion sweep three of its eight hits had
    // become ternaries (`duration: reduceMotionOf(context) ? … : const
    // Duration(…)`), so a line-anchored pin would have gated the code A8 did not
    // touch and waved through every line it did. A pin that a sweep can walk out
    // of is not a pin.
    //
    // So it matches the LITERAL, not the argument — and pays for that with a
    // scope. `services/mock/` latency, `AppConstants.mockDelay` and the two
    // `Timer` cooldowns are durations that never move a pixel; they live outside
    // these two directories and are simply not in view. The three non-motion
    // millisecond literals that DO live here carry a `// ds-ignore` with a
    // reason on the line above, which is the point of the escape hatch: an
    // exception you can read beats a rule that quietly does not apply.
    //
    // `Duration(seconds:` is deliberately out of scope, not overlooked: §9's
    // five tokens are 50–400 ms, so nothing measured in seconds can be one of
    // them. The story reel's 6 s dwell and the splash's 3800 ms are content
    // timers, not motion — the same distinction §12 draws for its "~300ms"
    // spinner heuristic, which is also not a token.
    final animationFiles = dartFiles
        .where(
            (f) => f.path.contains('/screens/') || f.path.contains('/widgets/'))
        .toList();

    List<String> animationOffenders(RegExp pattern) {
      final hits = <String>[];
      for (final file in animationFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('// ds-ignore')) continue;
          if (pattern.hasMatch(lines[i])) {
            hits.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      return hits;
    }

    test('the pin has files to look at', () {
      // `dartFiles` is built from a relative `Directory('lib')`. If that ever
      // resolves to nothing the two tests below pass on an empty list and read
      // as a clean sweep — the failure mode this whole register exists to stop.
      expect(animationFiles.length, greaterThan(100),
          reason: 'the animation pins are scanning an empty or truncated set');
    });

    test('motion duration is a token — no raw milliseconds (§9)', () {
      expect(
        animationOffenders(RegExp(r'Duration\(milliseconds:')),
        isEmpty,
        reason: 'use AppTheme.motion* (Stagger/Fast/Base/Emphasis/Slow = '
            '50/100/200/300/400ms). A hand-written number is how 240ms and '
            '220ms came to sit next to 200ms doing the same job.',
      );
    });

    test('motion curve is a token — no raw Curves.* (§9)', () {
      expect(
        animationOffenders(RegExp(r'Curves\.')),
        isEmpty,
        reason: 'each §9 token names its curve: use AppTheme.motion*Curve. '
            'The pairing is the rule — entering decelerates, exiting '
            'accelerates — and a bare Curves.easeIn on an ENTERING fade is '
            'exactly the inversion the tokens exist to prevent.',
      );
    });
  });
}
