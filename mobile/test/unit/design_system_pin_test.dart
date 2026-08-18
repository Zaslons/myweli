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
        // **A whole-line comment is prose, not code** (A11 C5). This sweep is
        // line-based, so a docstring quoting the very rule it enforces used to
        // BE a violation of it — which happened twice in three commits, once in
        // `otp_code_row.dart` quoting §13.3's example and once in
        // `reviews_screen.dart` naming the literal it had just deleted. The
        // effect was a standing incentive not to document the rules.
        //
        // Only a line that is ENTIRELY a comment is skipped. An end-of-line
        // `// …` is left alone on purpose: truncating at the first `//` would
        // also cut a line containing a URL, and would hide real code beside it.
        if (line.trimLeft().startsWith('//')) continue;
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
    // The second dialog component, and the split is by BEHAVIOUR: ConfirmDialog
    // decides and pops; FormDialog edits and must survive its own failure, so a
    // server fault can attach to a field with the dialog still open and the
    // values still typed. Two files own an AlertDialog; no screen does.
    const formDialogComponent = '/widgets/common/form_dialog.dart';

    test('one snackbar entry point — no raw showSnackBar (§15)', () {
      expect(
        offenders(RegExp(r'\.showSnackBar\('), allow: [snackBarComponent]),
        isEmpty,
        reason:
            'feedback goes through AppSnackBar.show/showOn/outcome. It '
            'owns §15\'s kind→colour+icon+duration table; a hand-rolled bar '
            'picks its own tone (30 of 61 errors used to render ink-black) '
            'and its own duration (2s/1s/4s — §15 says 3/6/10).',
      );
    });

    test('no hand-built SnackBar (§15)', () {
      expect(
        offenders(
          RegExp(r'(?:^|[^A-Za-z0-9_])SnackBar\('),
          allow: [snackBarComponent],
        ),
        isEmpty,
        reason: 'constructing a SnackBar is building the component again.',
      );
    });

    test('one ConfirmDialog — no hand-built AlertDialog (§15)', () {
      expect(
        offenders(
          RegExp(r'(?:^|[^A-Za-z0-9_])AlertDialog\('),
          allow: [dialogComponent, formDialogComponent],
        ),
        isEmpty,
        reason:
            'use showConfirmDialog / showInputDialog. The component owns '
            'the ladder (verb label, consequence, type-to-confirm), the '
            'destructive classification, cancel-takes-focus (§13.5) and the '
            'controller\'s lifetime — all things the 13 copies got wrong '
            'severally.',
      );
    });

    test('…and its entry points (§15)', () {
      expect(
        offenders(
          RegExp(r'showDialog<(?:bool|String)>'),
          allow: [dialogComponent, formDialogComponent],
        ),
        isEmpty,
        reason:
            'a bool/String dialog IS a confirm, an input or a form — they '
            'belong to ConfirmDialog / FormDialog, whose entry points own the '
            'raw showDialog so this stays a grep rather than a convention. '
            '(showDialog<void> for a lightbox is fine.)',
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
        reason:
            'a `validator:` cannot express §14 rule 2 (it fires on every '
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
        reason:
            'five copies of the e-mail rule shipped in one app, and they '
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
        reason:
            'use AppTheme.spacing* (4/8/12/16/24/32/48/64). A raw spacer '
            'number is either off the 8pt grid or a token that already exists. '
            'A genuine fixed dimension declares `// ds-ignore`.',
      );
    });

    test('gaps are a token — no raw spacing:/runSpacing: (§5)', () {
      // A11 C3. The two rules above scan `SizedBox(…)` and `EdgeInsets.*`, and
      // between them they were called "the complete firewall" — but Flutter 3.27
      // put `spacing` on `Flex`, and `Wrap` has had `spacing`/`runSpacing` all
      // along. **A gap written that way was invisible to every pin**, and 21 of
      // them had accumulated across 11 files by the time A11 went looking.
      //
      // Nineteen were already the token's value (8, and one 4) — invisible, not
      // wrong. The other two are why this is a §5 rule and not tidiness:
      // `spacing: 10` on the booking hub's slot chips and `spacing: 6` on the
      // appointment card's service pills. §5's own header says it: "an 8pt grid
      // with one sanctioned half-step. Nothing else is legal: 10, 14, 18, 20 are
      // not spacing values."
      //
      // `\b` keeps this off `letterSpacing:`/`wordSpacing:` twice over — those
      // capitalise the S, and there is no word boundary before it either.
      //
      // **A13, §21 row 71 — and the same `\b` was the hole.** It cannot fire
      // inside `crossAxisSpacing`/`mainAxisSpacing` either, so a grid's gaps
      // were invisible to a sweep §20 called complete. A12 converted the pro
      // dashboard's two in passing; a proper sweep returns **six**, and four of
      // them are `10` — not a token at all (the scale is 4/8/12/16/24/32/48/64).
      //
      // **The obvious widening is a trap.** `[A-Za-z]*[Ss]pacing:` reds on
      // **seven `letterSpacing:` lines** inside this very corpus — i.e. it
      // "closes" the gap by reintroducing the exact bug the `\b` was written
      // against. So the pattern names the compounds explicitly instead.
      //
      // `\s*` rather than a literal space closes a second hole while we are
      // here: a wrapped argument (`spacing:\n    10`) evaded the old form too.
      // Measured: zero sites exploit it today, so this is prevention, not a fix.
      expect(
        offenders(RegExp(r'(?:\b(?:run)?|(?:cross|main)Axis)[Ss]pacing:\s*\d')),
        isEmpty,
        reason:
            'use AppTheme.spacing* (4/8/12/16/24/32/48/64) for Wrap and '
            'Flex gaps too. A gap is spacing whether it is written as a '
            'SizedBox between children or as the parent’s `spacing:`, or as a '
            'grid delegate’s crossAxisSpacing/mainAxisSpacing.',
      );
    });

    // A13. The §5 spacing sweep above had **no non-empty guard of its own** —
    // it borrowed the credibility of the `childAspectRatio` and animation pins,
    // which do have one, from the same `group`. A pin that silently scans an
    // empty corpus is §21 row 67's failure mode, and the two tests that would
    // have caught it are not this test.
    test('the §5 spacing sweep is scanning a real corpus', () {
      expect(
        dartFiles.length,
        greaterThan(100),
        reason:
            'the spacing pin is scanning an empty or truncated file set, '
            'so its green means nothing',
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
        reason:
            'pick a scale entry (AppTextStyles.*) and .copyWith(color:) — '
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
    //
    // `core/router/` is in scope even though it holds no animation today (0
    // hits, checked): go_router's `CustomTransitionPage(transitionDuration:,
    // transitionsBuilder:)` is where a full-screen transition BELONGS, and the
    // review found it sitting in a directory neither pin read. A pin that only
    // covers where the code is today has an expiry date.
    //
    // `screens/provider/features/` is NOT in scope — `dartFiles` excludes the
    // flag-hidden V2/V3 screens (§22) and the motion pins inherit that. Named
    // here because inheriting an exclusion silently is how one gets forgotten.
    final animationFiles = dartFiles
        .where(
          (f) =>
              f.path.contains('/screens/') ||
              f.path.contains('/widgets/') ||
              f.path.contains('/core/router/'),
        )
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
      expect(
        animationFiles.length,
        greaterThan(100),
        reason: 'the animation pins are scanning an empty or truncated set',
      );
    });

    test('motion duration is a token — no raw milliseconds (§9)', () {
      expect(
        animationOffenders(RegExp(r'Duration\(milliseconds:')),
        isEmpty,
        reason:
            'use AppMotion.* (stagger/fast/base/emphasis/slow = '
            '50/100/200/300/400ms). A hand-written number is how 240ms and '
            '220ms came to sit next to 200ms doing the same job.',
      );
    });

    test('motion curve is a token — no raw Curves.* (§9)', () {
      expect(
        animationOffenders(RegExp(r'Curves\.')),
        isEmpty,
        reason:
            'each §9 token names its curve: use AppMotion.*Curve. '
            'The pairing is the rule — entering decelerates, exiting '
            'accelerates — and a bare Curves.easeIn on an ENTERING fade is '
            'exactly the inversion the tokens exist to prevent.',
      );
    });

    // ── The two holes the review found in the pins above. Both are at ZERO
    // today, so neither has ever gone red on real code — they are guard rails,
    // not discoveries, and each is proven by a throwaway mutation instead.
    // Saying so is the difference between a pin and a claim.

    test('…and no hand-rolled easing curve either (§9)', () {
      // `Curves.` is the idiom, not the language. Every name below is a `Curve`
      // subclass that defines an easing SHAPE while containing no `Curves.` —
      // so `curve: const Cubic(0.9, 0, 1, 1)` sailed straight past.
      //
      // `Interval(` is deliberately absent: it stages WHEN a curve runs, not
      // how it eases, and the curve inside it is caught by the rule above.
      expect(
        animationOffenders(
          RegExp(
            r'\b(Cubic|ElasticInCurve|ElasticOutCurve|ElasticInOutCurve|'
            r'SawTooth|Threshold|FlippedCurve|CatmullRom)\(',
          ),
        ),
        isEmpty,
        reason:
            'an easing shape is a token (AppMotion.*Curve), not four '
            'hand-tuned control points',
      );
    });

    test('no animation is measured in SECONDS (§9)', () {
      // The `milliseconds`-only rule has a role gap: §9's ladder tops out at
      // 400ms, so nothing in seconds can BE a token — but that argues a seconds
      // literal is WRONG, not that it should be invisible.
      //
      // Argument-position on purpose, and the narrowness is the point: the 11
      // `Duration(seconds:` in these directories are OTP cooldowns, a cache
      // timeout, the story dwell and §15's snackbar ladder — none of them
      // motion, none of them this slice's to relabel. This catches the one
      // shape that could only ever be motion.
      expect(
        animationOffenders(
          RegExp(
            r'(duration|transitionDuration|reverseDuration):\s*'
            r'(const\s+)?Duration\(seconds:',
          ),
        ),
        isEmpty,
        reason:
            'an animation longer than motionSlow reads as lag, not '
            'response (§9) — and a whole second is 2.5× the ceiling',
      );
    });

    // ── A9: one spelling per character (SYSTEM.md §17.1).
    //
    // §17 had no typography rule and §20 had no §17 row — the only substantive
    // section with neither, and the copy drifted accordingly: the app shipped
    // `Chargement...` in one file and `Chargement…` in another. The rules were
    // written into §17.1 first; these enforce them.
    //
    // Scoped to the same directories as the motion pins, and matching only
    // inside SINGLE-QUOTED STRINGS — a `...` in a doc comment is prose, and a
    // `\'` outside a string does not exist in Dart. The doc comments in this
    // repo are dense with quoted French copy, so a naive whole-line match would
    // flag the documentation for describing the defect it documents.

    // **A pin that names a forbidden literal is a hazard to its own sweep.**
    // The scan below only reads `lib/`, so it never sees this file — but the
    // script that APPLIED these rules walked `test/` too, rewrote `'...'` to
    // `'…'` inside `bad`, and inverted the rule: it began flagging every
    // correct character. Caught because 8 legitimate `…` sites turned red at
    // once. Any future mechanical sweep must exclude this file by name.

    /// Every Dart string literal on [line], with its quotes — **both quote
    /// styles**, because they hide the apostrophe differently.
    ///
    /// In `'l\'équipe'` it is an escape; in `"l'équipe"` it is a bare
    /// character needing no escape at all. A pin that only knew the first form
    /// would wave the second through — and the three tests that broke this
    /// sweep were all double-quoted precisely because the author was avoiding
    /// the escape.
    List<String> stringsIn(String line) => RegExp(
      '\'(?:[^\'\\\\]|\\\\.)*\'|"(?:[^"\\\\]|\\\\.)*"',
    ).allMatches(line).map((m) => m.group(0)!).toList();

    /// Does [literal] contain a straight apostrophe, in whichever form its
    /// quoting requires?
    bool hasStraightApostrophe(String literal) => literal.startsWith("'")
        ? literal.contains("\\'")
        : literal.substring(1, literal.length - 1).contains("'");

    // **Wider scope than the motion pins, on purpose.** Motion lives in
    // `screens/` + `widgets/` + `core/router/`; user-facing FRENCH lives
    // wherever a string reaches a user — `core/utils/message_templates.dart`,
    // `core/utils/team_error_messages.dart`, the `services/api/*` error
    // strings. Scoped to `animationFiles` this pin measured 24 offenders; over
    // `dartFiles` it measures the real number. A pin whose scope is inherited
    // rather than chosen enforces the rule somewhere other than where it
    // applies.
    /// Offenders judged on the RAW LINE rather than on parsed literals — for
    /// patterns a literal parser structurally cannot reach (see the apostrophe
    /// rule below).
    List<String> lineOffenders(bool Function(String line) bad) {
      final hits = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].trimLeft();
          if (code.startsWith('//') || code.startsWith('///')) continue;
          if (lines[i].contains('// ds-ignore')) continue;
          if (bad(lines[i])) {
            hits.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      return hits;
    }

    List<String> stringOffenders(bool Function(String literal) bad) {
      final hits = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].trimLeft();
          if (code.startsWith('//') || code.startsWith('///')) continue;
          if (lines[i].contains('// ds-ignore')) continue;
          if (stringsIn(lines[i]).any(bad)) {
            hits.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      return hits;
    }

    /// **Every pin in the suite, checked for the injury A9 inflicted on four
    /// of them.** The typography sweep walked `test/`, converted `'` to `’`
    /// inside patterns that hold the forbidden character as DATA, and silently
    /// disabled: this file's two §17.1 rules, `status_labels_test`'s three
    /// vocabulary regexes, and — worst, because it belongs to an earlier slice
    /// — `salon_time_pin_test`'s `'Africa/Abidjan'` firewall.
    ///
    /// The first repair was "exclude this file by name". That was one file too
    /// narrow, and the next pin will have the same property and a different
    /// name. This is the general form: **`’` cannot delimit a Dart string or
    /// appear in an identifier, so a pin searching for one can never match.**
    /// It fails in the same commit that breaks it, whatever the file is called.
    test('no pin searches for a character Dart source cannot contain', () {
      final pins = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .toList();
      expect(pins, isNotEmpty);

      // Built from code points, not written literally — otherwise this line
      // is itself a pattern containing the forbidden characters, and the rule
      // flags its own detector. (It did, on the first run.) It also makes THIS
      // pin immune to the sweep that broke the other four.
      final curlyQuote = String.fromCharCode(0x2019);
      final ellipsis = String.fromCharCode(0x2026);

      final dead = <String>[];
      for (final file in pins) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          // A pattern is code that SEARCHES source: a RegExp, a grep token, a
          // contains(). A curly quote inside one is always a corrupted pin.
          final isPattern =
              line.contains('RegExp(') ||
              line.contains('token:') ||
              line.contains('.contains(');
          if (isPattern &&
              (line.contains(curlyQuote) || line.contains(ellipsis))) {
            dead.add('${file.path}:${i + 1}  ${line.trim()}');
          }
        }
      }

      expect(
        dead,
        isEmpty,
        reason:
            'this pattern can never match — a curly quote and an '
            'ellipsis character do not appear in '
            'Dart syntax, so the pin is a no-op that passes vacuously. Four '
            'pins were disabled this way in one commit, and the suite stayed '
            'green through all of them.',
      );
    });

    test('a grid tile that holds text has no fixed aspect ratio (§13.3, A12)', () {
      // `childAspectRatio` freezes tile HEIGHT as a multiple of tile WIDTH, and
      // width does not move with the OS text scale — so the tile is the same
      // height at 100% and at 200%, forever. §13.3 already says "a box that
      // contains text may not have a fixed height"; this is the first thing
      // that enforces it.
      //
      // Two sites, both §21 row 68 findings: the pro dashboard's action grid
      // (1.1 → a tile frozen at 143.6dp, where « Rendez-vous » wraps to two
      // lines and runs past it while « Disponibilité » cannot break at all and
      // is clipped) and the provider grid (0.75).
      //
      // **A prohibition, not a conditional** — so unlike the `isExpanded` pin
      // below it needs no non-empty guard on its own hits (after the fixes the
      // correct count is ZERO), no inferred-generic form to miss
      // (`childAspectRatio:` is a named argument, spelled identically by
      // `GridView.count`, `.builder`, `.extent` and every
      // `SliverGridDelegateWith*`), and no lookahead window that could cover
      // two sites. The corpus guard above is what keeps it honest.
      //
      // A grid of IMAGES may legitimately fix its ratio and declares
      // `// ds-ignore` on the line, the escape `offenders` already honours. A
      // grid of text uses `mainAxisExtent`, or a `Wrap`.
      expect(
        dartFiles.length,
        greaterThan(100),
        reason: 'this pin is scanning an empty or truncated set',
      );
      expect(
        offenders(RegExp(r'childAspectRatio:')),
        isEmpty,
        reason:
            'a tile height derived from its WIDTH cannot grow with the text '
            'inside it. At 200% the label either overflows the tile or is '
            'clipped without throwing — and a clip inside a fixed box is the '
            'one shape neither `takeException` nor the truncation walk can see.',
      );
    });

    // ── A14b: nothing in `lib/` opts out of the OS text scale (§13.3).
    //
    // Named so the falsifiability case below can point at the same object the
    // rule uses. A pin proven able to fire by a *copy* of its pattern proves
    // nothing about the pattern that ships.
    final noScalingPattern = RegExp(r'TextScaler\.noScaling|withNoTextScaling');

    test('no widget opts out of the OS text scale (§13.3, A14b)', () {
      // This is the rule Flutter breaks, and the reason A14b exists.
      // `time_picker.dart:387` passes `textScaler: TextScaler.noScaling` to the
      // hour and the minute — the dialog's largest text, displayLarge at 57sp —
      // so the field is the same size at 100% and at 200%, forever. :528 does it
      // to the separator and :2263 wraps the input mode in
      // `MediaQuery.withNoTextScaling`.
      //
      // That is worse than a clip, and it is worse for a specific reason: a clip
      // is visible. A control that silently ignores the accessibility setting
      // looks correct in every screenshot and every golden, at every scale.
      //
      // §13.3 says 200% is a first-class input. These two APIs are the only way
      // to say "not for this widget" — so the app should be unable to grow its
      // own copy, in a picker or anywhere else. A genuine exception (a fixed-
      // geometry canvas overlay, say) declares `// ds-ignore` and says why.
      expect(
        dartFiles.length,
        greaterThan(100),
        reason: 'this pin is scanning an empty or truncated set',
      );
      expect(
        offenders(noScalingPattern),
        isEmpty,
        reason:
            'this widget renders the same size at 100% and 200% text. The '
            'user turned the setting on and the app decided not to listen — '
            'which no golden, no clip gate and no `takeException` can see.',
      );
    });

    test('…and that rule is able to fail (§21 row 67)', () {
      // **Green from birth is row 67's exact trap:** six helpers shipped unable
      // to fail, and the count above is legitimately zero today, so `isEmpty`
      // passing proves nothing about the pattern. The corpus guard shows it is
      // reading files; this shows it would recognise the thing if it were in
      // one. Both halves are needed.
      //
      // And the whole rule was **watched go red end-to-end**, not just proven
      // here: `textScaler: TextScaler.noScaling` was planted on the day cell at
      // `myweli_date_picker.dart:521` and the sweep reported
      //
      //   Expected: empty
      //     Actual: ['lib/widgets/common/myweli_date_picker.dart:521  …']
      //
      // before it was reverted. A regex proven to match a string in this file is
      // not the same evidence as the sweep finding it in `lib/`.
      expect(
        noScalingPattern.hasMatch(
          '      child: Text(t, textScaler: TextScaler.noScaling),',
        ),
        isTrue,
        reason:
            'the pin cannot see the literal it exists to forbid — this is '
            'the line copied from time_picker.dart:387',
      );
      expect(
        noScalingPattern.hasMatch('      child: MediaQuery.withNoTextScaling('),
        isTrue,
        reason: 'the pin sees only one of the two opt-outs',
      );
      // And the other side: it must not fire on the CORRECT idiom, or the fix
      // for a hit would be to stop scaling properly.
      expect(
        noScalingPattern.hasMatch(
          '      final s = MediaQuery.textScalerOf(context).scale(line);',
        ),
        isFalse,
        reason:
            'the pin flags the right way to read the scale, so obeying it '
            'would mean removing the scaling this rule exists to protect',
      );
    });

    test('every form dropdown sets isExpanded (A11 C8, §13.3)', () {
      // A `DropdownButtonFormField` sizes its button to the WIDEST item's
      // intrinsic width unless told otherwise, so the field overflows the
      // moment the longest label stops fitting. `pro_register_screen.dart`
      // overflowed by **79px** at 360dp × 200% text on « Institut de
      // manucure » — measured on a 360dp Android device, then in
      // `test/a11y/auth_layout_test.dart`.
      //
      // Discovered, not listed: three sites were fixed, and the fourth
      // dropdown to be written is the one this exists for.
      //
      // **Four ways the first version of this pin could pass on nothing**, all
      // closed below and all found by review rather than by it failing:
      //   1. no guard that it found ANY dropdown;
      //   2. matching `DropdownButtonFormField<` missed the inferred-generic
      //      form, `DropdownButtonFormField(` — legal Dart, and silently
      //      exempt;
      //   3. the window was not comment-filtered, so a docstring saying
      //      "`isExpanded: true` is set below" satisfied it;
      //   4. a 30-line window let ONE `isExpanded` cover two dropdowns in the
      //      same form.
      final found = <String>[];
      final missing = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (!line.contains('DropdownButtonFormField')) continue;
          final site = '${file.path}:${i + 1}';
          found.add(site);

          // Twelve lines, comment-stripped, and stopping at the NEXT dropdown
          // so one flag can never cover two.
          final window = <String>[];
          for (var k = i + 1; k < lines.length && k <= i + 12; k++) {
            if (lines[k].contains('DropdownButtonFormField')) break;
            if (lines[k].trimLeft().startsWith('//')) continue;
            window.add(lines[k]);
          }
          if (!window.join('\n').contains('isExpanded: true')) {
            missing.add(site);
          }
        }
      }

      expect(
        found,
        isNotEmpty,
        reason:
            'no DropdownButtonFormField was found anywhere in lib/, so '
            'the assertion below is empty-set-true. Either they are all gone '
            'or this scan is resolving paths from the wrong directory.',
      );

      expect(
        missing,
        isEmpty,
        reason:
            'a form dropdown without `isExpanded: true` is as wide as '
            'its longest option, whatever the screen is. At 200% text that '
            'is off the edge, and in a release build there is no striped '
            'banner to say so.',
      );
    });

    test('one ellipsis character — … never ... (§17.1)', () {
      expect(
        stringOffenders((s) => s.contains('...')),
        isEmpty,
        reason:
            'the app shipped `Chargement...` and `Chargement…` — the same '
            'word, two spellings. Use the … character.',
      );
    });

    test('one apostrophe — ’ never the straight one (§17.1)', () {
      // **Line-level for the escaped form, literal-level for the bare one** —
      // and the asymmetry is load-bearing. A literal parser cannot see inside
      // an interpolation: in
      //
      //   'heure du salon (${countryLabel ?? 'Côte d\'Ivoire'})'
      //
      // the regex stops at the first unescaped quote and never reaches the
      // nested string. The pin passed while that exact line still held a
      // straight apostrophe; a FAILING TEST found it, not the gate.
      //
      // `\'` cannot legally appear outside a string in Dart, so scanning the
      // whole line for it is both simpler and complete. The bare `'` inside a
      // double-quoted literal still needs the parser, because a bare `'` on a
      // line is usually just a normal string's own quote.
      expect(
        lineOffenders((line) => line.contains("\\'")) +
            stringOffenders(hasStraightApostrophe),
        isEmpty,
        reason:
            "use ’ (U+2019), not \\'. Both shipped, sometimes in adjacent "
            'files. It also removes the escape, which is why the strings get '
            'shorter rather than longer.',
      );
    });

    // §17.1's third rule (A13, §21 row 41).
    //
    // « 1 prestation(s) » is an ENGLISH habit. French writes « 1 prestation »
    // and « 2 prestations », and the choice is not stylistic — the parenthetical
    // is simply not a French form.
    //
    // **Why this belongs in §17.1 and not in a style guide**, using §17.1's own
    // test: A9 added the ellipsis and apostrophe rules because *the app
    // contradicted itself* — the same word spelled two ways in adjacent files —
    // and explicitly declined to invent conventions (guillemets, the narrow
    // no-break space) that were merely absent. This is the first kind: the app
    // renders `(s)` in seven places and a correct plural in seventeen.
    //
    // **`invité(e)` is deliberately NOT in scope.** It is gender, not count; it
    // is a French administrative habit rather than an English one; and it is
    // asserted verbatim by `pro_login_invitations_test.dart`. A sweep that
    // quietly changed it would be inventing a convention, which is the thing
    // §17.1 says to take as its own decision.
    test('no parenthetical plural — « 1 prestation » never « 1 prestation(s) » '
        '(§17.1)', () {
      expect(
        stringOffenders((s) => s.contains('(s)')),
        isEmpty,
        reason:
            'French does not use the English « (s) » form. Use '
            'Formatters.count(n, singular, plural), which asks CLDR and gets '
            'n = 0 right — French puts zero in the SINGULAR, which is exactly '
            'where the app’s four hand-rolled idioms disagreed.',
      );
    });
  });
}
