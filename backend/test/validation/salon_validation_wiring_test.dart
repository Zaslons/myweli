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
    // Stage 3 (§3.5): the « Mes salons » entries say each salon's state.
    'SalonDirectoryService',
  ]) {
    test('$name is constructed WITH the validation repository', () {
      expect(
        construction(name),
        contains('validations: salonValidationRepository'),
      );
    });
  }

  test('the admin is told: publish gets the admin notifier, the catalogue '
      'the capped place notices (decision 133), and the notifier reads '
      'ADMIN_EMAIL', () {
    expect(
      construction('SalonProvisioningService'),
      contains('adminNotifier: adminNotifier'),
    );
    expect(
      construction('ProviderCatalogService'),
      contains('placeNotices: salonPlaceNoticeService'),
    );
    expect(construction('AdminNotifier'), contains('adminEmail: _adminEmail'));
    expect(src, contains("_adminEmail = _envOrNull('ADMIN_EMAIL')"));
  });

  test('the dev boot validates the seed\'s salons: right AFTER the seed, '
      'inside the same dev-only block, and nowhere else (§3.7)', () {
    // Nothing behavioural catches its removal: every seeded salon stays
    // public (the seed writes `active`), so only a restore or a republish
    // would notice it reads « never validated ».
    const seed = 'seedProvidersIfEmpty(pool, env: _env)';
    const backfill = 'backfillSalonValidationsForDev(pool, env: _env)';
    final seedAt = src.indexOf(seed);
    expect(seedAt, isNonNegative, reason: 'the dev seed is called');
    // The `if (_env == Env.dev) {` block that holds the seed, to its
    // matching brace.
    final opening = RegExp(
      r'if\s*\(\s*_env\s*==\s*Env\.dev\s*\)\s*\{',
    ).allMatches(src).where((m) => m.end <= seedAt).lastOrNull;
    expect(opening, isNotNull, reason: 'the seed sits in a dev-only block');
    var depth = 1;
    var end = opening!.end;
    while (depth > 0 && end < src.length) {
      if (src[end] == '{') depth++;
      if (src[end] == '}') depth--;
      end++;
    }
    final block = src.substring(opening.end, end);
    expect(block, contains(seed), reason: 'the seed is inside that block');
    expect(block, contains(backfill), reason: 'the backfill runs there too');
    expect(
      block.indexOf(backfill),
      greaterThan(block.indexOf(seed)),
      reason: 'after the seed, which inserts the active salons',
    );
    expect(
      'backfillSalonValidationsForDev('.allMatches(src),
      hasLength(1),
      reason:
          'never outside dev: in production it would validate whatever '
          'an older image published during a rollback (§9.3)',
    );
  });

  test('the admin seed reads the SAME variable — one read of ADMIN_EMAIL', () {
    expect(
      RegExp(r"_envOrNull\('ADMIN_EMAIL'\)").allMatches(src),
      hasLength(1),
    );
  });
}
