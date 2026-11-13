import 'dart:io';

import 'package:test/test.dart';

/// The composition root hands the storage to `KycService` (B0.22 —
/// docs/design/pro-deletion-erase-gaps.md §3.2 point 5).
///
/// **The behavioural tests cannot catch an omission.** The storage is an
/// OPTIONAL constructor parameter, so the existing test constructions keep
/// compiling — and without it a re-submit deletes nothing: the replaced
/// document stays in the private bucket, unreferenced, outliving the
/// account. Every test green, the erasure quietly broken: the idiom of
/// `validation/salon_validation_wiring_test.dart`.
void main() {
  // Comments stripped BEFORE matching: the DI site's comments may name what
  // this test looks for.
  final src = File('lib/src/dependencies.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  /// The constructor call for [name], from `= Name(` to its closing `);`.
  String construction(String name) {
    final open = RegExp('=\\s*$name\\(').firstMatch(src);
    expect(open, isNotNull, reason: '$name is constructed in dependencies');
    final end = src.indexOf(');', open!.start);
    expect(end, isNonNegative, reason: '$name construction is terminated');
    return src.substring(open.start, end).replaceAll(RegExp(r'\s+'), ' ');
  }

  test('KycService is constructed WITH the storage and the verifier', () {
    final c = construction('KycService');
    expect(c, contains('storage: storageService'));
    expect(c, contains('verifier: uploadVerificationService'));
  });
}
