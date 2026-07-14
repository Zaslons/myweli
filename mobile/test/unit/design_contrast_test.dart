import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';

import '../support/wcag.dart';

/// The design system's colour rules, EXECUTABLE (docs/design/SYSTEM.md §3, §20).
///
/// Prose drifts; a failing test cannot. Every floor in SYSTEM.md is asserted here
/// against real WCAG relative-luminance math (`test/support/wcag.dart` — the same
/// implementation the goldens use, so the two can never disagree about what
/// "passes" means).
///
/// If you are here because this went red: you did not break a test, you broke a
/// contrast floor. The failure message tells you the measured ratio.
void main() {
  // The three surfaces a token has to survive, worst → best. A token must clear
  // its floor on `background` — the worst case — to be legal anywhere.
  const surfaces = <String, Color>{
    'background': AppColors.background,
    'surface': AppColors.surface,
    'card': AppColors.secondary,
  };

  void expectFloor(String name, Color c, double floor) {
    surfaces.forEach((surfaceName, bg) {
      final ratio = contrastRatio(c, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(floor),
        reason: '$name on $surfaceName is ${ratioLabel(ratio)}:1 — '
            'below the ${floor.toStringAsFixed(1)}:1 floor.',
      );
    });
  }

  group('text — WCAG 1.4.3, 4.5:1', () {
    test('textPrimary (the ink)', () {
      expectFloor('textPrimary', AppColors.textPrimary, kFloorText);
    });

    test('textSecondary', () {
      expectFloor('textSecondary', AppColors.textSecondary, kFloorText);
    });

    test('textTertiary — the LIGHTEST legal text; nothing may go below it', () {
      expectFloor('textTertiary', AppColors.textTertiary, kFloorText);
    });

    test(
        'textDisabled is exempt (WCAG exempts inactive controls) — but exempt is '
        'not the same as invisible', () {
      // No WCAG floor. Ours: it must still read as a *disabled thing*, not as a
      // blank. The old #C0C0C0 was 1.70:1 — effectively nothing.
      expectFloor('textDisabled', AppColors.textDisabled, 2.0);
    });
  });

  group('non-text — WCAG 1.4.11, 3:1', () {
    test('borderStrong — the boundary of an interactive control', () {
      expectFloor('borderStrong', AppColors.borderStrong, kFloorNonText);
    });

    test('borderFocus — the focus ring', () {
      expectFloor('borderFocus', AppColors.borderFocus, kFloorNonText);
    });

    test('gold — gold-as-STATE (the unseen ring, the featured flag)', () {
      expectFloor('gold', AppColors.gold, kFloorNonText);
    });

    test('favorite — the heart glyph', () {
      expectFloor('favorite', AppColors.favorite, kFloorNonText);
    });

    test('the category accents (a sanctioned exception, but still legible)',
        () {
      expectFloor('categorySpa', AppColors.categorySpa, kFloorText);
      expectFloor('categoryBarber', AppColors.categoryBarber, kFloorText);
      expectFloor('categorySalon', AppColors.categorySalon, kFloorText);
    });
  });

  group('semantic', () {
    test('every status colour is legible AS TEXT', () {
      expectFloor('success', AppColors.success, kFloorText);
      expectFloor('successLight', AppColors.successLight, kFloorText);
      expectFloor('error', AppColors.error, kFloorText);
      expectFloor('errorLight', AppColors.errorLight, kFloorText);
      expectFloor('warning', AppColors.warning, kFloorText);
      expectFloor('info', AppColors.info, kFloorText);
      expectFloor('infoLight', AppColors.infoLight, kFloorText);
    });

    test('white on the filled status surfaces', () {
      for (final (name, fill) in const [
        ('success', AppColors.success),
        ('error', AppColors.error),
      ]) {
        final ratio = contrastRatio(AppColors.secondary, fill);
        expect(ratio, greaterThanOrEqualTo(kFloorText),
            reason: 'white on $name is ${ratioLabel(ratio)}:1');
      }
    });
  });

  group('the tokens that are NOT foregrounds', () {
    test(
        'warningLight is a background TINT — it fails as a foreground (1.62:1), '
        'and carries ink ON it instead', () {
      // Asserting the failure is the point: this documents WHY the token may not
      // be used as a text or icon colour, and it would go red if someone
      // "fixed" the value instead of the usage.
      expect(
        contrastRatio(AppColors.warningLight, AppColors.background),
        lessThan(kFloorNonText),
      );
      // What it IS for: ink on the tint.
      final onTint =
          contrastRatio(AppColors.textPrimary, AppColors.warningLight);
      expect(onTint, greaterThanOrEqualTo(kFloorText),
          reason: 'ink on warningLight is ${ratioLabel(onTint)}:1');
    });

    test(
        'starRating is the fill of a star GLYPH and nothing else — at 1.62:1 it '
        'can only ever be decoration, which is why the numeral carries the '
        'meaning (§3.5)', () {
      expect(
        contrastRatio(AppColors.starRating, AppColors.background),
        lessThan(kFloorNonText),
      );
      // …and why gold-as-state uses `gold`, which actually clears the floor.
      expect(
        contrastRatio(AppColors.gold, AppColors.background),
        greaterThanOrEqualTo(kFloorNonText),
      );
    });
  });

  group('the two blacks (SYSTEM.md §1)', () {
    test('primary is PINNED to pure black — it is the brand', () {
      expect(AppColors.primary, const Color(0xFF000000));
      expect(contrastRatio(AppColors.secondary, AppColors.primary), 21.0);
    });

    test('the ink is NOT the brand black — the split may not silently collapse',
        () {
      expect(
        AppColors.textPrimary,
        isNot(AppColors.primary),
        reason: 'textPrimary has been set back to the brand black. Text is '
            'never `primary` (SYSTEM.md §1): long runs of pure-black glyphs '
            'halate, which is the whole reason the ink is #1A1A1A.',
      );
      // …but softening the ink must not cost us anything: still AAA.
      expect(
        contrastRatio(AppColors.textPrimary, AppColors.background),
        greaterThanOrEqualTo(7.0),
      );
    });

    test('the three border roles are ordered: divider < border < borderStrong',
        () {
      double r(Color c) => contrastRatio(c, AppColors.background);
      expect(r(AppColors.divider), lessThan(r(AppColors.border)));
      expect(r(AppColors.border), lessThan(r(AppColors.borderStrong)));
    });
  });

  // ---------------------------------------------------------------------------
  // The grep-pins. A value can be asserted; a USAGE has to be grepped — and these
  // two usages are exactly the ones A1 exists to fix, so they are exactly the
  // ones that will creep back. Same idiom as salon_time_pin_test.dart.
  // ---------------------------------------------------------------------------
  group('usage pins', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('the ink is never used as a FILL or a STROKE (§1)', () {
      // `textPrimary` is what you read THROUGH. The moment it fills a shape or
      // strokes a border, the brand black has silently softened to #1A1A1A —
      // which is precisely what salon_picker_sheet.dart was doing.
      final offenders = <String>[];
      for (final file in dartFiles) {
        if (file.path.contains('core/theme/')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('AppColors.textPrimary')) continue;
          final isFillOrStroke = line.contains('backgroundColor:') ||
              line.contains('Border.all(') ||
              line.contains('BorderSide(') ||
              line.contains('fillColor:') ||
              line.contains('shadowColor:');
          if (isFillOrStroke) offenders.add('${file.path}:${i + 1}  $line');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'AppColors.textPrimary is INK. Use AppColors.primary for a fill '
            'or a stroke — otherwise the brand black softens to #1A1A1A:\n'
            '${offenders.join('\n')}',
      );
    });

    test('starRating only ever colours a star glyph (§3.5)', () {
      // Gold-as-STATE — a ring, a flag, a bar — must be `gold` (3.04:1), not
      // `starRating` (1.62:1, invisible). Any NEW file here is a regression.
      const allowed = {
        'lib/screens/booking/artist_selection_screen.dart',
        'lib/screens/providers/provider_detail_screen.dart',
        'lib/screens/admin/admin_moderation_screen.dart',
        'lib/screens/provider/reviews/reviews_screen.dart',
        'lib/screens/map/map_screen.dart',
        'lib/widgets/provider/provider_card.dart',
        'lib/widgets/review/review_tile.dart',
        'lib/widgets/review/submit_review_sheet.dart',
      };
      final users = dartFiles
          .where((f) => !f.path.contains('core/theme/'))
          .where((f) => f.readAsStringSync().contains('AppColors.starRating'))
          .map((f) => f.path)
          .toSet();
      expect(
        users.difference(allowed),
        isEmpty,
        reason: 'AppColors.starRating is the fill of a rating STAR and nothing '
            'else (1.62:1 — it cannot carry meaning). If this is gold-as-state, '
            'use AppColors.gold; if it really is a rating star, add the file to '
            'the allowlist above.',
      );
    });
  });
}
