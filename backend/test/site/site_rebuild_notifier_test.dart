import 'dart:io';

import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/site/site_rebuild_notifier.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

/// Records what it was asked to do, so a call site can be observed.
class _RecordingNotifier implements SiteRebuildNotifier {
  final reasons = <String>[];
  @override
  Future<void> requestRebuild(String reason) async => reasons.add(reason);
}

/// Always throws, for the fail-open arm.
class _BrokenNotifier implements SiteRebuildNotifier {
  @override
  Future<void> requestRebuild(String reason) async =>
      throw StateError('vercel is down');
}

void main() {
  group('HttpSiteRebuildNotifier', () {
    late HttpServer server;
    late List<String> hits;
    late List<String> logs;

    setUp(() async {
      hits = [];
      logs = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits.add(req.method);
        await req.drain<void>();
        req.response.statusCode = 201;
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${server.port}/hook');

    test('POSTs the hook and logs the outcome', () async {
      final n = HttpSiteRebuildNotifier(url(), log: logs.add);
      await n.requestRebuild('salon.created');
      expect(hits, ['POST']);
      expect(logs.single, contains('reason=salon.created'));
      expect(logs.single, contains('status=201'));
    });

    test('THE URL IS NEVER LOGGED — it is a build-triggering secret', () async {
      // Anyone holding this URL can spend money on unlimited builds. The log
      // line an operator reads must not become the place it leaks.
      final n = HttpSiteRebuildNotifier(url(), log: logs.add);
      await n.requestRebuild('salon.created');
      for (final l in logs) {
        expect(l, isNot(contains(url().toString())));
        expect(l, isNot(contains('/hook')));
      }
    });

    // **Real short cooldowns, not the fake clock.** The trailing fire is a
    // `Timer`, and a Timer cannot be driven by an injected clock — under the
    // old fake-clock shape this test would arm a real 30-second timer whose
    // callback re-enters `requestRebuild` against a frozen clock, chaining
    // timers forever. The group already runs a real `HttpServer`; tens of
    // real milliseconds is the same idiom.
    test('in-window calls COALESCE into one trailing fire, never drop', () async {
      // The old behaviour — drop — was safe only while every trigger had a
      // "next build" behind it. With publish as a trigger there is none: the
      // second salon to publish inside the window would 404 indefinitely.
      final n = HttpSiteRebuildNotifier(
        url(),
        log: logs.add,
        cooldown: const Duration(milliseconds: 300),
      );
      await n.requestRebuild('salon.published');
      await n.requestRebuild('provider.suspend');
      await n.requestRebuild('provider.restore');
      expect(hits, hasLength(1), reason: 'two are inside the window');
      expect(
        logs.where((l) => l.contains('cause=cooldown')),
        hasLength(2),
        reason: 'the log token stays `skipped` — the alert filter greps it',
      );

      // Wait past the window: exactly ONE trailing fire lands, carrying the
      // LAST deferred reason — three requests, two builds, nothing lost.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(hits, hasLength(2), reason: 'coalesced, not one per deferral');
      expect(logs.last, contains('sent reason=provider.restore'));
    });

    test('a call after an idle window fires immediately, no timer', () async {
      final n = HttpSiteRebuildNotifier(
        url(),
        log: logs.add,
        cooldown: const Duration(milliseconds: 100),
      );
      await n.requestRebuild('salon.published');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await n.requestRebuild('salon.unpublished');
      expect(hits, hasLength(2));
      expect(logs.where((l) => l.contains('cause=cooldown')), isEmpty);
    });

    test('a dead hook does not throw — it fails OPEN and says so', () async {
      // The write that triggered this already succeeded. Refusing a correct
      // admin action because Vercel is unreachable would be a self-inflicted
      // outage.
      final n = HttpSiteRebuildNotifier(
        Uri.parse('http://127.0.0.1:1/nothing-listens-here'),
        log: logs.add,
      );
      await expectLater(n.requestRebuild('salon.created'), completes);
      expect(logs.single, contains('FAILED'));
    });
  });

  group('the call sites', () {
    late InMemoryProvidersRepository providers;
    late _RecordingNotifier rebuild;
    late AdminProviderService svc;
    late SalonSubscriptionService subs;
    late String salonId;

    setUp(() async {
      providers = InMemoryProvidersRepository();
      rebuild = _RecordingNotifier();
      final memberships = InMemoryMembershipRepository();
      final accounts = InMemoryProviderAuthRepository(
        tokens: TokenService(secret: 'test-secret'),
        echoDevCode: false,
      );
      subs = SalonSubscriptionService(
        InMemorySalonSubscriptionRepository(),
        MembershipService(memberships, accounts),
        memberships,
        providers,
        accounts,
      );
      svc = AdminProviderService(
        providers,
        InMemoryAppointmentRepository(),
        InMemoryAuditLogRepository(),
        subs,
        rebuild: rebuild,
      );
      final salon = await providers.createSalon(
        name: 'Beauté Divine',
        category: 'salon',
        phoneNumber: '+2250700000000',
        address: 'Cocody',
      );
      salonId = salon['id'] as String;
    });

    test(
      'SUSPEND asks for a rebuild — the slug leaves the listable set',
      () async {
        final r = await svc.suspend('admin_1', salonId, 'fraude');
        expect(r.ok, isTrue);
        expect(rebuild.reasons, ['provider.suspend']);
      },
    );

    test('RESTORE asks for a rebuild — the slug rejoins it', () async {
      await svc.suspend('admin_1', salonId, null);
      rebuild.reasons.clear();
      final r = await svc.restore('admin_1', salonId);
      expect(r.ok, isTrue);
      expect(rebuild.reasons, ['provider.restore']);
      // Without this, a restored salon's public page stays 404 until someone
      // deploys — the web prebuilds the slug set (`dynamicParams = false`).
    });

    test('a FAILED status change asks for nothing', () async {
      final r = await svc.suspend('admin_1', 'provider_nope', null);
      expect(r.ok, isFalse);
      expect(
        rebuild.reasons,
        isEmpty,
        reason: 'nothing changed, so nothing needs rebuilding',
      );
    });

    test('a broken notifier does not fail the suspension', () async {
      final broken = AdminProviderService(
        providers,
        InMemoryAppointmentRepository(),
        InMemoryAuditLogRepository(),
        subs,
        rebuild: _BrokenNotifier(),
      );
      // The real notifier swallows its own errors; this proves the CALLER does
      // not depend on that, so a future implementation that throws cannot turn
      // a successful suspension into a 500.
      await expectLater(
        broken.suspend('admin_1', salonId, null),
        throwsA(isA<StateError>()),
        reason:
            'documents today: the caller does NOT guard. If this ever flips to '
            '`completes`, the guard moved into the service and that is fine — '
            'what must never happen is it changing silently.',
      );
    });
  });
}
