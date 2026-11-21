import 'dart:io';

import 'package:myweli_backend/src/maintenance/salon_purge_repository.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The salon purge is wired where production builds it (B0.24,
/// deleted-owner-salon-purge.md §6.7, test 22): the composition root, the
/// tick, the deletion and the manifests.
///
/// **The behavioural tests cannot catch an omission.** The deletion's
/// `purgeQueue`, `purgeNotifier` and `purgeMode` are OPTIONAL constructor
/// parameters, so a missing one compiles and every test that builds its own
/// stays green: no deleted owner's salon is ever stamped, and the job finds
/// it only by its absence of owner. A repository left in memory in
/// production would purge nothing, ever, and say zeros. The idiom of
/// `salon_place_notice_wiring_test.dart`.
void main() {
  // Comments stripped BEFORE matching: the DI site's comments name what
  // this test looks for.
  String code(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final src = code('lib/src/dependencies.dart');
  final flat = src.replaceAll(RegExp(r'\s+'), ' ');

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
        'final SalonPurgeRepository salonPurgeRepository = _pool == null '
        '? InMemorySalonPurgeRepository() '
        ': PostgresSalonPurgeRepository(_pool!);',
      ),
    );
  });

  test('the service: that repository, the real storage, the notifier, the '
      'mode and the limit from the environment', () {
    final c = construction('SalonPurgeService');
    expect(
      c,
      contains(
        'SalonPurgeService( salonPurgeRepository, storageService, '
        'salonPurgeNotifier, mode: salonPurgeMode, '
        'maxPerRun: salonPurgeMaxPerRun,',
      ),
    );
    expect(flat, contains("_envOrNull('SALON_PURGE_MODE')"));
    expect(flat, contains("_envOrNull('SALON_PURGE_MAX_PER_RUN')"));
    expect(
      construction('SalonPurgeNotifier'),
      contains(
        'SalonPurgeNotifier( membershipRepository, providersRepository, '
        'emailProvider,',
      ),
      reason: 'the budgeted provider, as every send',
    );
  });

  test('the tick runs it, last', () {
    final tick = construction('MaintenanceTick');
    expect(tick, contains('salonPurge: salonPurgeService.run'));
    expect(
      tick.indexOf('salonPurge:'),
      greaterThan(tick.indexOf('demoReset:')),
    );
  });

  test('the deletion stamps with the same repository, notifier and mode', () {
    final c = construction('ProviderAccountService');
    for (final arg in [
      'purgeQueue: salonPurgeRepository',
      'purgeNotifier: salonPurgeNotifier',
      'purgeMode: salonPurgeMode',
    ]) {
      expect(c, contains(arg), reason: arg);
    }
  });

  // The manifest is where real purges are switched on (§6.6 step 4), so its
  // value must be one the code reads — a typo would quietly rehearse.
  for (final (name, path) in [
    ('production', '../infra/gcp/service.yaml'),
    ('staging', '../infra/gcp/service-staging.yaml'),
  ]) {
    test('$name declares SALON_PURGE_MODE, and its value is a real mode', () {
      final doc = loadYaml(File(path).readAsStringSync()) as YamlMap;
      final containers =
          ((doc['spec'] as YamlMap)['template'] as YamlMap)['spec'] as YamlMap;
      final env = <String, String?>{};
      for (final c in containers['containers'] as YamlList) {
        for (final e in ((c as YamlMap)['env'] as YamlList?) ?? YamlList()) {
          final m = e as YamlMap;
          env[m['name'] as String] = m['value']?.toString();
        }
      }
      expect(env.containsKey('SALON_PURGE_MODE'), isTrue);
      final raw = env['SALON_PURGE_MODE']!;
      expect(
        SalonPurgeMode.values.map((m) => m.name),
        contains(raw.trim().toLowerCase()),
        reason: 'a mistyped mode runs as rehearse — read it here instead',
      );
    });
  }
}
