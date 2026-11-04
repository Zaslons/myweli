import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/pro-app-batch7.md §2.9 (B7.9, decision 26) — both apps are
/// portrait on Android, as they are on the iPhone (`ios_store_readiness_test`
/// pins the iPhone list). One activity carries both flavours.
///
/// Android 16+ ignores an orientation lock on large screens (sw ≥ 600 dp):
/// the system rule, not ours — so a tablet still has to be usable in
/// landscape, which the tablet-emulator run checks, not this pin.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  String mainActivity() {
    final m = RegExp(
      r'<activity\s[^>]*android:name="\.MainActivity"[^>]*>',
      dotAll: true,
    ).firstMatch(manifest);
    expect(m, isNotNull, reason: 'MainActivity not found in the manifest');
    return m!.group(0)!;
  }

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
}
