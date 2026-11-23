import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

/// Two things the client app said that were not true, kept out
/// (docs/design/consumer-app-truth.md §2.3, §2.5). Comments are stripped, so a
/// sentence ABOUT the defect cannot satisfy or trip the pin.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('the scan sees the app', () {
    // A scan of nothing passes every pin below.
    expect(files.length, greaterThan(100));
  });

  test('no third-party placeholder image: a salon with no photo is drawn '
      'locally (§2.5)', () {
    final hits = [
      for (final f in files)
        if (stripDartComments(f.readAsStringSync()).contains('placeholder.com'))
          f.path,
    ];
    expect(hits, isEmpty, reason: 'fetches a third-party placeholder');
  });

  test(
    'no « Fonctionnalité à venir »: no control that does nothing (§2.3)',
    () {
      final hits = [
        for (final f in files)
          if (stripDartComments(
            f.readAsStringSync(),
          ).contains('Fonctionnalité à venir'))
            f.path,
      ];
      expect(hits, isEmpty, reason: 'placeholder content (App Review 2.1)');
    },
  );
}
