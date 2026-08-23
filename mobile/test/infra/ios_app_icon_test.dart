import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One icon, two apps — until 2026-08-23.
///
/// ## Why this file exists
///
/// `Assets.xcassets` held exactly one `AppIcon.appiconset`, and all nine build
/// configurations carried `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Not
/// because anything set it — because `setup_flavours.rb` clones the three base
/// configurations with a `Marshal` deep copy, so every flavour inherited the
/// template's value. The same mechanism that carried the inert misspelled
/// display name along for months.
///
/// So **MyWeli Pro shipped the consumer app's icon**: white mark on black, on a
/// home screen next to the consumer app wearing the identical tile. Beyond being
/// simply wrong, two store listings with one icon is how an App Store 4.3
/// (duplicate apps) conversation begins.
///
/// The art was never missing. The designer bundle carried a complete
/// `pro/ios/AppIcon.appiconset` — black mark on #FAFAFA, matching what the
/// Android Pro resources have used all along — and only the consumer half had
/// ever been installed. `branding-integration.md` §8.2 item 4 had the wiring
/// written down and undone since 2026-07-01.
///
/// A grep of the Ruby rather than an Xcode build, for the reason
/// `ios_google_client_test.dart` gives: CI has no Mac, and a missing constant is
/// exactly what a grep can see. The built artifact is checked by hand at release
/// time, which is the only thing that can see an icon.
void main() {
  /// Comments stripped — two guards in this repo have matched a string that
  /// existed only in a comment, and the block this change adds names the
  /// setting while explaining it.
  final script = File('ios/tool/setup_flavours.rb')
      .readAsStringSync()
      .split('\n')
      .map((l) => l.trimLeft().startsWith('#') ? '' : l)
      .join('\n');

  String iconFor(String flavour) {
    final table = RegExp(
      "'$flavour'\\s*=>\\s*\\{(.*?)\\}",
      dotAll: true,
    ).firstMatch(script)?.group(1);
    expect(
      table,
      isNotNull,
      reason: 'the FLAVOURS table has no $flavour entry any more',
    );
    final icon = RegExp(r"app_icon:\s*'([^']+)'").firstMatch(table!)?.group(1);
    expect(icon, isNotNull, reason: '$flavour declares no app_icon');
    return icon!;
  }

  group('each flavour gets its own icon', () {
    test('the PER-FLAVOUR assignment is the one that exists', () {
      // **Watched surviving.** The first version of this asserted only that the
      // setting name appeared somewhere in the script — and the legacy block a
      // few lines further down contains that same name. Deleting the flavour
      // loop's assignment, which is precisely the defect, left this green while
      // Pro went back to inheriting AppIcon. The value has to be `meta`, which
      // only the per-flavour loop can supply.
      expect(
        script,
        contains(
          "build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = "
          'meta[:app_icon]',
        ),
        reason:
            'without the per-flavour assignment every configuration inherits '
            'the template AppIcon through the Marshal deep copy, and Pro ships '
            'the consumer icon again — exactly how this defect arrived',
      );
    });

    test('and the two flavours are NOT the same icon', () {
      // The whole defect, in one line.
      expect(
        iconFor('consumer'),
        isNot(iconFor('pro')),
        reason: 'two store listings cannot wear one icon',
      );
    });

    test('the flavourless configurations are covered too', () {
      // Debug/Profile/Release still exist and still build the consumer app.
      expect(
        script,
        contains("FLAVOURS['consumer'][:app_icon]"),
        reason:
            'left unset the legacy configurations expand the setting to empty, '
            'which is a worse failure than the one this replaces',
      );
    });
  });

  group('every icon set the table names is real and submittable', () {
    for (final flavour in ['consumer', 'pro']) {
      test('$flavour: the set exists, with a marketing icon', () {
        final dir = Directory(
          'ios/Runner/Assets.xcassets/${iconFor(flavour)}.appiconset',
        );
        expect(
          dir.existsSync(),
          isTrue,
          reason:
              'the script names an icon set that is not in the asset catalog, '
              'so the build fails or falls back silently',
        );

        final contents =
            jsonDecode(File('${dir.path}/Contents.json').readAsStringSync())
                as Map<String, dynamic>;
        final images = (contents['images'] as List)
            .cast<Map<String, dynamic>>();

        final marketing = images.where((i) => i['idiom'] == 'ios-marketing');
        expect(
          marketing,
          isNotEmpty,
          reason:
              'App Store Connect rejects an upload with no 1024 marketing icon, '
              'and it rejects it after the archive, not before',
        );

        for (final i in images) {
          final name = i['filename'] as String?;
          if (name == null) continue;
          expect(
            File('${dir.path}/$name').existsSync(),
            isTrue,
            reason: 'Contents.json references $name, which is not there',
          );
        }
      });
    }

    test('the two sets are actually different art', () {
      // A set that exists but was copied from the consumer icon satisfies every
      // assertion above while shipping the defect.
      final a = File(
        'ios/Runner/Assets.xcassets/${iconFor('consumer')}.appiconset/Icon-1024.png',
      ).readAsBytesSync();
      final b = File(
        'ios/Runner/Assets.xcassets/${iconFor('pro')}.appiconset/Icon-1024.png',
      ).readAsBytesSync();
      expect(
        a,
        isNot(b),
        reason:
            'the Pro marketing icon is byte-identical to the consumer one — the '
            'wiring is right and the art was never replaced',
      );
    });
  });
}
