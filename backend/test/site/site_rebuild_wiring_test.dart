import 'dart:io';

import 'package:test/test.dart';

/// The composition root actually supplies the rebuild notifier — and does NOT
/// supply it where a fire would build nothing.
///
/// **The behavioural tests cannot catch either half.** `rebuild` is an
/// OPTIONAL constructor parameter defaulting to the Noop, which is what lets
/// every existing test construction keep compiling. It also means a forgotten
/// argument is *no rebuild in production with every test green* — and that is
/// not hypothetical: `SalonProvisioningService` was constructed without it
/// from the day its `salon.created` call was written until 2026-08-25, so the
/// call had never fired in production while the launch runbook told the
/// operator to expect its log line. The same idiom as
/// `identity_limits_wiring_test.dart`, which names this defect class.
///
/// Design: docs/design/backend-web-rebuild-hook.md
void main() {
  // Comments are stripped BEFORE matching (`no_secret_in_url_test.dart`'s
  // helper shape): the DI site carries a comment QUOTING the exact string
  // this test looks for, and four guards in this repo have gone green
  // against their own explanatory comment.
  final src = File('lib/src/dependencies.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  /// The constructor call for [name], from `= Name(` to its closing `);`.
  ///
  /// A regex rather than `indexOf('= \$name(')` because half of these
  /// constructions wrap — `… =\n    SalonProvisioningService(` — and the
  /// single-line probe returns -1 for them. The vacuity expect below is what
  /// caught that: the first run of this test failed on its own scan.
  String construction(String name) {
    final open = RegExp('=\\s*$name\\(').firstMatch(src);
    expect(
      open,
      isNotNull,
      reason: '$name is constructed in dependencies.dart',
    );
    final end = src.indexOf(');', open!.start);
    expect(end, isNonNegative, reason: '$name construction is terminated');
    return src.substring(open.start, end);
  }

  group('the composition root supplies the notifier', () {
    // The five services whose status writes change the prebuilt slug set.
    for (final name in const [
      'SalonProvisioningService',
      'SalonSubscriptionService',
      'SubscriptionScheduler',
      'ProviderAccountService',
      'AdminProviderService',
    ]) {
      test('$name is constructed WITH one', () {
        expect(
          construction(name),
          contains('rebuild: siteRebuildNotifier'),
          reason:
              '$name takes an optional rebuild notifier, so omitting it here '
              'silently wires the Noop: salons publish (or unpublish) and the '
              'prebuilt slug set never learns — the page 404s (or keeps '
              'serving) until an unrelated deploy. Nothing behavioural can '
              'catch the omission, which is why this test exists.',
        );
      });
    }
  });

  test('SalonDirectoryService is constructed WITHOUT one', () {
    // The other direction, pinned per the denial rule: addSalon creates DRAFT
    // salons, which the slug set excludes, so a creation fire builds nothing
    // while consuming the notifier's cooldown window — it could swallow a
    // real publish seconds later. The parameter was deleted from the service;
    // this catches it growing back.
    expect(construction('SalonDirectoryService'), isNot(contains('rebuild')));
  });
}
