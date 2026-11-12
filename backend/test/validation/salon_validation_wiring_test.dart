import 'dart:io';

import 'package:test/test.dart';

/// The composition root hands the validation record to every service whose
/// behaviour now depends on it (B0.18 — docs/design/salon-go-live-approval.md
/// §3.1, §3.4, §3.6, §5).
///
/// **The behavioural tests cannot catch an omission.** For most of these the
/// repository is an OPTIONAL constructor parameter, so the existing test
/// constructions keep compiling — and each one fails closed without it:
/// `publish` throws, « Marquer payé » republishes nothing, the scheduler
/// sends no notice, erasure leaves the request in the queue, a place change
/// e-mails nobody. Every test green, the product quietly broken: the class
/// of defect `site_rebuild_wiring_test.dart` names, so the same idiom.
void main() {
  // Comments stripped BEFORE matching: the DI site carries comments quoting
  // the exact strings this test looks for.
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
    return src.substring(open.start, end);
  }

  for (final name in const [
    'SalonProvisioningService',
    'SalonSubscriptionService',
    'SubscriptionScheduler',
    'ProviderAccountService',
    'ProviderCatalogService',
    'AdminProviderService',
    'AnalyticsService',
  ]) {
    test('$name is constructed WITH the validation repository', () {
      expect(
        construction(name),
        contains('validations: salonValidationRepository'),
      );
    });
  }

  test('the admin is told: publish and the catalogue get the admin notifier, '
      'which reads ADMIN_EMAIL', () {
    expect(
      construction('SalonProvisioningService'),
      contains('adminNotifier: adminNotifier'),
    );
    expect(
      construction('ProviderCatalogService'),
      contains('adminNotifier: adminNotifier'),
    );
    expect(construction('AdminNotifier'), contains('adminEmail: _adminEmail'));
    expect(src, contains("_adminEmail = _envOrNull('ADMIN_EMAIL')"));
  });

  test('the admin seed reads the SAME variable — one read of ADMIN_EMAIL', () {
    expect(
      RegExp(r"_envOrNull\('ADMIN_EMAIL'\)").allMatches(src),
      hasLength(1),
    );
  });
}
