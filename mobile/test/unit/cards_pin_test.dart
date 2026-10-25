import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/hygiene-batch9.md §2.7.3 (B9.8 F2, Q10, Q13–Q15) — a card is
/// `AppCard`: `secondary`, `radiusXL`, no shadow, no border unless it is a
/// control. Pinned on the whole of `lib/`, so the card written tomorrow by
/// hand fails here the day it is written.
///
/// `screens/provider/features/` is left out on purpose: V2/V3 screens behind
/// `FeatureFlags.futureProviderFeatures`, not polished until their phase.
void main() {
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

  /// The argument list of each `BoxDecoration(` — its parentheses matched.
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

  Map<String, int> count(int Function(String source) n) => {
    for (final MapEntry(key: path, value: s) in sources().entries)
      if (n(s) > 0) path: n(s),
  };

  test('no Material `Card` — it is `AppCard`', () {
    final card = RegExp(r'(?<![A-Za-z_])Card\(');
    expect(count((s) => card.allMatches(s).length), isEmpty);
  });

  test('no card drawn by hand: a `secondary` box at the card radius', () {
    final cardRadius = RegExp(r'radius(XL|Large)\b');
    expect(
      count(
        (s) => decorations(s)
            .where(
              (d) =>
                  d.contains('AppColors.secondary') && cardRadius.hasMatch(d),
            )
            .length,
      ),
      {
        // The pinned « Total » under the booking steps: a docked bar, like
        // the bottom nav, with its shadow (Q14) — not a card in the list.
        'lib/screens/booking/booking_hub_screen.dart': 1,
        // « mercredi 11 mars 2026 › »: a field that opens the day picker,
        // drawn as one — not a card.
        'lib/widgets/booking/slot_picker.dart': 1,
      },
    );
  });

  test(
    'a page that holds cards is `background`, not `surface` (SYSTEM §3.1)',
    () {
      // White on #FAFAFA is half the surface step: six pages had leaned on the
      // shadows and borders F2 removed to keep their cards visible.
      final surfacePage = RegExp(
        r'Scaffold\(\s*(key: [^,]+,\s*)?backgroundColor: AppColors\.surface,',
      );
      expect(
        {
          for (final MapEntry(key: path, value: s) in sources().entries)
            if (path.startsWith('lib/screens/') && surfacePage.hasMatch(s))
              path,
        },
        {
          // No card on these: a sign-in form, a form, the two splashes.
          'lib/screens/admin/admin_login_screen.dart',
          'lib/screens/provider/salons/add_salon_screen.dart',
          'lib/screens/splash/splash_screen.dart',
          'lib/screens/provider/auth/pro_splash_screen.dart',
        },
      );
    },
  );

  test('a shadow only on what floats (SYSTEM §8)', () {
    final shadow = RegExp(r'AppTheme\.elevation\d');
    expect(
      count((s) => shadow.allMatches(s).length),
      {
        // Over the map: the person's dot, the salon's pin.
        'lib/screens/map/map_screen.dart': 1,
        'lib/screens/provider/profile/pro_salon_profile_screen.dart': 1,
        'lib/widgets/common/salon_map_marker.dart': 1,
        // Over a photo: the logo on the cover, the before/after handle.
        'lib/screens/providers/provider_detail_screen.dart': 1,
        'lib/widgets/providers/before_after_section.dart': 1,
        // The stories' rings, over the page's edge.
        'lib/widgets/home/announcement_stories.dart': 1,
        // The docked « Total » (Q14).
        'lib/screens/booking/booking_hub_screen.dart': 1,
        // The tokens themselves.
        'lib/core/theme/app_theme.dart': 0,
      }..removeWhere((_, n) => n == 0),
      reason:
          'a card has no shadow — the surface step lifts it; a shadow is '
          'for a menu, a sheet, the bottom nav, a pin over a map',
    );
  });
}
