import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// What no behavioural test can see (docs/design/infra-cron-maintenance.md):
/// the routes are wired to the real tasks with their real windows, the
/// subscriptions cron no longer carries them, and every cron route has a
/// Scheduler job declared in the repo and an entry in the contract — a route
/// nothing calls is the defect Render's dashboard jobs were.
void main() {
  final deps = File('lib/src/dependencies.dart').readAsStringSync();
  final maintenance = File(
    'routes/internal/cron/maintenance.dart',
  ).readAsStringSync();
  final subscriptions = File(
    'routes/internal/cron/subscriptions.dart',
  ).readAsStringSync();

  /// Code lines only: the routes' comments may still say what moved.
  String code(String src) =>
      src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('the maintenance route runs the tick behind the cron door', () {
    expect(maintenance, contains('cronAuth.isConfigured'));
    expect(maintenance, contains('cronAuth.authenticate('));
    expect(maintenance, contains('context.read<MaintenanceTick>().run('));
    expect(
      File('routes/_middleware.dart').readAsStringSync(),
      contains('provider<MaintenanceTick>((_) => maintenanceTick)'),
    );
  });

  test('the tick is built with each real task and its own window', () {
    for (final wiring in [
      'pruneThrottle: () => pruneAdminLoginThrottle(const Duration(hours: 24))',
      'pruneRateLimits: () => pruneRateLimitWindows(kRateLimitRetention)',
      'pruneIdempotency: () => pruneIdempotencyKeys(kIdempotencyWindow)',
      'demoReset: (now) async => (await demoResetService.tickIfDue(now)).ran',
    ]) {
      expect(deps, contains(wiring));
    }
  });

  test('the subscriptions cron is back to the offers walk only', () {
    final body = code(subscriptions);
    for (final gone in [
      'pruneAdminLoginThrottle',
      'pruneRateLimitWindows',
      'pruneIdempotencyKeys',
      'DemoResetService',
      'throttleRowsPruned',
      'rateLimitWindowsPruned',
      'idempotencyKeysPruned',
      'demoReset',
    ]) {
      expect(body, isNot(contains(gone)), reason: gone);
    }
    expect(body, contains('context.read<SubscriptionScheduler>().tick('));
  });

  final routes = Directory('routes/internal/cron')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.dart'))
      .map((n) => '/internal/cron/${n.replaceAll('.dart', '')}')
      .toList();

  test('there are three cron routes', () {
    expect(routes.toSet(), {
      '/internal/cron/reminders',
      '/internal/cron/subscriptions',
      '/internal/cron/maintenance',
    });
  });

  group('every cron route has a Scheduler job declared in the repo', () {
    final jobs = File('../infra/gcp/99-scheduler-jobs.sh').readAsStringSync();

    for (final route in routes) {
      test(route, () => expect(jobs, contains(route)));
    }

    test('their names and hours (Q1: maintenance at 03:30 UTC)', () {
      expect(
        jobs,
        contains(
          "make_job myweli-reminders     '*/15 * * * *' /internal/cron/reminders",
        ),
      );
      expect(
        jobs,
        contains(
          "make_job myweli-subscriptions '0 3 * * *'    /internal/cron/subscriptions",
        ),
      );
      expect(
        jobs,
        contains(
          "make_job myweli-maintenance   '30 3 * * *'   /internal/cron/maintenance",
        ),
      );
    });

    test('and staging’s way back creates it too', () {
      expect(
        File('../infra/gcp/90-staging.sh').readAsStringSync(),
        contains('make_job myweli-maintenance-staging'),
      );
    });
  });

  group('every cron route is in the contract (Q4)', () {
    final paths =
        (loadYaml(File('../docs/api/openapi.yaml').readAsStringSync())
                as YamlMap)['paths']
            as YamlMap;
    for (final route in routes) {
      test(route, () {
        expect(paths[route], isNotNull);
        expect((paths[route] as YamlMap)['post'], isNotNull);
      });
    }
  });
}
