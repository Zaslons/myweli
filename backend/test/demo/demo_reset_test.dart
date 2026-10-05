import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/demo/demo_reset_service.dart';
import 'package:myweli_backend/src/demo/demo_snapshot_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:test/test.dart';

import '../../routes/admin/demo/snapshot.dart' as snapshot_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// The demo salon's 7-day reset (T69) — restore, wipe, regenerate, extend.
/// Design: docs/design/backend-demo-review-account.md §6.2.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appointments;
  late InMemoryClientsRepository clients;
  late InMemorySalonSubscriptionRepository subs;
  late InMemoryMembershipRepository members;
  late InMemoryProviderAuthRepository auth;
  late InMemoryDemoSnapshotRepository snapshots;
  late DemoResetService service;
  late List<String> logs;

  final t0 = DateTime.utc(2026, 8, 26, 3);

  setUp(() {
    providers = InMemoryProvidersRepository();
    appointments = InMemoryAppointmentRepository();
    clients = InMemoryClientsRepository();
    subs = InMemorySalonSubscriptionRepository();
    members = InMemoryMembershipRepository();
    auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
    snapshots = InMemoryDemoSnapshotRepository();
    logs = [];
    service = DemoResetService(
      auth,
      providers,
      appointments,
      clients,
      subs,
      members,
      BookingService(
        providers,
        appointments,
        SlotService(providers, appointments),
        // Production's BookingService carries a ClientsService, which is what
        // auto-creates a client row from a manual booking's phone — the half
        // of the regenerated agenda this suite asserts on.
        clients: ClientsService(
          auth,
          MembershipService(members, auth),
          InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
          clients,
          appointments,
          InMemoryProviderAuditLogRepository(),
        ),
      ),
      snapshots,
      log: logs.add,
    );
  });

  /// The demo account + curated salon, provisioned the way production would
  /// — with an offer row only when [withOffer] (a demo provisioned since
  /// the companion path has no way to choose one).
  Future<String> provisionDemo({bool withOffer = true}) async {
    final reg = await auth.register(
      businessName: 'Salon Démo MyWeli',
      businessType: 'salon',
      phoneNumber: '+2250700000100',
      email: kDemoProviderEmail,
      authProvider: 'email',
      emailCode: (await auth.requestEmailOtp(kDemoProviderEmail)).code,
      providerId: 'demo-salon',
    );
    final accountId = reg.provider!.id;
    final salon = await providers.createSalon(
      name: 'Salon Démo MyWeli',
      category: 'salon',
      phoneNumber: '+2250700000100',
    );
    final id = salon['id'] as String;
    await auth.linkProvider(accountId, id);
    await members.ensureOwner(
      providerId: id,
      accountId: accountId,
      email: kDemoProviderEmail,
    );
    await providers.updateProfile(id, {
      'description': 'La vitrine de démonstration.',
      'services': [
        {'id': 's1', 'name': 'Coupe', 'active': true, 'price': 5000},
        {'id': 's2', 'name': 'Brushing', 'active': true, 'price': 7000},
      ],
    });
    if (withOffer) {
      await subs.create(
        providerId: id,
        tier: 'pro',
        trialEndsAt: t0.add(const Duration(days: 90)),
      );
    }
    return id;
  }

  test(
    'capture derives the target from the constant, never from input',
    () async {
      final id = await provisionDemo();
      final r = await service.capture(t0);
      expect(r.ok, isTrue);
      expect(r.providerId, id);
      expect((await snapshots.read())!.providerId, id);
    },
  );

  test('capture with no demo account → demo_account_missing', () async {
    final r = await service.capture(t0);
    expect(r.ok, isFalse);
    expect(r.error, 'demo_account_missing');
  });

  test('due-gating: 6 days no-op, 7 days runs, then not again for 7', () async {
    await provisionDemo();
    await service.capture(t0);

    final early = await service.tickIfDue(t0.add(const Duration(days: 6)));
    expect(early.ran, isFalse);

    final due = await service.tickIfDue(t0.add(const Duration(days: 7)));
    expect(due.ran, isTrue);

    final tooSoon = await service.tickIfDue(t0.add(const Duration(days: 8)));
    expect(tooSoon.ran, isFalse, reason: 'the clock restarted at day 7');
  });

  test('no snapshot → quiet no-op (a deployment that never set the demo up '
      'must not log daily forever)', () async {
    final r = await service.tickIfDue(t0);
    expect(r.ran, isFalse);
    expect(r.error, isNull);
    expect(logs, isEmpty);
  });

  test('the reset reverts a defaced document', () async {
    final id = await provisionDemo();
    await service.capture(t0);
    await providers.updateProfile(id, {
      'name': 'DEFACED',
      'description': 'junk',
    });

    await service.tickIfDue(t0.add(const Duration(days: 7)));
    final doc = (await providers.byId(id))!;
    expect(doc['name'], 'Salon Démo MyWeli');
    expect(doc['description'], 'La vitrine de démonstration.');
  });

  test('the reset never touches id, slug or status', () async {
    final id = await provisionDemo();
    await service.capture(t0);
    final before = (await providers.byId(id))!;

    await service.tickIfDue(t0.add(const Duration(days: 7)));
    final after = (await providers.byId(id))!;
    expect(after['id'], before['id']);
    expect(after['slug'], before['slug']);
    expect(after['status'], 'draft', reason: 'draft forever, by design');
  });

  test(
    'wipe + regenerate: reviewer junk goes, a relative agenda appears',
    () async {
      final id = await provisionDemo();
      await service.capture(t0);
      // Reviewer junk.
      for (var i = 0; i < 5; i++) {
        await appointments.create({
          'id': 'junk$i',
          'providerId': id,
          'userId': 'manual',
          'status': 'confirmed',
          'appointmentDate': '2026-01-01T09:00:00.000Z',
        });
      }

      final now = t0.add(const Duration(days: 7));
      await service.tickIfDue(now);

      final left = await appointments.listForProvider(id);
      expect(
        left.where((a) => (a['id'] as String).startsWith('junk')),
        isEmpty,
      );
      expect(left, hasLength(4), reason: 'the regenerated plan is four rows');
      // Relative to NOW, not to the capture: the demo never shows a stale week.
      final dates = left
          .map((a) => DateTime.parse(a['appointmentDate'] as String))
          .toList();
      for (final d in dates) {
        expect(now.difference(d).inDays.abs() <= 4, isTrue, reason: '$d');
      }
      // And the client book was rebuilt through the real path.
      final book = await clients.list(id, page: 1, pageSize: 20);
      expect(book.total, greaterThanOrEqualTo(1));
    },
  );

  test('the subscription never shows expired: coverage extended + notices '
      'cleared', () async {
    final id = await provisionDemo();
    await service.capture(t0);
    await subs.markNoticeIfNew(id, 'grace');

    final now = t0.add(const Duration(days: 7));
    await service.tickIfDue(now);

    final row = (await subs.byProvider(id))!;
    expect(row.paidUntil, now.add(const Duration(days: 30)));
    expect(
      await subs.markNoticeIfNew(id, 'grace'),
      isTrue,
      reason: 'the notice cycle reopened',
    );
  });

  test('A NON-DEMO-OWNED TARGET IS REFUSED, LOUDLY', () async {
    // The safety condition lives in the code, not the operator's head:
    // whatever wrote the snapshot row, the destructive half re-verifies the
    // owner independently before touching anything.
    final salon = await providers.createSalon(
      name: 'Vrai Salon',
      category: 'salon',
      phoneNumber: '+2250700000200',
    );
    final realId = salon['id'] as String;
    await members.ensureOwner(
      providerId: realId,
      accountId: 'acc-real',
      email: 'vraie@proprietaire.ci',
    );
    await snapshots.capture(
      providerId: realId,
      doc: {'name': 'OVERWRITE'},
      capturedAt: t0,
    );
    await appointments.create({
      'id': 'real1',
      'providerId': realId,
      'userId': 'manual',
      'status': 'confirmed',
      'appointmentDate': '2026-09-01T09:00:00.000Z',
    });

    final r = await service.tickIfDue(t0.add(const Duration(days: 7)));
    expect(r.ran, isFalse);
    expect(r.error, 'not_demo_owned');
    expect(logs.single, contains('REFUSED'));
    expect((await providers.byId(realId))!['name'], 'Vrai Salon');
    expect(await appointments.listForProvider(realId), hasLength(1));
    expect(
      await subs.byProvider(realId),
      isNull,
      reason: 'the offer pin writes billing state — never on a real salon',
    );
  });
  // docs/design/pro-companion-path.md §3.3 — the demo is ALWAYS on a live
  // Pro offer: the app no longer offers a choice and the demo account may
  // not make one, so the reset is the row's only writer.
  test(
    'a demo with NO offer row gets one at capture: pro, paid 30 days',
    () async {
      final id = await provisionDemo(withOffer: false);
      expect(await subs.byProvider(id), isNull);

      await service.capture(t0);
      final row = (await subs.byProvider(id))!;
      expect(row.tier, 'pro');
      expect(row.paidUntil, t0.add(const Duration(days: 30)));
      expect(
        row.trialEndsAt,
        t0.add(const Duration(days: 90)),
        reason: 'the ordinary trial clock — the backstop if resets stop',
      );
    },
  );

  test('the reset itself creates the row when absent', () async {
    final id = await provisionDemo(withOffer: false);
    // A snapshot written without the capture path (e.g. before this
    // change shipped): the reset must still leave a live row behind.
    await snapshots.capture(
      providerId: id,
      doc: (await providers.byId(id))!,
      capturedAt: t0,
    );
    expect(await subs.byProvider(id), isNull);

    final now = t0.add(const Duration(days: 7));
    final r = await service.tickIfDue(now);
    expect(r.ran, isTrue);
    final row = (await subs.byProvider(id))!;
    expect(row.tier, 'pro');
    expect(row.paidUntil, now.add(const Duration(days: 30)));
  });

  test('CAPTURE REFUSES A NON-DEMO-OWNED TARGET — no snapshot, no billing '
      'write', () async {
    // The capture writes billing state now (the offer pin), so it runs the
    // reset's owner check itself: the demo account's scalar link alone may
    // not aim a 30-day paid extension and a tier pin at someone's salon.
    final reg = await auth.register(
      businessName: 'Salon Démo MyWeli',
      businessType: 'salon',
      phoneNumber: '+2250700000100',
      email: kDemoProviderEmail,
      authProvider: 'email',
      emailCode: (await auth.requestEmailOtp(kDemoProviderEmail)).code,
    );
    final salon = await providers.createSalon(
      name: 'Vrai Salon',
      category: 'salon',
      phoneNumber: '+2250700000200',
    );
    final realId = salon['id'] as String;
    await members.ensureOwner(
      providerId: realId,
      accountId: 'acc-real',
      email: 'vraie@proprietaire.ci',
    );
    await subs.create(
      providerId: realId,
      tier: 'reseau',
      trialEndsAt: t0.add(const Duration(days: 90)),
    );
    await auth.linkProvider(reg.provider!.id, realId);

    final r = await service.capture(t0);
    expect(r.ok, isFalse);
    expect(r.error, 'not_demo_owned');
    expect(logs.single, contains('REFUSED'));
    expect(await snapshots.read(), isNull, reason: 'nothing written');
    final row = (await subs.byProvider(realId))!;
    expect(row.tier, 'reseau', reason: 'the real tier is never pinned');
    expect(row.paidUntil, isNull, reason: 'no paid coverage minted');
  });

  test(
    'the reset pins the tier back to pro and never re-mints the clock',
    () async {
      final id = await provisionDemo();
      await service.capture(t0);
      final trialEnd = (await subs.byProvider(id))!.trialEndsAt;
      // Whatever a switch made before the PUT lock existed.
      await subs.update(id, tier: 'reseau');

      final now = t0.add(const Duration(days: 7));
      await service.tickIfDue(now);
      final row = (await subs.byProvider(id))!;
      expect(row.tier, 'pro');
      expect(row.trialEndsAt, trialEnd, reason: 'an existing row is kept');
      expect(row.paidUntil, now.add(const Duration(days: 30)));
    },
  );

  /// The admin route: audited (T17) — it writes the demo's billing state.
  group('POST /admin/demo/snapshot', () {
    late InMemoryAuditLogRepository audit;

    setUp(() => audit = InMemoryAuditLogRepository());

    RequestContext ctx(String method) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost/admin/demo/snapshot'),
          headers: {
            'Authorization':
                'Bearer ${tokens.issueAccessToken(subject: 'adm1', role: 'admin').token}',
          },
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<DemoResetService>()).thenReturn(service);
      when(() => c.read<AuditLogRepository>()).thenReturn(audit);
      return c;
    }

    test('200 + ONE audit entry naming the admin and the demo salon', () async {
      final id = await provisionDemo(withOffer: false);
      final res = await snapshot_route.onRequest(ctx('POST'));
      expect(res.statusCode, HttpStatus.ok);
      expect((await res.json() as Map)['providerId'], id);
      final entry = (await audit.list()).items.single;
      expect(entry['action'], 'demo.snapshot');
      expect(entry['actorAdminId'], 'adm1');
      expect(entry['targetType'], 'provider');
      expect(entry['targetId'], id);
    });

    test('a refused capture → 409 and NO audit entry', () async {
      final res = await snapshot_route.onRequest(ctx('POST'));
      expect(res.statusCode, HttpStatus.conflict);
      expect((await res.json() as Map)['error'], 'demo_account_missing');
      expect((await audit.list()).total, 0);
    });

    test('GET → 405', () async {
      final res = await snapshot_route.onRequest(ctx('GET'));
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
