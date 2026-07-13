import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The salon-time regression firewall (docs/design/timezone-salon-time.md §8)
/// — the R6b sweep-pin idiom. A hit means new code bypassed the seam
/// (core/utils/salon_time.dart): displayed times and day boundaries are the
/// SALON's, never the device's.
void main() {
  List<String> offenders({
    required List<String> roots,
    required String token,
    List<String> allow = const [],
  }) {
    final out = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (allow.any((a) => entity.path.endsWith(a))) continue;
        if (entity.readAsStringSync().contains(token)) out.add(entity.path);
      }
    }
    return out;
  }

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
        "no 'Africa/Abidjan' STRING literal outside the seam (multi-pays "
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
}
