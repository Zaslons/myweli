import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What App Review sees in the Pro binary, pinned where a grep can see it.
///
/// ## Why this file exists
///
/// The 2026-09-24 App Store audit of the Pro app (docs/design/app-store-forms.md
/// §1) found three things the signed IPA of 2026-08-29 got wrong, none of which
/// any test could have caught, because CI never builds iOS:
///
/// 1. **One Info.plist, literal purpose strings, two apps.** The Pro app asked
///    for location « pour afficher les salons autour de vous sur la carte » —
///    a consumer feature Pro does not have. Pro uses location to place the
///    salon's own pin. A purpose string that does not describe the use is the
///    textbook 5.1.1 rejection.
/// 2. **Pro declared iPad** (`TARGETED_DEVICE_FAMILY = "1,2"` inherited from
///    the Flutter template), which makes 13-inch iPad screenshots mandatory and
///    reviews an untested layout on iPad. A device family, once shipped, can be
///    added to but never withdrawn — so the first release goes iPhone-only.
/// 3. **file_picker 11.x linked DKImagePickerController and DKPhotoGallery**,
///    both on Apple's required-privacy-manifest list, and neither bundle carried
///    a manifest in the IPA: an ITMS-91061 refusal for a new app. 12.0.0 removed
///    that dependency chain.
///
/// The per-flavour values are written by `ios/tool/setup_flavours.rb`, so the
/// script and the generated project are both pinned: the script is the source,
/// the project is what Xcode builds. The built artifact is checked by hand at
/// release time (`plutil -p` on the IPA's Info.plist) — the only thing that
/// sees a resolved `$(SETTING)`.
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final pbxproj = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  /// Comments stripped: two guards in this repo have matched a string that
  /// existed only in a comment, and the script's comments name every setting.
  final script = File('ios/tool/setup_flavours.rb')
      .readAsStringSync()
      .split('\n')
      .map((l) => l.trimLeft().startsWith('#') ? '' : l)
      .join('\n');

  /// Every Runner-target build configuration, keyed by name, for [bundleId].
  /// Test-target configurations carry `<bundle>.RunnerTests` and are excluded
  /// by the exact `;` after the id.
  Map<String, String> runnerConfigs(String bundleId) {
    final out = <String, String>{};
    final block = RegExp(
      r'/\* ([A-Za-z-]+) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};',
      dotAll: true,
    );
    for (final m in block.allMatches(pbxproj)) {
      final body = m.group(2)!;
      if (body.contains('PRODUCT_BUNDLE_IDENTIFIER = $bundleId;')) {
        out[m.group(1)!] = body;
      }
    }
    return out;
  }

  String? setting(String body, String key) =>
      RegExp('\\b$key = ("?)(.*?)\\1;').firstMatch(body)?.group(2);

  const purposeKeys = {
    'NSLocationWhenInUseUsageDescription': 'LOCATION_USAGE_DESCRIPTION',
    'NSCameraUsageDescription': 'CAMERA_USAGE_DESCRIPTION',
    'NSPhotoLibraryUsageDescription': 'PHOTO_LIBRARY_USAGE_DESCRIPTION',
  };

  group('purpose strings are per flavour', () {
    for (final e in purposeKeys.entries) {
      test('Info.plist reads ${e.key} from \$(${e.value})', () {
        expect(
          plist,
          contains('<key>${e.key}</key>\n\t<string>\$(${e.value})</string>'),
          reason:
              'a literal here is ONE string for two apps — how Pro came to '
              'ask for location to show "salons around you" on a map it '
              'does not have',
        );
      });
    }

    test('the script assigns them from the flavour table, in the loop', () {
      // The value must be `meta[key]`, which only the per-flavour loop has;
      // a hard-coded assignment would give both apps the same string again.
      expect(
        script,
        contains(
          'PURPOSE_SETTINGS.each { |key, setting| '
          'cfg.build_settings[setting] = meta[key] }',
        ),
      );
    });

    test('every Pro configuration describes the PRO use of location', () {
      final pro = runnerConfigs('com.myweli.pro');
      expect(
        pro.keys,
        unorderedEquals(['Debug-pro', 'Profile-pro', 'Release-pro']),
      );
      for (final MapEntry(key: name, value: body) in pro.entries) {
        final loc = setting(body, 'LOCATION_USAGE_DESCRIPTION');
        expect(loc, isNotNull, reason: '$name has no location string');
        expect(
          loc,
          contains('placer votre salon'),
          reason: '$name must say why PRO asks: the salon pin',
        );
        expect(
          loc,
          isNot(contains('salons autour de vous')),
          reason: '$name carries the consumer wording — the defect itself',
        );
      }
    });

    test('every configuration defines all three, non-empty', () {
      // An empty purpose string is not a rejection, it is a crash the moment
      // the permission is requested — which is why the flavourless Debug /
      // Profile / Release configurations get the consumer values explicitly.
      final all = {
        ...runnerConfigs('com.myweli.pro'),
        ...runnerConfigs('com.myweli.app'),
      };
      expect(all.length, 9, reason: '3 pro + 6 consumer configurations');
      for (final MapEntry(key: name, value: body) in all.entries) {
        for (final key in purposeKeys.values) {
          final v = setting(body, key);
          expect(v, isNotNull, reason: '$name does not set $key');
          expect(v!.trim(), isNotEmpty, reason: '$name sets $key empty');
        }
      }
    });

    test('and the two apps say different things', () {
      final pro = runnerConfigs('com.myweli.pro')['Release-pro']!;
      final consumer = runnerConfigs('com.myweli.app')['Release-consumer']!;
      for (final key in purposeKeys.values) {
        expect(
          setting(pro, key),
          isNot(setting(consumer, key)),
          reason: 'Pro and consumer share $key again',
        );
      }
    });
  });

  group('Pro is iPhone-only for its first release', () {
    test('the script writes the device family from the flavour table', () {
      expect(
        script,
        contains(
          "cfg.build_settings['TARGETED_DEVICE_FAMILY'] = meta[:device_family]",
        ),
      );
      final proTable = RegExp(
        r"'pro'\s*=>\s*\{(.*?)\}",
        dotAll: true,
      ).firstMatch(script)?.group(1);
      expect(proTable, contains("device_family: '1'"));
    });

    test('every Pro configuration is 1 (iPhone); consumer stays "1,2"', () {
      for (final MapEntry(key: name, value: body) in runnerConfigs(
        'com.myweli.pro',
      ).entries) {
        expect(
          setting(body, 'TARGETED_DEVICE_FAMILY'),
          '1',
          reason:
              '$name declares iPad: 13-inch iPad screenshots become '
              'mandatory and the choice cannot be withdrawn once shipped',
        );
      }
      for (final MapEntry(key: name, value: body) in runnerConfigs(
        'com.myweli.app',
      ).entries) {
        expect(setting(body, 'TARGETED_DEVICE_FAMILY'), '1,2', reason: name);
      }
    });
  });

  test('the app declares French, the only language it speaks', () {
    // Without it, system UI inside the app (permission-alert buttons, the
    // document picker) falls back to English next to French purpose strings.
    expect(
      plist,
      contains(
        '<key>CFBundleLocalizations</key>\n\t<array>\n\t\t<string>fr</string>',
      ),
    );
  });

  test('file_picker is past the DK chain (>= 12)', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final m = RegExp(
      r'\n  file_picker:\n(?:    .*\n)*?    version: "(\d+)\.',
    ).firstMatch(lock);
    expect(m, isNotNull, reason: 'file_picker is no longer locked');
    expect(
      int.parse(m!.group(1)!),
      greaterThanOrEqualTo(12),
      reason:
          'file_picker <12 links DKImagePickerController + DKPhotoGallery on '
          'iOS; both need a privacy manifest the IPA did not carry (ITMS-91061)',
    );
  });
}
