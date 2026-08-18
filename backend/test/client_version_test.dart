import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/admin/admin_client_version_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/client_version/client_version_repository.dart';
import 'package:myweli_backend/src/client_version/client_version_service.dart';
import 'package:test/test.dart';

import '../routes/admin/client-version/index.dart' as admin_route;
import '../routes/client-version/index.dart' as public_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// The minimum supported client version — the only lever that reaches a phone
/// we cannot otherwise reach (docs/design/client-version-gate.md).
///
/// The property under test throughout is **fail open**: every shape that is not
/// an explicit, well-formed "you are below the floor" must let the client run.
/// A gate that blocks on ambiguity is worse than no gate, because the failure it
/// produces — an app that will not start — is indistinguishable from the app
/// being broken.
void main() {
  const consumer = 'com.myweli.app';

  late InMemoryClientVersionRepository repo;
  late ClientVersionService svc;

  setUp(() {
    repo = InMemoryClientVersionRepository();
    svc = ClientVersionService(repo);
  });

  group('the verdict', () {
    Future<void> setAndroidFloor({int min = 0, int rec = 0}) => repo.setFloor(
      consumer,
      'android',
      minimumBuild: min,
      recommendedBuild: rec,
      updateUrl: 'https://play.google.com/store/apps/details?id=$consumer',
    );

    test(
      'seeded state blocks nobody — shipping the mechanism is inert',
      () async {
        // Migration 0032 seeds every row at 0/0 on purpose. If this test ever
        // fails, the mechanism has started making policy on its own.
        for (final app in const ['com.myweli.app', 'com.myweli.pro']) {
          for (final plat in const ['android', 'ios']) {
            final v = await svc.check(appId: app, platform: plat, build: 1);
            expect(v.status, ClientVersionStatus.ok, reason: '$app/$plat');
          }
        }
      },
    );

    test('below the floor → update_required, with the URL', () async {
      await setAndroidFloor(min: 5);
      final v = await svc.check(appId: consumer, platform: 'android', build: 4);
      expect(v.status, ClientVersionStatus.updateRequired);
      expect(v.updateUrl, contains('play.google.com'));
    });

    test('exactly at the floor is allowed — the floor is inclusive', () async {
      await setAndroidFloor(min: 5);
      final v = await svc.check(appId: consumer, platform: 'android', build: 5);
      expect(v.status, ClientVersionStatus.ok);
    });

    test('between floor and recommendation → update_available', () async {
      await setAndroidFloor(min: 3, rec: 7);
      expect(
        (await svc.check(
          appId: consumer,
          platform: 'android',
          build: 5,
        )).status,
        ClientVersionStatus.updateAvailable,
      );
      expect(
        (await svc.check(
          appId: consumer,
          platform: 'android',
          build: 7,
        )).status,
        ClientVersionStatus.ok,
      );
    });

    test('NO updateUrl NEVER blocks, whatever the floor says', () async {
      // The load-bearing rule: you cannot block users you have nowhere to send.
      // iOS genuinely has no store URL until App Store Connect mints the adamId,
      // and this is what makes it safe to ship the whole mechanism first.
      await repo.setFloor(
        consumer,
        'ios',
        minimumBuild: 999,
        recommendedBuild: 999,
        updateUrl: null,
      );
      final v = await svc.check(appId: consumer, platform: 'ios', build: 1);
      expect(v.status, ClientVersionStatus.ok);
      expect(v.updateUrl, isNull);
    });

    test('unknown app, unknown platform, missing build → ok', () async {
      await setAndroidFloor(min: 999);
      for (final probe in [
        () =>
            svc.check(appId: 'com.someone.else', platform: 'android', build: 1),
        () => svc.check(appId: consumer, platform: 'windows', build: 1),
        () => svc.check(appId: consumer, platform: 'android'),
        () => svc.check(build: 1),
      ]) {
        expect((await probe()).status, ClientVersionStatus.ok);
      }
    });
  });

  group('GET /client-version', () {
    RequestContext ctx(String query, {String method = 'GET'}) {
      final c = _MockRequestContext();
      final uri = Uri.parse('http://localhost/client-version?$query');
      when(
        () => c.request,
      ).thenReturn(method == 'GET' ? Request.get(uri) : Request.post(uri));
      when(() => c.read<ClientVersionService>()).thenReturn(svc);
      return c;
    }

    test('200 with the verdict; no-store, never cached', () async {
      await repo.setFloor(
        consumer,
        'android',
        minimumBuild: 9,
        recommendedBuild: 9,
        updateUrl: 'https://play.google.com/store/apps/details?id=$consumer',
      );
      final res = await public_route.onRequest(
        ctx('app=$consumer&platform=android&build=2&version=1.0.0'),
      );
      expect(res.statusCode, HttpStatus.ok);
      // An hour of cache would sit between the decision and its effect, which
      // is the entire thing this lever is for.
      expect(res.headers['Cache-Control'], 'no-store');
      final body = jsonDecode(await res.body()) as Map<String, dynamic>;
      expect(body['status'], 'update_required');
      expect(body['updateUrl'], isNotNull);
    });

    test('a malformed request is answered ok, NOT 400', () async {
      // 400 and "ok" produce the same client behaviour (it fails open), so the
      // only thing a 400 would add is a confusing log line.
      final res = await public_route.onRequest(ctx('app=&platform=&build=abc'));
      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(await res.body())['status'], 'ok');
    });

    test('platform is case-insensitive', () async {
      await repo.setFloor(
        consumer,
        'android',
        minimumBuild: 9,
        recommendedBuild: 0,
        updateUrl: 'https://play.google.com/x',
      );
      final res = await public_route.onRequest(
        ctx('app=$consumer&platform=Android&build=1'),
      );
      expect(jsonDecode(await res.body())['status'], 'update_required');
    });

    test('a wrong verb → 405', () async {
      final res = await public_route.onRequest(
        ctx('app=$consumer', method: 'POST'),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('admin control', () {
    late InMemoryAuditLogRepository audit;
    late AdminClientVersionService admin;

    setUp(() {
      audit = InMemoryAuditLogRepository();
      admin = AdminClientVersionService(repo, audit);
    });

    test('setting a floor is audited WITH the values', () async {
      final r = await admin.set(
        'admin_1',
        appId: consumer,
        platform: 'android',
        minimumBuild: 12,
        recommendedBuild: 14,
        updateUrl: 'https://play.google.com/x',
      );
      expect(r.ok, isTrue);
      final e = (await audit.list()).items.first;
      expect(e['action'], 'client_floor.set');
      // Unlike a user erasure — where metadata would be PII — the values ARE
      // the record. Without them the log says a floor moved but not to what.
      expect(e.toString(), contains('12'));
      expect(
        (await svc.check(
          appId: consumer,
          platform: 'android',
          build: 11,
        )).status,
        ClientVersionStatus.updateRequired,
      );
    });

    test('a recommendation below the floor is refused', () async {
      // Everyone below the floor is already blocked, so such a nudge could
      // never be shown. Refuse rather than store a setting with no effect.
      final r = await admin.set(
        'admin_1',
        appId: consumer,
        platform: 'android',
        minimumBuild: 10,
        recommendedBuild: 5,
        updateUrl: null,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'recommended_below_minimum');
      expect((await audit.list()).items, isEmpty);
    });

    test('an unknown app×platform is not_found, never created', () async {
      final r = await admin.set(
        'admin_1',
        appId: 'com.myweli.typo',
        platform: 'android',
        minimumBuild: 1,
        recommendedBuild: 0,
        updateUrl: null,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'not_found');
      expect((await repo.all()).length, 4, reason: 'no row invented');
    });

    test('rejects a negative or absurd floor', () async {
      for (final bad in [-1, 1000001, 'nine']) {
        final r = await admin.set(
          'admin_1',
          appId: consumer,
          platform: 'android',
          minimumBuild: bad,
          recommendedBuild: 0,
          updateUrl: null,
        );
        expect(r.ok, isFalse, reason: 'minimumBuild=$bad');
      }
    });

    test('lists all four pairs', () async {
      final r = await admin.list();
      expect((r.data! as Map)['items'], hasLength(4));
    });
  });

  group('PUT /admin/client-version', () {
    late AdminClientVersionService admin;

    RequestContext ctx(String method, {Object? body}) {
      final c = _MockRequestContext();
      final uri = Uri.parse('http://localhost/admin/client-version');
      when(() => c.request).thenReturn(
        method == 'PUT'
            ? Request(
                'PUT',
                uri,
                body: jsonEncode(body),
                headers: const {'content-type': 'application/json'},
              )
            : Request.get(uri),
      );
      when(() => c.read<AdminClientVersionService>()).thenReturn(admin);
      return c;
    }

    setUp(() {
      admin = AdminClientVersionService(repo, InMemoryAuditLogRepository());
    });

    test('GET lists; DELETE → 405', () async {
      expect(
        (await admin_route.onRequest(ctx('GET'))).statusCode,
        HttpStatus.ok,
      );
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request('DELETE', Uri.parse('http://localhost/admin/client-version')),
      );
      when(() => c.read<AdminClientVersionService>()).thenReturn(admin);
      expect(
        (await admin_route.onRequest(c)).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });

    test('an unparseable body → 400, not a crash', () async {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          'PUT',
          Uri.parse('http://localhost/admin/client-version'),
          body: 'not json',
        ),
      );
      when(() => c.read<AdminClientVersionService>()).thenReturn(admin);
      expect(
        (await admin_route.onRequest(c)).statusCode,
        HttpStatus.badRequest,
      );
    });
  });
}
