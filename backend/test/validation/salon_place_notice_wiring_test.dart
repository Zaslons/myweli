import 'dart:io';

import 'package:test/test.dart';

/// Decision 133's cap is wired where production builds it
/// (docs/design/salon-go-live-approval.md §5.1) — the composition root, the
/// middleware, the cron.
///
/// **The behavioural tests cannot catch an omission.** The catalogue's
/// `placeNotices` and the erasure's are OPTIONAL constructor parameters, so
/// a missing one compiles and every test that builds its own stays green:
/// the admin is never told of a place change, or an erased owner's phone
/// outlives them in the last reported place. A repository left in memory in
/// production would cap per instance and forget on every deploy. The idiom
/// of `salon_validation_wiring_test.dart`.
void main() {
  // Comments stripped BEFORE matching: the DI site's comments name what
  // this test looks for.
  String code(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final src = code('lib/src/dependencies.dart');
  final flat = src.replaceAll(RegExp(r'\s+'), ' ');

  /// The constructor call for [name], from `= Name(` to its closing `);`.
  String construction(String name) {
    final open = RegExp('=\\s*$name\\(').firstMatch(src);
    expect(open, isNotNull, reason: '$name is constructed in dependencies');
    final end = src.indexOf(');', open!.start);
    expect(end, isNonNegative, reason: '$name construction is terminated');
    return src.substring(open.start, end).replaceAll(RegExp(r'\s+'), ' ');
  }

  test('the repository is Postgres whenever there is a database', () {
    expect(
      flat,
      contains(
        'final SalonPlaceNoticeRepository salonPlaceNoticeRepository = '
        '_pool == null ? InMemorySalonPlaceNoticeRepository() '
        ': PostgresSalonPlaceNoticeRepository(_pool!);',
      ),
    );
  });

  test('the service is built on that repository, the validation record and '
      'the admin notifier (ADMIN_EMAIL)', () {
    expect(
      construction('SalonPlaceNoticeService'),
      contains(
        'SalonPlaceNoticeService( salonPlaceNoticeRepository, '
        'providersRepository, salonValidationRepository, adminNotifier,',
      ),
    );
  });

  test('the catalogue tells the admin THROUGH the cap', () {
    final c = construction('ProviderCatalogService');
    expect(c, contains('placeNotices: salonPlaceNoticeService'));
    expect(
      c,
      isNot(contains('adminNotifier')),
      reason: 'a direct notifier would bypass the cap',
    );
  });

  test('account erasure forgets the place last reported', () {
    expect(
      construction('ProviderAccountService'),
      contains('placeNotices: salonPlaceNoticeRepository'),
    );
  });

  test('the middleware provides the service the reminders cron reads', () {
    expect(
      code('routes/_middleware.dart').replaceAll(RegExp(r'\s+'), ' '),
      contains(
        'provider<SalonPlaceNoticeService>((_) => salonPlaceNoticeService)',
      ),
    );
  });
}
