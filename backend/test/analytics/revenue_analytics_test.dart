import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/analytics/revenue_aggregator.dart';
import 'package:myweli_backend/src/analytics/revenue_analytics_service.dart';
import 'package:myweli_backend/src/analytics/revenue_period.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/providers/[id]/analytics/revenue/appointments.dart'
    as ledger_route;
import '../../routes/providers/[id]/analytics/revenue/index.dart'
    as revenue_route;
import '../contract/openapi_shape.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// The capability override of §13.1 (« a caller without `clients.view` »):
/// today every member with money also has the clients, so the only way to
/// reach the branch is a membership double that refuses that one capability.
class _NoClientsView extends MembershipService {
  _NoClientsView(super.members, super.providerAuth);

  @override
  Future<bool> can(String accountId, String providerId, String capability) =>
      capability == Cap.clientsView
      ? Future.value(false)
      : super.can(accountId, providerId, capability);
}

/// Counts how the ledger reaches the client book: one batched read per page,
/// never a per-booking lookup.
class _CountingClients extends InMemoryClientsRepository {
  int batched = 0;
  int single = 0;

  @override
  Future<({Map<String, String> byUserId, Map<String, String> byPhone})>
  displayNamesFor(
    String providerId, {
    required Set<String> userIds,
    required Set<String> phones,
  }) {
    batched++;
    return super.displayNamesFor(providerId, userIds: userIds, phones: phones);
  }

  @override
  Future<Map<String, dynamic>?> byPhone(String providerId, String phone) {
    single++;
    return super.byPhone(providerId, phone);
  }

  @override
  Future<Map<String, dynamic>?> byUserId(String providerId, String userId) {
    single++;
    return super.byUserId(providerId, userId);
  }
}

/// `GET /providers/{id}/analytics/revenue[/appointments]` —
/// docs/design/pro-revenue-analytics.md §7, §10, §13.1 (« The ledger's client
/// name », « Handlers », « Contract », « The Accueil equality »).
void main() {
  // Wednesday 25 November 2026, 14:30 in Abidjan.
  final now = DateTime.utc(2026, 11, 25, 14, 30);
  final tokens = TokenService(secret: 'test-secret');

  late InMemoryAppointmentRepository appts;
  late InMemoryProvidersRepository providers;
  late _CountingClients clients;
  late InMemoryProviderAuthRepository providerAuth;
  late InMemoryMembershipRepository memberships;
  late MembershipService members;
  late RevenueAnalyticsService service;
  late String ownerId;
  late String ownerToken;

  Map<String, dynamic> salon(String id) => {
    'id': id,
    'name': 'Salon $id',
    'status': 'published',
    'currency': 'XOF',
    'timezone': 'Africa/Abidjan',
    'services': [
      {'id': 's1', 'name': 'Tresses', 'price': 20000, 'durationMinutes': 120},
      {'id': 's2', 'name': 'Manucure', 'price': 5000, 'durationMinutes': 45},
    ],
    'artists': [
      {'id': 'ar1', 'name': 'Aminata'},
    ],
  };

  var seq = 0;
  Future<void> book({
    required DateTime at,
    String status = 'completed',
    num price = 10000,
    String? artistId,
    String userId = 'u1',
    String? phone,
    String? channel = 'app',
    List<String> serviceIds = const ['s1'],
    String providerId = 'provider1',
    int minutes = 60,
    String currency = 'XOF',
    bool keptLines = true,
  }) async {
    await appts.create({
      'id': 'b${(seq++).toString().padLeft(3, '0')}',
      'currency': currency,
      'userId': userId,
      'providerId': providerId,
      'serviceIds': serviceIds,
      'artistId': artistId,
      'appointmentDate': at.toIso8601String(),
      'durationMinutes': minutes,
      'status': status,
      'totalPrice': price,
      'depositAmount': 0,
      'balanceDue': price,
      'cancellationWindowHours': 24,
      'clientName': null,
      'clientPhone': phone,
      'notes': null,
      'depositScreenshotUrl': null,
      'createdAt': now.toIso8601String(),
      'serviceLines': keptLines
          ? [
              for (final s in serviceIds)
                {
                  'serviceId': s,
                  'name': 'kept $s',
                  'price': price / serviceIds.length,
                  'durationMinutes': 60,
                },
            ]
          : null,
      'artistNameKept': null,
      'channel': channel,
    });
  }

  Future<String> member(
    String email,
    String role, {
    bool revoke = false,
  }) async {
    final sent = await providerAuth.requestEmailOtp(email);
    final created = await providerAuth.createMemberAccount(
      email: email,
      authProvider: 'email',
      emailCode: sent.devCode,
    );
    final row = await memberships.invite(
      providerId: 'provider1',
      email: email,
      role: role,
      artistId: role == 'staff' ? 'ar1' : null,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    await memberships.activate(row!.id, created.provider!.id);
    if (revoke) await memberships.revoke(row.id);
    return created.provider!.id;
  }

  setUp(() async {
    seq = 0;
    appts = InMemoryAppointmentRepository();
    providers = InMemoryProvidersRepository([
      salon('provider1'),
      salon('provider2'),
    ]);
    clients = _CountingClients();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    memberships = InMemoryMembershipRepository();
    members = MembershipService(memberships, providerAuth);
    service = RevenueAnalyticsService(
      members,
      appts,
      providers,
      clients,
      clock: () => now,
    );
    final reg = await providerAuth.register(
      email: 'owner@rev.pro',
      authProvider: 'google',
      googleSub: 'rev-sub-1',
      phoneNumber: '+2250500000031',
      businessName: 'X',
      businessType: 'salon',
      providerId: 'provider1',
    );
    ownerId = reg.provider!.id;
    ownerToken = tokens
        .issueAccessToken(subject: ownerId, role: 'provider')
        .token;
  });

  const month = RevenueQuery(kind: RevenuePeriodKind.month);

  Future<Map<String, dynamic>> figuresOf(
    RevenueQuery q, {
    String? account,
  }) async {
    final r = await service.revenue(account ?? ownerId, 'provider1', q);
    expect(r.error, isNull);
    return r.data!;
  }

  Map<String, dynamic> current(Map<String, dynamic> data) =>
      ((data['groups'] as List).first as Map)['current']
          as Map<String, dynamic>;

  group('who sees it (§6, §10) — deny by default, on BOTH endpoints', () {
    Future<void> expectRefused(String accountId, String providerId) async {
      final r = await service.revenue(accountId, providerId, month);
      expect(r.error, 'forbidden');
      final l = await service.ledger(
        accountId,
        providerId,
        month,
        status: RevenueLedgerStatus.completed,
        page: 1,
        pageSize: 20,
      );
      expect(l.error, 'forbidden');
    }

    test('the owner reads both', () async {
      await book(at: DateTime.utc(2026, 11, 3, 10));
      expect((await service.revenue(ownerId, 'provider1', month)).ok, isTrue);
      final l = await service.ledger(
        ownerId,
        'provider1',
        month,
        status: RevenueLedgerStatus.completed,
        page: 1,
        pageSize: 20,
      );
      expect(l.ok, isTrue);
    });

    test('Manager, Réception, Collaborateur: 403', () async {
      await expectRefused(await member('m@rev.pro', 'manager'), 'provider1');
      await expectRefused(await member('r@rev.pro', 'reception'), 'provider1');
      await expectRefused(await member('s@rev.pro', 'staff'), 'provider1');
    });

    test('a revoked member: 403', () async {
      await expectRefused(
        await member('gone@rev.pro', 'manager', revoke: true),
        'provider1',
      );
    });

    test('another salon\'s owner: 403, and the same answer for a salon '
        'that does not exist (no oracle)', () async {
      await expectRefused(ownerId, 'provider2');
      await expectRefused(ownerId, 'no-such-salon');
    });
  });

  group('the comparison, like for like, through the real reads', () {
    test(
      '25 October 14:00 is inside a 14:30 cutoff; 15:00 is outside',
      () async {
        await book(at: DateTime.utc(2026, 10, 25, 14), price: 1000);
        await book(at: DateTime.utc(2026, 10, 25, 15), price: 2000);
        await book(at: DateTime.utc(2026, 10, 30, 10), price: 4000);
        await book(at: DateTime.utc(2026, 11, 28, 10), price: 8000);
        final data = await figuresOf(month);
        final group = (data['groups'] as List).single as Map;
        expect(
          (group['current'] as Map)['completedAmount'],
          8000,
          reason: 'the current month whole, the 28th included',
        );
        expect((group['previous'] as Map)['completedAmount'], 1000);
        expect((group['previous'] as Map)['completedCount'], 1);
      },
    );

    test('a past month is compared whole', () async {
      await book(at: DateTime.utc(2026, 9, 30, 15), price: 2000);
      final data = await figuresOf(
        RevenueQuery(
          kind: RevenuePeriodKind.month,
          date: DateTime.utc(2026, 10, 10),
        ),
      );
      final group = (data['groups'] as List).single as Map;
      expect((group['previous'] as Map)['completedAmount'], 2000);
    });
  });

  group('bounds, with the salon\'s today', () {
    test('a custom range of 367 days → range_too_long', () async {
      final r = await service.revenue(
        ownerId,
        'provider1',
        RevenueQuery(
          kind: RevenuePeriodKind.custom,
          from: DateTime.utc(2025),
          to: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(r.error, 'range_too_long');
    });

    test('a date past today + 366 days → invalid_input', () async {
      final r = await service.revenue(
        ownerId,
        'provider1',
        RevenueQuery(
          kind: RevenuePeriodKind.day,
          date: DateTime.utc(2027, 11, 27),
        ),
      );
      expect(r.error, 'invalid_input');
    });
  });

  group('the ledger\'s client name (§7.2)', () {
    Future<List<Map<String, dynamic>>> items({MembershipService? as}) async {
      final s = RevenueAnalyticsService(
        as ?? members,
        appts,
        providers,
        clients,
        clock: () => now,
      );
      final r = await s.ledger(
        ownerId,
        'provider1',
        month,
        status: RevenueLedgerStatus.completed,
        page: 1,
        pageSize: 20,
      );
      expect(r.error, isNull);
      return (r.data!['items'] as List).cast<Map<String, dynamic>>();
    }

    setUp(() async {
      // An online booking: `clientName` is null by design; the salon's name
      // for the client is in its client book.
      await book(at: DateTime.utc(2026, 11, 3, 10), userId: 'u-online');
      await clients.create({
        'id': 'c-online',
        'providerId': 'provider1',
        'userId': 'u-online',
        'displayName': 'Aïcha K.',
        'phone': null,
        'tags': const <String>[],
      });
      // A booking the salon entered, found by its phone.
      await book(
        at: DateTime.utc(2026, 11, 4, 10),
        userId: 'manual',
        phone: '+2250700000201',
        channel: 'salon',
      );
      await clients.create({
        'id': 'c-guest',
        'providerId': 'provider1',
        'userId': null,
        'displayName': 'Bintou',
        'phone': '+2250700000201',
        'tags': const <String>[],
      });
      // An erased client: the row exists, unlinked — nothing resolves.
      await book(at: DateTime.utc(2026, 11, 5, 10), userId: 'u-erased');
      await clients.create({
        'id': 'c-erased',
        'providerId': 'provider1',
        'userId': null,
        'displayName': 'Client',
        'phone': null,
        'tags': const <String>[],
      });
    });

    test('an online booking shows its client-book name; a salon-entered one '
        'its phone\'s; an erased one none — and never a phone', () async {
      final byDate = {
        for (final i in await items())
          (i['appointmentDate'] as String).substring(0, 10): i,
      };
      expect(byDate['2026-11-03']!['clientDisplayName'], 'Aïcha K.');
      expect(byDate['2026-11-04']!['clientDisplayName'], 'Bintou');
      expect(byDate['2026-11-05']!.containsKey('clientDisplayName'), isFalse);
      for (final i in byDate.values) {
        expect(i.containsKey('clientPhone'), isFalse);
        expect(i.containsKey('clientName'), isFalse);
        expect(i.containsKey('userId'), isFalse);
      }
    });

    test('one batched read per page, never a per-booking lookup', () async {
      await items();
      expect(clients.batched, 1);
      expect(clients.single, 0);
    });

    test(
      'without clients.view: the field is ABSENT, and nothing is read',
      () async {
        final list = await items(as: _NoClientsView(memberships, providerAuth));
        expect(list, hasLength(3));
        for (final i in list) {
          expect(i.containsKey('clientDisplayName'), isFalse);
        }
        expect(clients.batched, 0);
      },
    );
  });

  group('the ledger lists exactly what the figures count', () {
    setUp(() async {
      final asOf = now;
      // Completed, three collaborateur states, two channels, two prestations.
      await book(at: DateTime.utc(2026, 11, 2, 9), artistId: 'ar1');
      await book(at: DateTime.utc(2026, 11, 3, 9), artistId: '');
      await book(
        at: DateTime.utc(2026, 11, 4, 9),
        serviceIds: ['s1', 's2'],
        price: 25000,
        userId: 'manual',
        channel: 'salon',
      );
      await book(
        at: DateTime.utc(2026, 11, 6, 9),
        serviceIds: ['s1', 's2'],
        price: 25000,
        keptLines: false, // an older booking, estimated
        channel: null,
      );
      // Confirmed: ended (« À clôturer »), running and later (« Prévu »).
      await book(
        at: asOf.subtract(const Duration(hours: 3)),
        status: 'confirmed',
        artistId: 'ar1',
      );
      await book(
        at: asOf.subtract(const Duration(minutes: 30)),
        status: 'confirmed',
        minutes: 180,
        artistId: 'ar2',
      );
      await book(at: DateTime.utc(2026, 11, 29, 9), status: 'confirmed');
      await book(at: DateTime.utc(2026, 11, 9, 9), status: 'noShow');
      await book(at: DateTime.utc(2026, 11, 10, 9), status: 'cancelled');
      await book(at: DateTime.utc(2026, 11, 27, 9), status: 'pending');
      // Outside the month.
      await book(at: DateTime.utc(2026, 10, 31, 23, 59));
      await book(at: DateTime.utc(2026, 12));
    });

    const filters = <String, RevenueFilters>{
      'none': RevenueFilters(),
      'artist ar1': RevenueFilters(artistId: 'ar1'),
      'no artist': RevenueFilters(artistId: RevenueFilters.none),
      'prestation s2': RevenueFilters(serviceId: 's2'),
      'channel salon': RevenueFilters(channel: 'salon'),
      'channel online': RevenueFilters(channel: 'online'),
    };
    const figureOf = {
      RevenueLedgerStatus.completed: 'completed',
      RevenueLedgerStatus.upcoming: 'upcoming',
      RevenueLedgerStatus.toClose: 'toClose',
      RevenueLedgerStatus.noShow: 'noShow',
      RevenueLedgerStatus.cancelled: 'cancelled',
    };

    for (final MapEntry(key: name, value: f) in filters.entries) {
      test('$name: for each figure, the pages add up to its count and '
          'amount', () async {
        final q = RevenueQuery(kind: RevenuePeriodKind.month, filters: f);
        final data = await figuresOf(q);
        final groups = data['groups'] as List;
        final figures = groups.isEmpty
            ? const <String, dynamic>{}
            : (groups.single as Map)['current'] as Map<String, dynamic>;
        for (final MapEntry(key: status, value: figure) in figureOf.entries) {
          var count = 0;
          var amount = 0.0;
          int? total;
          for (var page = 1; page < 20; page++) {
            final r = await service.ledger(
              ownerId,
              'provider1',
              q,
              status: status,
              page: page,
              pageSize: 2,
              asOf: DateTime.parse(data['asOf'] as String),
            );
            expect(r.error, isNull);
            final items = r.data!['items'] as List;
            total = r.data!['total'] as int;
            if (items.isEmpty) break;
            count += items.length;
            for (final i in items) {
              amount += ((i as Map)['amount'] as num).toDouble();
            }
          }
          expect(total, figures['${figure}Count'] ?? 0, reason: figure);
          expect(count, total, reason: '$figure: every page read');
          expect(amount, figures['${figure}Amount'] ?? 0, reason: figure);
        }
      });
    }
  });

  test('the Accueil equality: this month\'s « Revenus prévus » = Réalisé + '
      'Prévu + À clôturer', () async {
    await book(at: DateTime.utc(2026, 11, 2, 9), price: 12000);
    await book(at: DateTime.utc(2026, 11, 20, 9), status: 'confirmed');
    await book(
      at: DateTime.utc(2026, 11, 28, 9),
      status: 'confirmed',
      price: 7000,
    );
    await book(at: DateTime.utc(2026, 11, 29, 9), price: 3000);
    await book(at: DateTime.utc(2026, 11, 12, 9), status: 'pending');
    await book(at: DateTime.utc(2026, 11, 13, 9), status: 'noShow');
    await book(at: DateTime.utc(2026, 11, 14, 9), status: 'cancelled');
    await book(at: DateTime.utc(2026, 10, 31, 9), price: 99000);

    final dashboard = await ProviderDashboardService(
      members,
      appts,
      providers: providers,
      clock: () => now,
    ).statsFor(ownerId, 'provider1');
    final f = current(await figuresOf(month));
    expect(
      (f['completedAmount'] as num) +
          (f['upcomingAmount'] as num) +
          (f['toCloseAmount'] as num),
      dashboard.data!['monthRevenue'],
    );
    expect(dashboard.data!['monthRevenue'], 32000, reason: 'the control');
  });

  group('the ledger\'s asOf window', () {
    Future<String?> at(DateTime asOf) async => (await service.ledger(
      ownerId,
      'provider1',
      month,
      status: RevenueLedgerStatus.toClose,
      page: 1,
      pageSize: 20,
      asOf: asOf,
    )).error;

    test('within the last 24 hours: accepted', () async {
      expect(await at(now), isNull);
      expect(await at(now.subtract(const Duration(hours: 24))), isNull);
    });

    test('older, or in the future: refused', () async {
      expect(
        await at(now.subtract(const Duration(hours: 24, seconds: 1))),
        'invalid_input',
      );
      expect(await at(now.add(const Duration(seconds: 1))), 'invalid_input');
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<RevenueAnalyticsService>()).thenReturn(service);
      return context;
    }

    Request get(String path, {String? bearer = ''}) => Request.get(
      Uri.parse('http://localhost$path'),
      headers: {
        if (bearer != null)
          'Authorization': 'Bearer ${bearer.isEmpty ? ownerToken : bearer}',
      },
    );

    Future<Response> revenue(
      String query, {
      String? bearer = '',
    }) => revenue_route.onRequest(
      ctx(get('/providers/provider1/analytics/revenue?$query', bearer: bearer)),
      'provider1',
    );

    Future<Response> ledger(String query, {String? bearer = ''}) =>
        ledger_route.onRequest(
          ctx(
            get(
              '/providers/provider1/analytics/revenue/appointments?$query',
              bearer: bearer,
            ),
          ),
          'provider1',
        );

    setUp(() async {
      await book(at: DateTime.utc(2026, 11, 3, 10), artistId: 'ar1');
      await book(
        at: DateTime.utc(2026, 10, 3, 10),
        serviceIds: ['s1', 's2'],
        keptLines: false,
      );
    });

    test(
      '200 for every period, no-store, and the body the contract says',
      () async {
        final shape = OpenApiShape();
        for (final query in [
          'period=day',
          'period=week&compare=year',
          'period=month',
          'period=month&date=2026-10-15&compare=none',
          'period=year&artistId=ar1',
          'period=custom&from=2026-01-01&to=2026-12-31&serviceId=s1',
          'period=month&channel=online',
          'period=month&artistId=none',
        ]) {
          final r = await revenue(query);
          expect(r.statusCode, HttpStatus.ok, reason: query);
          expect(
            r.headers['Cache-Control'],
            'private, no-store',
            reason: query,
          );
          final body = await r.json();
          expect(
            shape.checkResponse(
              '/providers/{id}/analytics/revenue',
              'get',
              200,
              body,
            ),
            isEmpty,
            reason: query,
          );
        }
      },
    );

    test(
      'the ledger: 200, no-store, the contract — with and without names',
      () async {
        await clients.create({
          'id': 'c1',
          'providerId': 'provider1',
          'userId': 'u1',
          'displayName': 'Aïcha',
          'phone': null,
          'tags': const <String>[],
        });
        final shape = OpenApiShape();
        for (final query in [
          'period=month',
          'period=month&status=toClose&page=1&pageSize=50',
          'period=month&serviceId=s2&date=2026-10-01',
          'period=month&asOf=${Uri.encodeQueryComponent(now.toIso8601String())}',
        ]) {
          final r = await ledger(query);
          expect(r.statusCode, HttpStatus.ok, reason: query);
          expect(r.headers['Cache-Control'], 'private, no-store');
          final body = await r.json() as Map<String, dynamic>;
          expect(
            shape.checkResponse(
              '/providers/{id}/analytics/revenue/appointments',
              'get',
              200,
              body,
            ),
            isEmpty,
            reason: query,
          );
        }
        final body = await (await ledger('period=month')).json() as Map;
        expect(
          ((body['items'] as List).single as Map)['clientDisplayName'],
          'Aïcha',
        );
        final october =
            await (await ledger(
                  'period=month&serviceId=s2&date=2026-10-01',
                )).json()
                as Map;
        final row = (october['items'] as List).single as Map;
        expect(row['amount'], 2000, reason: 's2\'s estimated share of 10 000');
        expect(row['totalPrice'], 10000);
        expect(row['estimated'], isTrue);
        expect(row['serviceNames'], ['Tresses', 'Manucure']);
      },
    );

    test('each malformed parameter → 400 invalid_input', () async {
      for (final query in [
        '',
        'period=decade',
        'period=month&date=2026-13-01',
        'period=month&date=2026-02-30',
        'period=month&date=20261101',
        'period=month&date=2026-11-1',
        'period=custom&from=2026-01-01&to=2026-01-31&date=2026-01-05',
        'period=month&from=2026-01-01',
        'period=custom&from=2026-01-01',
        'period=custom&from=2026-02-01&to=2026-01-31',
        'period=month&compare=last',
        'period=month&artistId=a%20b',
        'period=month&artistId=${'a' * 65}',
        'period=month&serviceId=s.1',
        'period=month&channel=Web',
        'period=month&channel=',
        'period=day&date=2019-12-31',
        'period=day&date=2027-11-27',
      ]) {
        for (final r in [await revenue(query), await ledger(query)]) {
          expect(r.statusCode, HttpStatus.badRequest, reason: query);
          expect(await r.json(), {'error': 'invalid_input'}, reason: query);
        }
      }
    });

    test('the ledger\'s own parameters → 400 invalid_input', () async {
      final old = now.subtract(const Duration(hours: 25)).toIso8601String();
      final later = now.add(const Duration(minutes: 1)).toIso8601String();
      for (final query in [
        'period=month&status=pending',
        'period=month&page=0',
        'period=month&page=abc',
        'period=month&pageSize=0',
        'period=month&pageSize=51',
        'period=month&asOf=2026-11-25T14:00:00',
        'period=month&asOf=yesterday',
        'period=month&asOf=${Uri.encodeQueryComponent(old)}',
        'period=month&asOf=${Uri.encodeQueryComponent(later)}',
      ]) {
        final r = await ledger(query);
        expect(r.statusCode, HttpStatus.badRequest, reason: query);
        expect(await r.json(), {'error': 'invalid_input'}, reason: query);
      }
    });

    test('a custom range over 366 days → 400 range_too_long', () async {
      for (final r in [
        await revenue('period=custom&from=2025-01-01&to=2026-01-02'),
        await ledger('period=custom&from=2025-01-01&to=2026-01-02'),
      ]) {
        expect(r.statusCode, HttpStatus.badRequest);
        expect(await r.json(), {'error': 'range_too_long'});
      }
    });

    test('no token → 401; a consumer token → 403; POST → 405', () async {
      expect(
        (await revenue('period=month', bearer: null)).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await ledger('period=month', bearer: null)).statusCode,
        HttpStatus.unauthorized,
      );
      final consumer = tokens
          .issueAccessToken(subject: 'u1', role: 'customer')
          .token;
      expect(
        (await revenue('period=month', bearer: consumer)).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await ledger('period=month', bearer: consumer)).statusCode,
        HttpStatus.forbidden,
      );
      for (final handler in [revenue_route.onRequest, ledger_route.onRequest]) {
        final post = await handler(
          ctx(
            Request.post(
              Uri.parse(
                'http://localhost/providers/provider1/analytics/revenue',
              ),
              headers: {'Authorization': 'Bearer $ownerToken'},
            ),
          ),
          'provider1',
        );
        expect(post.statusCode, HttpStatus.methodNotAllowed);
      }
    });

    test('another salon → 403 on both', () async {
      for (final r in [
        await revenue_route.onRequest(
          ctx(get('/providers/provider2/analytics/revenue?period=month')),
          'provider2',
        ),
        await ledger_route.onRequest(
          ctx(
            get(
              '/providers/provider2/analytics/revenue/appointments?period=month',
            ),
          ),
          'provider2',
        ),
      ]) {
        expect(r.statusCode, HttpStatus.forbidden);
        expect(await r.json(), {'error': 'forbidden'});
      }
    });
  });
}
