import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/pro-app-batch7.md §2.9 (B7.9, decision 26) — both apps are
/// portrait on Android, as they are on the iPhone (`ios_store_readiness_test`
/// pins the iPhone list). One activity carries both flavours.
///
/// Android 16+ ignores an orientation lock on large screens (sw ≥ 600 dp):
/// the system rule, not ours — so a tablet still has to be usable in
/// landscape, which the tablet-emulator run checks, not this pin.
///
/// **The lock must not cost any device (2026-11-19).** A
/// `screenOrientation="portrait"` makes Play infer a REQUIRED
/// `android.hardware.screen.portrait`, and Play hides the app from every
/// device that does not report that feature: 27 devices lost at build 785
/// (tablets, TV, cars), and the closed track's check named phones, tablets,
/// desktop and Android XR. The manifest therefore declares the feature
/// optional (docs/design/android-play-release.md §11, 2026-11-19).
///
/// This file reads the SOURCE manifest. What Play reads is the MERGED one in
/// the built APK, which a plugin's manifest could change: CI's `apk-size` job
/// reads that with `tool/verify_android_portrait_optional.sh`
/// (guarded by backend/test/infra/android_portrait_optional_test.dart).
void main() {
  // Comments stripped: a commented-out element is not an element, and the
  // manifest's own comments name these attributes in prose.
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  String mainActivity() {
    final m = RegExp(
      r'<activity\s[^>]*android:name="\.MainActivity"[^>]*>',
      dotAll: true,
    ).firstMatch(manifest);
    expect(m, isNotNull, reason: 'MainActivity not found in the manifest');
    return m!.group(0)!;
  }

  List<RegExpMatch> portraitFeatures() => RegExp(
    r'<uses-feature\s[^>]*android:name="android\.hardware\.screen\.portrait"[^>]*>',
    dotAll: true,
  ).allMatches(manifest).toList();

  test('MainActivity is portrait', () {
    expect(mainActivity(), contains('android:screenOrientation="portrait"'));
  });

  test(
    'no other activity in the main manifest — one lock covers both apps',
    () {
      expect(
        RegExp(r'<activity\s').allMatches(manifest).length,
        1,
        reason: 'a second activity would need its own orientation',
      );
    },
  );

  group('the lock does not make portrait a required feature', () {
    test('android.hardware.screen.portrait is declared once, optional', () {
      final features = portraitFeatures();
      expect(
        features,
        hasLength(1),
        reason:
            'without the declaration, Play infers the feature as required '
            'from the lock and hides the app from tablets, Chromebooks and XR',
      );
      // `required` defaults to true: the attribute must be there, and false.
      expect(features.single.group(0), contains('android:required="false"'));
    });

    test('at manifest level — a <uses-feature> inside <application> is '
        'not a feature declaration', () {
      final application = RegExp(
        r'<application[\s>].*?</application>',
        dotAll: true,
      ).firstMatch(manifest);
      expect(application, isNotNull, reason: 'no <application> element');
      final features = portraitFeatures();
      expect(features, hasLength(1));
      final at = features.single.start;
      expect(
        at < application!.start || at >= application.end,
        isTrue,
        reason: 'the declaration sits inside <application>',
      );
    });
  });
}
