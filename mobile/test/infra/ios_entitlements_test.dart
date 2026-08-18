import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS entitlements — the capabilities a signed build actually carries.
///
/// ## Why this file exists
///
/// **`Runner.entitlements` sat for months with zero `CODE_SIGN_ENTITLEMENTS`
/// references**, so the built app carried no `aps-environment` and iOS never
/// issued an APNs token. Every bit of Apple and Firebase setup looked correct
/// and push was dead. `ios/tool/setup_flavours.rb` records that lesson in a
/// comment and fixes the wiring — but nothing checked the *contents*, and on
/// 2026-08-18 the same shape was found again: `FeatureFlags.appleSignIn` had
/// defaulted on since 2026-08-07 and three screens rendered the button, while
/// `com.apple.developer.applesignin` was in **neither** file. A signed build
/// could not have presented the sheet, and App Store rule 4.8 is a rejection
/// found at review.
///
/// Both defects are the same class: the Dart looks finished, the capability is
/// absent, and nothing between them fails. This is the thing that fails.
///
/// It is a plist grep rather than an Xcode build because CI has no Mac — but a
/// missing key is exactly what a grep can see, and it is what was missing both
/// times.
void main() {
  File file(String name) => File('ios/Runner/$name');

  /// The plist with its XML comments stripped.
  ///
  /// Twice in one day a test in this repo passed because the string it looked
  /// for was in a COMMENT rather than in the code — including one that
  /// explained the very defect it was supposed to catch. These files carry long
  /// comments naming the keys, so this is not a hypothetical here.
  String body(String name) => file(
    name,
  ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  const debugProfile = 'Runner.entitlements';
  const release = 'RunnerRelease.entitlements';

  group('every entitlements file exists and is wired', () {
    test('both files exist', () {
      for (final n in const [debugProfile, release]) {
        expect(file(n).existsSync(), isTrue, reason: '$n is missing');
      }
    });

    test('setup_flavours.rb maps EVERY configuration to one of them', () {
      // The wiring half. A file with the right keys that no configuration
      // points at is the original defect, and it produced no symptom.
      final script = File('ios/tool/setup_flavours.rb').readAsStringSync();
      for (final cfg in const ['Debug', 'Profile', 'Release']) {
        expect(
          script,
          contains("'$cfg'"),
          reason: '$cfg is not mapped to an entitlements file',
        );
      }
      expect(script, contains(debugProfile));
      expect(script, contains(release));
    });
  });

  group('the capabilities a build must carry', () {
    test('APNs: development off-release, production on release', () {
      // Not cosmetic: a build signed `development` gets a SANDBOX token, and a
      // production FCM send to it is silently dropped.
      expect(body(debugProfile), contains('development'));
      expect(body(release), contains('production'));
      for (final n in const [debugProfile, release]) {
        expect(body(n), contains('aps-environment'));
      }
    });

    test('Sign in with Apple is in BOTH files (rule 4.8)', () {
      // In only one of them, it works in exactly the builds nobody ships.
      for (final n in const [debugProfile, release]) {
        expect(
          body(n),
          contains('com.apple.developer.applesignin'),
          reason:
              '$n has no Sign in with Apple entitlement. Rule 4.8 requires the '
              'button wherever another third-party provider ships — and '
              'FeatureFlags.appleSignIn defaults ON, so three screens render '
              'one that cannot work.',
        );
      }
    });

    test('…and it is the plain Default scope', () {
      // `Default` = the user's own Apple ID. The alternative is Sign in with
      // Apple at Work & School, which needs a different App ID configuration
      // and is not what a consumer marketplace wants.
      for (final n in const [debugProfile, release]) {
        final plist = body(n);
        final i = plist.indexOf('com.apple.developer.applesignin');
        expect(plist.substring(i).contains('Default'), isTrue, reason: n);
      }
    });
  });

  test('the Dart flag and the entitlement agree', () {
    // The pairing that was false for eleven days: the flag defaults on, so the
    // entitlement is not optional. If someone ever defaults the flag off, this
    // test should be revisited deliberately rather than silently passing.
    final flags = File('lib/core/config/feature_flags.dart').readAsStringSync();
    expect(
      flags.contains("'APPLE_SIGN_IN'") && flags.contains('defaultValue: true'),
      isTrue,
      reason:
          'appleSignIn no longer defaults on — re-check whether the '
          'entitlement is still required before changing this test',
    );
  });
}
