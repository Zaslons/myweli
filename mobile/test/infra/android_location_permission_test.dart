import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/consumer-location.md §1, §8.3 (A6, decision 272): on Android,
/// precise location is MyWeli Pro's alone.
///
/// The client centres a map and picks the nearest commune, which approximate
/// location does; without `ACCESS_FINE_LOCATION` it needs no precise-location
/// declaration on Play (due 2027-01-27). geolocator asks for exactly what the
/// merged manifest declares (`PermissionManager.java:209-232`), so the
/// manifests are the whole decision: `src/main/` declares approximate for
/// both apps, `src/pro/` adds precise, and Gradle merges it into Pro's build
/// alone.
///
/// This reads the SOURCE manifests under `android/app/src/*/` — never
/// `build/`, whose merged manifests name the permission — with XML comments
/// stripped first, since these manifests' own comments name it. What Play
/// reads is the MERGED manifest of the built APK, which a plugin could
/// change: CI's `apk-size` job reads the client's with
/// `tool/verify_android_location.sh` (guarded by
/// backend/test/infra/android_location_test.dart).
void main() {
  const fine = 'android.permission.ACCESS_FINE_LOCATION';
  const coarse = 'android.permission.ACCESS_COARSE_LOCATION';

  /// Every source manifest, by its source set: `main`, `pro`, `debug`, …
  final manifests = {
    for (final dir in Directory(
      'android/app/src',
    ).listSync().whereType<Directory>())
      if (File('${dir.path}/AndroidManifest.xml').existsSync())
        dir.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last: File('${dir.path}/AndroidManifest.xml')
            .readAsStringSync()
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ''),
  };

  /// The `<uses-permission…>` elements of any form (`-sdk-23` included) that
  /// name [permission].
  List<String> declarations(String manifest, String permission) =>
      RegExp(r'<uses-permission(?:-sdk-23)?\s[^>]*>', dotAll: true)
          .allMatches(manifest)
          .map((m) => m.group(0)!)
          .where((e) => e.contains('android:name="$permission"'))
          .toList();

  test('the source sets were found (an empty read would pass the rest)', () {
    expect(manifests.keys, containsAll(['main', 'pro']));
  });

  test('src/main/ declares approximate location, for both apps', () {
    expect(declarations(manifests['main']!, coarse), hasLength(1));
  });

  test('only src/pro/ declares precise location', () {
    final declaring = [
      for (final MapEntry(:key, :value) in manifests.entries)
        if (declarations(value, fine).isNotEmpty) key,
    ];
    expect(declaring, ['pro']);
    expect(declarations(manifests['pro']!, fine), hasLength(1));
  });
}
