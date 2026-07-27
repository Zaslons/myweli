import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The salon-time regression firewall (docs/design/timezone-salon-time.md §8)
/// — the R6b sweep-pin idiom. A hit means new code bypassed the seam
/// (core/utils/salon_time.dart): displayed times and day boundaries are the
/// SALON's, never the device's.
///
/// **A10 adds the other half.** §18 always governed which *zone* a time renders
/// in; it never owned which *instant* "now" is, and the pins below could not see
/// the gap — they sweep `.toLocal(`, `DateFormat(` and `'Africa/Abidjan'`, never
/// the clock. The three clock pins live here rather than in their own file
/// because they enforce the same rule: a screen renders what the salon's clock
/// says, not what the machine it happens to run on says.
void main() {
  /// Every `.dart` file under [roots], minus path-suffix matches in [allow].
  List<File> sources(List<String> roots, {List<String> allow = const []}) {
    final out = <File>[];
    for (final root in roots) {
      // `listSync` throws on a MISSING directory, so a wrong cwd fails loudly
      // rather than sweeping nothing and passing — but see `the sweep is not
      // vacuous` below for the case where a root exists and yields nothing.
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (allow.any((a) => entity.path.endsWith(a))) continue;
        out.add(entity);
      }
    }
    return out;
  }

  List<String> offenders({
    required List<String> roots,
    required String token,
    List<String> allow = const [],
  }) =>
      [
        for (final f in sources(roots, allow: allow))
          if (f.readAsStringSync().contains(token)) f.path,
      ];

  group('salon-time sweep pins', () {
    test(
        'no `.toLocal(` outside the allowlisted ops console — device-tz '
        'rendering is the leak this slice killed', () {
      expect(
        offenders(
          roots: [
            'lib/screens',
            'lib/widgets',
            'lib/providers',
            'lib/services'
          ],
          token: '.toLocal(',
          allow: ['screens/admin/admin_audit_screen.dart'],
        ),
        isEmpty,
        reason: 'render with toSalonTime()/Formatters instead '
            '(core/utils/salon_time.dart)',
      );
    });

    test(
        'no direct `DateFormat(` outside core/utils/formatters.dart — the '
        'single display choke point', () {
      expect(
        offenders(
          roots: ['lib'],
          token: 'DateFormat(',
          allow: ['core/utils/formatters.dart'],
        ),
        isEmpty,
        reason: 'go through Formatters.* so salon time stays enforced in '
            'one place',
      );
    });

    test(
        'no \'Africa/Abidjan\' STRING literal outside the seam (multi-pays '
        'MP2) — per-salon timezones come from the API, the fallback lives '
        'in kSalonTz', () {
      expect(
        offenders(
          roots: ['lib'],
          token: "'Africa/Abidjan'",
          allow: ['core/utils/salon_time.dart'],
        ),
        isEmpty,
        reason: 'use kSalonTz (or better: thread the salon tz) — '
            'core/utils/salon_time.dart',
      );
    });

    test(
        'no `constants/communes.dart` import outside the mock locality seed '
        '(multi-pays MP2) — the live tree comes from GET /localities', () {
      expect(
        offenders(
          roots: ['lib'],
          token: 'constants/communes.dart',
          allow: [
            'core/constants/communes.dart',
            'services/mock/mock_locality_service.dart',
          ],
        ),
        isEmpty,
        reason: 'read localities via LocalityProvider '
            '(providers/locality_provider.dart)',
      );
    });
  });

  group('A10 — the clock seam (§18, §20.1, §21 row 23)', () {
    // The seven `lib/` files that may read the wall clock directly, each with
    // the reason it is not a render path. This list is the pin's whole content:
    // a new entry is a claim that a clock read never reaches a pixel, and it has
    // to be argued in review rather than added quietly.
    const libAllow = <String>[
      // The seam itself.
      'core/utils/app_clock.dart',
      // §22 — three render-path reads, but ZERO references outside its own
      // declaration. Shelved, not swept: converting dead code would shorten this
      // list and leave the app no more deterministic.
      'screens/provider/features/booking_journal_screen.dart',
      // Cache expiry and session expiry. Freezing these would make a frozen test
      // believe its session never expires — worse than non-determinism, because
      // it is a test that can no longer express the thing it exists to test.
      'core/utils/timeout_cache_manager.dart',
      'services/api/api_auth_service.dart',
      // `fromJson` fallbacks for a malformed payload. They DO reach a screen, but
      // only when the field is missing, which no mock and therefore no golden can
      // produce — so the seam would buy nothing here.
      'models/team_member.dart',
      'models/salon_client.dart',
      'models/kyc_document.dart',
    ];

    test(
        'no `DateTime.now()` in lib/ outside the seam — the app renders what '
        'the clock says, not what the machine says', () {
      // **Both spellings.** `DateTime.timestamp()` is Dart 3's UTC "now", and it
      // is the *likely* next offender precisely because §18 now tells authors to
      // think in UTC — nothing about the old rule would have stopped the first
      // one. Zero occurrences today; this is the pin arriving before the defect
      // rather than after it, which is the only time that is cheap.
      expect(
        [
          ...offenders(
              roots: ['lib'], token: 'DateTime.now()', allow: libAllow),
          ...offenders(
              roots: ['lib'], token: 'DateTime.timestamp()', allow: libAllow),
        ],
        isEmpty,
        reason: 'call AppClock.now() (core/utils/app_clock.dart), or better a '
            'salon_time.dart helper — a direct read cannot be frozen, and an '
            'unfreezable read on a render path is a screen that cannot be '
            'photographed (§20.1)',
      );
    });

    test(
        'no `DateTime.now()` under test/golden/ — a golden built from the wall '
        'clock is a picture of the day it was taken', () {
      // **This is the pin that is red on arrival.** `pro_screens_golden_test`
      // builds four fixtures from the wall clock, `_FixedRoster` among them, and
      // ④ moves them. It stays a failing assertion rather than an allowlisted
      // exemption because making that file honest is the whole slice.
      expect(
        [
          ...offenders(roots: ['test/golden'], token: 'DateTime.now()'),
          ...offenders(roots: ['test/golden'], token: 'DateTime.timestamp()'),
        ],
        isEmpty,
        reason: 'a golden fixture comes from the FROZEN clock — see '
            'test/support/frozen_clock.dart',
      );
    });

    test(
        'no file both freezes the clock and reads the wall clock — the silent '
        'decoupling', () {
      // **The hazard here is invisible, which is why it needs a pin.** 12
      // subscription/trial fixtures and 3 slot generators in `test/` build dates
      // from `DateTime.now()` and compare them against `SalonSubscription`, which
      // reads the seam. While nothing freezes, both are the wall clock and every
      // day count is right. The moment one of those files gains a freeze, the two
      // diverge — and a trial reading « 12 jours » instead of « 14 jours » is a
      // wrong number, not a crash. Nothing else in the suite would notice.
      //
      // A blanket ban on the token across `test/` was the first design and is the
      // wrong instrument: 38 sites, nearly all legitimate relative fixtures ("two
      // hours from now"), and banning them pushes authors toward absolute dates
      // that rot. The defect is not the read — it is the MIX.
      final mixed = [
        for (final f in sources(
          ['test'],
          // Two exemptions, and the second is a defect this pin found in ITSELF
          // on its first run.
          //
          // `clock_test.dart` is the control: it asserts the seam's default IS
          // the wall clock, and without that every other clock test would pass on
          // a seam that returned a constant always. It is the one file where the
          // mix is the point.
          //
          // This file matched because it *names* both tokens — in the search and
          // in the prose explaining it. A9 hit the same shape and built its
          // detector from `String.fromCharCode` so it could not contain what it
          // searched for; that does not work here, because the tokens also belong
          // in the comments, and a pin nobody can read is worse than one that
          // exempts itself by name.
          allow: ['unit/clock_test.dart', 'unit/salon_time_pin_test.dart'],
        ))
          if (f.readAsStringSync() case final src
              when src.contains('freezeClock') &&
                  src.contains('DateTime.now()'))
            f.path,
      ];
      expect(mixed, isEmpty,
          reason: 'this file freezes the clock, so its fixtures must come from '
              'the frozen instant (kFixedNow, or whatever was passed to '
              'freezeClock) — a fixture built from the wall clock is measured '
              'against a clock that is no longer running, and the day counts go '
              'wrong silently');
    });

    test('the sweep is not vacuous', () {
      // Every assertion above is `isEmpty`, and a sweep that reads nothing is
      // also empty. `listSync` throws on a MISSING root, but not on one that
      // exists and yields no `.dart` files — a glob narrowed in review, a
      // rename, an `allow:` entry that swallows a directory. Then all three pins
      // pass forever, green and blind.
      //
      // The floors are ~80% of today's tree (292 · 11 · 151), so they survive an
      // ordinary deletion and fail on a glob that collapses. The first draft
      // guessed `> 300` for `lib/` and was itself red — which is the argument for
      // the guard: a threshold nobody measured cannot be trusted in either
      // direction.
      // **Measured WITH the allowlist, which the first version was not.** It
      // called `sources(['lib'])` bare, so it could see a narrowed glob and a
      // rename — and was blind to the third case its own comment names. Widen
      // one `libAllow` entry to `'_screen.dart'`, a plausible-looking review
      // edit, and pin 1 exempts every screen in the app while the bare guard
      // still counts 292 and stays green. With the allowlist applied it counts
      // 214 and goes red — mutation-proven.
      expect(sources(['lib'], allow: libAllow).length, greaterThan(230));
      expect(sources(['test/golden']).length, greaterThan(8));
      expect(sources(['test']).length, greaterThan(120));
    });
  });
}
