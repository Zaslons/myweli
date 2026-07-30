import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:myweli/core/utils/app_locale.dart';
import 'package:myweli/core/utils/formatters.dart';

/// French plurals (A13, SYSTEM.md §17.1, §21 row 41).
///
/// **The whole file is about n = 0.** English and French agree at every other
/// value, which is why four hand-rolled idioms coexisted in `lib/` for months
/// without anyone noticing they disagreed: `== 1`, `<= 1`, `> 1`, and a
/// hard-coded plural all give the same answer at 1 and at 2.
void main() {
  group('Formatters.count', () {
    test('French puts ZERO in the singular', () {
      expect(Formatters.count(0, 'salon', 'salons'), '0 salon');
    });

    test('one is singular, two and up are plural', () {
      expect(Formatters.count(1, 'salon', 'salons'), '1 salon');
      expect(Formatters.count(2, 'salon', 'salons'), '2 salons');
      expect(Formatters.count(17, 'visite', 'visites'), '17 visites');
    });

    /// **The regression this helper exists to make impossible.**
    ///
    /// `Intl.plural` without an explicit `locale:` resolves through
    /// `Intl.getCurrentLocale()`, which falls back to `en_US`. English puts 0 in
    /// `other`; French puts it in `one`. So an unlocalised call is correct at
    /// every value a casual test checks and wrong at exactly the one this slice
    /// is about.
    ///
    /// `Intl.defaultLocale` is deliberately cleared here — the state a unit
    /// test that builds neither an app root nor `wrapApp` actually runs in.
    test('is correct at n = 0 even with Intl.defaultLocale unset', () {
      final saved = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = saved);
      Intl.defaultLocale = null;

      // The bug, demonstrated rather than asserted about: the English rule.
      expect(
        Intl.plural(0, one: '0 salon', other: '0 salons'),
        '0 salons',
        reason:
            'if this is « 0 salon », the fallback locale changed and the '
            'rest of this test no longer proves anything',
      );

      // And the helper, which names the locale.
      expect(Formatters.count(0, 'salon', 'salons'), '0 salon');
    });

    test('the noun-only form matches, for the split-rendering sites', () {
      expect(Formatters.plural(0, 'visite', 'visites'), 'visite');
      expect(Formatters.plural(1, 'visite', 'visites'), 'visite');
      expect(Formatters.plural(2, 'visite', 'visites'), 'visites');
    });

    test('kAppLocale is the French the helper pins to', () {
      expect(kAppLocale, 'fr_FR');
    });
  });
}
