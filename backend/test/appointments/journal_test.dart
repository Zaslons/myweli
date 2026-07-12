import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/journal_service.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/arrive.dart' as arrive_route;
import '../../routes/providers/[id]/journal.dart' as journal_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// Journal J1 backend (docs/design/journal-j1-grid.md §2): the one-payload
/// day view, « Client arrivé » (J2), and drag-across-columns reschedule —
/// threats T41–T43.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late ClientsService clients;
  late JournalService journal;
  late ProAppointmentService proService;
  late AppointmentLifecycleService lifecycle;
  late String accountId; // manages provider1
  late String otherAccountId; // manages provider2
  late InMemoryMembershipRepository memberships;
  late MembershipService members;

  // A Monday (open 09:00–18:00 in the seeded schedule), fixed + future-proof.
  final monday = DateTime.utc(2026, 7, 13);
  // A Sunday — weekday '6' has no schedule → closed.
  final sunday = DateTime.utc(2026, 7, 12);

  Future<void> seed({
    required String id,
    String status = 'confirmed',
    DateTime? when,
    String? userId,
    String? clientPhone,
    String providerId = 'provider1',
    String? artistId,
  }) => appts.create({
    'id': id,
    'userId': userId ?? 'manual',
    'providerId': providerId,
    'serviceIds': ['service1'],
    'artistId': artistId,
    'appointmentDate': (when ?? monday.add(const Duration(hours: 10)))
        .toIso8601String(),
    'durationMinutes': 60,
    'status': status,
    'totalPrice': 15000,
    'depositAmount': 0,
    'balanceDue': 15000,
    'cancellationWindowHours': 24,
    'clientName': 'Koffi',
    'clientPhone': clientPhone,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.utc(2026).toIso8601String(),
  });

  setUp(() async {
    // Deep-copy the seed: the blocked-date test mutates provider records, and
    // the default constructor shares the GLOBAL seedProviders list.
    providers = InMemoryProvidersRepository(
      (jsonDecode(jsonEncode(seedProviders)) as List)
          .cast<Map<String, dynamic>>(),
    );
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    memberships = InMemoryMembershipRepository();
    members = MembershipService(memberships, providerAuth);
    clients = ClientsService(
      providerAuth,
      members,
      InMemoryAuthRepository(tokens: tokens, isProd: false),
      InMemoryClientsRepository(),
      appts,
      InMemoryProviderAuditLogRepository(),
    );
    journal = JournalService(members, providers, appts, clients);
    proService = ProAppointmentService(members, appts, clients: clients);
    lifecycle = AppointmentLifecycleService(
      appts,
      SlotService(providers, appts),
      providers: providers,
    );

    final reg1 = await providerAuth.register(
      email: 'journal1@test.pro',
      authProvider: 'google',
      googleSub: 'sub-journal-1',
      phoneNumber: '+2250500000060',
      businessName: 'Salon Un',
      businessType: 'salon',
      providerId: 'provider1',
    );
    accountId = reg1.provider!.id;
    final reg2 = await providerAuth.register(
      email: 'journal2@test.pro',
      authProvider: 'google',
      googleSub: 'sub-journal-2',
      phoneNumber: '+2250500000061',
      businessName: 'Salon Deux',
      businessType: 'salon',
      providerId: 'provider2',
    );
    otherAccountId = reg2.provider!.id;
  });

  group('JournalService.dayFor', () {
    test(
      'one payload: hours, artists, sorted enriched day (all statuses)',
      () async {
        await providers.addArtist('provider1', {
          'id': 'artist1',
          'name': 'Awa',
          'imageUrl': null,
        });
        // The guest has ONE prior no-show → the badge data on today's block.
        await seed(
          id: 'past-noshow',
          status: 'noShow',
          when: DateTime.utc(2026, 7, 6, 10),
          clientPhone: '+2250700000001',
        );
        await clients.recordBooking({
          'providerId': 'provider1',
          'userId': 'manual',
          'clientName': 'Koffi',
          'clientPhone': '+2250700000001',
        });
        await seed(
          id: 'late',
          when: monday.add(const Duration(hours: 14)),
          clientPhone: '+2250700000001',
        );
        await seed(
          id: 'early',
          when: monday.add(const Duration(hours: 9)),
          clientPhone: '+2250700000001',
        );
        await seed(
          id: 'ghost',
          status: 'cancelled',
          when: monday.add(const Duration(hours: 11)),
        );

        final r = await journal.dayFor(accountId, 'provider1', monday);
        expect(r.ok, isTrue);
        final data = r.data!;
        expect(data['date'], '2026-07-13');
        expect((data['hours'] as Map)['open'], '09:00');
        expect((data['hours'] as Map)['close'], '18:00');
        expect(((data['artists'] as List).single as Map)['name'], 'Awa');

        final day = (data['appointments'] as List).cast<Map<String, dynamic>>();
        // Only the day's bookings, ascending, cancelled included (ghost toggle
        // is client-side).
        expect(day.map((a) => a['id']), ['early', 'ghost', 'late']);
        final early = day.first;
        expect(early['clientNoShowCount'], 1); // the guest's history
        expect(early['salonClientId'], isNotNull);
      },
    );

    test('closed day (Sunday) and blocked dates → hours null', () async {
      await seed(id: 'sun', when: sunday.add(const Duration(hours: 10)));
      final r = await journal.dayFor(accountId, 'provider1', sunday);
      expect(r.data!['hours'], isNull);
      expect((r.data!['appointments'] as List), hasLength(1));

      // Blocked Monday behaves the same.
      final record = await providers.byId('provider1');
      ((record!['availability'] as Map)['blockedDates'] as List).add(
        monday.toIso8601String(),
      );
      final blocked = await journal.dayFor(accountId, 'provider1', monday);
      expect(blocked.data!['hours'], isNull);
    });

    test('T41: cross-salon → forbidden; unknown salon → not_found', () async {
      expect(
        (await journal.dayFor(otherAccountId, 'provider1', monday)).error,
        'forbidden',
      );
      expect((await journal.dayFor(accountId, 'provider1', monday)).ok, isTrue);
      final regGhost = await providerAuth.register(
        email: 'journal3@test.pro',
        authProvider: 'google',
        googleSub: 'sub-journal-3',
        phoneNumber: '+2250500000062',
        businessName: 'Ghost',
        businessType: 'salon',
        providerId: 'providerGhost',
      );
      expect(
        (await journal.dayFor(
          regGhost.provider!.id,
          'providerGhost',
          monday,
        )).error,
        'not_found',
      );
    });
  });

  group('own scope (T40 — access R4a)', () {
    /// A bare STAFF account, active member of provider1 linked to [artistId].
    Future<String> staffAccount({String? artistId = 'artist1'}) async {
      final sent = await providerAuth.requestEmailOtp('staff@test.pro');
      final created = await providerAuth.createMemberAccount(
        email: 'staff@test.pro',
        authProvider: 'email',
        emailCode: sent.devCode,
      );
      final row = await memberships.invite(
        providerId: 'provider1',
        email: 'staff@test.pro',
        role: 'staff',
        artistId: artistId,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(row.id, created.provider!.id);
      return created.provider!.id;
    }

    Future<void> seedTwoColumns() async {
      await providers.addArtist('provider1', {
        'id': 'artist1',
        'name': 'Awa',
        'imageUrl': null,
      });
      await providers.addArtist('provider1', {
        'id': 'artist2',
        'name': 'Fatou',
        'imageUrl': null,
      });
      await seed(id: 'own', artistId: 'artist1', clientPhone: '+2250700000001');
      await seed(
        id: 'foreign',
        artistId: 'artist2',
        when: monday.add(const Duration(hours: 11)),
        clientPhone: '+2250700000002',
      );
      await seed(id: 'unassigned', when: monday.add(const Duration(hours: 12)));
    }

    test('the staff day view: own bookings only, own column only, phone '
        'PRESENT on the requested day when it is today', () async {
      await seedTwoColumns();
      final staffId = await staffAccount();
      final ownJournal = JournalService(
        members,
        providers,
        appts,
        clients,
        clock: () => monday.add(const Duration(hours: 8)), // "today" = monday
      );

      final res = await ownJournal.dayFor(staffId, 'provider1', monday);
      expect(res.ok, isTrue);
      final data = res.data!;
      final ids = [
        for (final a in data['appointments'] as List) (a as Map)['id'],
      ];
      expect(ids, ['own']);
      expect(
        (data['appointments'] as List)
            .cast<Map<String, dynamic>>()
            .single['clientPhone'],
        '+2250700000001',
      );
      final artists = (data['artists'] as List).cast<Map<String, dynamic>>();
      expect(artists.single['id'], 'artist1');
    });

    test('off-day own view: clientPhone is MASKED (same-day contact rule, '
        '§11.2/T39)', () async {
      await seedTwoColumns();
      final staffId = await staffAccount();
      final ownJournal = JournalService(
        members,
        providers,
        appts,
        clients,
        // "today" is the day AFTER the requested monday.
        clock: () => monday.add(const Duration(days: 1, hours: 8)),
      );

      final res = await ownJournal.dayFor(staffId, 'provider1', monday);
      expect(res.ok, isTrue);
      final row = (res.data!['appointments'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(row['id'], 'own');
      expect(row.containsKey('clientPhone'), isFalse);
      // Non-contact enrichment survives the masking.
      expect(row['clientNoShowCount'], isNotNull);
    });

    test(
      'a staff row with a NULL artistId gets NOTHING (deny by default)',
      () async {
        await seedTwoColumns();
        final staffId = await staffAccount(artistId: null);
        final res = await journal.dayFor(staffId, 'provider1', monday);
        expect(res.ok, isFalse);
        expect(res.error, 'forbidden');
      },
    );

    test('RÉCEPTION keeps the whole journal (view.all)', () async {
      await seedTwoColumns();
      final sent = await providerAuth.requestEmailOtp('front@test.pro');
      final created = await providerAuth.createMemberAccount(
        email: 'front@test.pro',
        authProvider: 'email',
        emailCode: sent.devCode,
      );
      final row = await memberships.invite(
        providerId: 'provider1',
        email: 'front@test.pro',
        role: 'reception',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(row.id, created.provider!.id);

      final res = await journal.dayFor(
        created.provider!.id,
        'provider1',
        monday,
      );
      expect(res.ok, isTrue);
      expect((res.data!['appointments'] as List).length, 3);
      expect((res.data!['artists'] as List).length, 2);
    });

    test('transitions: staff completes/no-shows OWN bookings; everything '
        'else is 403 (cross-artist, accept, arrive — T40 negatives)', () async {
      await seedTwoColumns();
      await seed(
        id: 'own-pending',
        status: 'pending',
        artistId: 'artist1',
        when: monday.add(const Duration(hours: 14)),
      );
      final staffId = await staffAccount();

      // « Terminé » on the OWN confirmed booking.
      final done = await proService.complete('own', staffId);
      expect(done.ok, isTrue);
      expect(done.appointment!['status'], 'completed');

      // « Non présenté » on own.
      final ns = await proService.noShow('own-pending', staffId);
      expect(ns.ok, isTrue);

      // Cross-artist → 403 (the T40 REQUIRED negative).
      expect(
        (await proService.complete('foreign', staffId)).error,
        'forbidden',
      );
      expect((await proService.noShow('foreign', staffId)).error, 'forbidden');
      // Unassigned bookings are nobody's "own".
      expect(
        (await proService.complete('unassigned', staffId)).error,
        'forbidden',
      );
      // Whole-journal actions stay closed, even on OWN bookings.
      expect(
        (await proService.accept('own-pending', staffId)).error,
        'forbidden',
      );
      expect(
        (await proService.arrive(
          'own',
          staffId,
          now: monday.add(const Duration(hours: 9)),
        )).error,
        'forbidden',
      );
    });
  });

  group('arrive (J2 — threat T43)', () {
    test('confirmed today → arrivedAt stamped; idempotent', () async {
      final today = DateTime.now().toUtc();
      await seed(
        id: 'today1',
        when: DateTime.utc(today.year, today.month, today.day, 23),
      );
      final r = await proService.arrive('today1', accountId);
      expect(r.ok, isTrue);
      expect(r.appointment!['arrivedAt'], isNotNull);

      final again = await proService.arrive('today1', accountId);
      expect(again.ok, isTrue);
      expect(again.appointment!['arrivedAt'], r.appointment!['arrivedAt']);
    });

    test('guards: wrong state · wrong day · cross-salon · unknown', () async {
      final today = DateTime.now().toUtc();
      await seed(
        id: 'pending1',
        status: 'pending',
        when: DateTime.utc(today.year, today.month, today.day, 22),
      );
      expect(
        (await proService.arrive('pending1', accountId)).error,
        'invalid_state',
      );

      await seed(id: 'nextweek'); // fixed future Monday — not today
      expect(
        (await proService.arrive('nextweek', accountId)).error,
        'not_today',
      );

      await seed(
        id: 'foreign',
        providerId: 'provider2',
        when: DateTime.utc(today.year, today.month, today.day, 21),
      );
      expect(
        (await proService.arrive('foreign', accountId)).error,
        'forbidden',
      );
      expect((await proService.arrive('ghost', accountId)).error, 'not_found');
    });
  });

  group('reschedule with artistId (J1 drag — threat T42)', () {
    test(
      'valid artist → moved + assigned; foreign artist → invalid_artist',
      () async {
        await providers.addArtist('provider1', {
          'id': 'artist1',
          'name': 'Awa',
          'imageUrl': null,
        });
        await seed(id: 'drag1');

        // service1 runs 180 min + 10 min buffer — 14:00 is a fitting start
        // in the 09:00–18:00 day.
        final moved = await lifecycle.rescheduleByProvider(
          'drag1',
          'provider1',
          monday.add(const Duration(hours: 14)),
          artistId: 'artist1',
        );
        expect(moved.ok, isTrue);
        expect(moved.appointment!['artistId'], 'artist1');
        expect(
          moved.appointment!['appointmentDate'],
          monday.add(const Duration(hours: 14)).toIso8601String(),
        );

        final bad = await lifecycle.rescheduleByProvider(
          'drag1',
          'provider1',
          monday.add(const Duration(hours: 16)),
          artistId: 'not-my-artist',
        );
        expect(bad.error, 'invalid_artist');
      },
    );

    test(
      'a taken target slot still 409s (the grid is never trusted)',
      () async {
        await seed(id: 'a1', when: monday.add(const Duration(hours: 10)));
        await seed(id: 'a2', when: monday.add(const Duration(hours: 14)));
        final clash = await lifecycle.rescheduleByProvider(
          'a2',
          'provider1',
          monday.add(const Duration(hours: 10)),
        );
        expect(clash.error, 'slot_unavailable');
      },
    );
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<JournalService>()).thenReturn(journal);
      when(() => context.read<ProAppointmentService>()).thenReturn(proService);
      return context;
    }

    String proTok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'provider').token;
    String userTok() =>
        tokens.issueAccessToken(subject: 'u1', role: 'user').token;

    Request req(String method, String path, {String? token}) => Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    test('journal: 200 · 400 bad date · 401 · 403 consumer · 405', () async {
      expect(
        (await journal_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/journal?date=2026-07-13',
              token: proTok(accountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await journal_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/journal?date=quoi',
              token: proTok(accountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.badRequest,
      );
      expect(
        (await journal_route.onRequest(
          ctx(req('GET', '/providers/provider1/journal?date=2026-07-13')),
          'provider1',
        )).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await journal_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/journal?date=2026-07-13',
              token: userTok(),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await journal_route.onRequest(
          ctx(
            req(
              'POST',
              '/providers/provider1/journal?date=2026-07-13',
              token: proTok(accountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });

    test('journal: cross-salon token → 403 (T41)', () async {
      expect(
        (await journal_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/journal?date=2026-07-13',
              token: proTok(otherAccountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.forbidden,
      );
    });

    test('arrive: 200 · 409 wrong state · 404 · 403 consumer · 405', () async {
      final today = DateTime.now().toUtc();
      await seed(
        id: 'r-today',
        when: DateTime.utc(today.year, today.month, today.day, 23, 30),
      );
      await seed(
        id: 'r-pending',
        status: 'pending',
        when: DateTime.utc(today.year, today.month, today.day, 22, 30),
      );
      expect(
        (await arrive_route.onRequest(
          ctx(
            req(
              'POST',
              '/appointments/r-today/arrive',
              token: proTok(accountId),
            ),
          ),
          'r-today',
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await arrive_route.onRequest(
          ctx(
            req(
              'POST',
              '/appointments/r-pending/arrive',
              token: proTok(accountId),
            ),
          ),
          'r-pending',
        )).statusCode,
        HttpStatus.conflict,
      );
      expect(
        (await arrive_route.onRequest(
          ctx(
            req('POST', '/appointments/ghost/arrive', token: proTok(accountId)),
          ),
          'ghost',
        )).statusCode,
        HttpStatus.notFound,
      );
      expect(
        (await arrive_route.onRequest(
          ctx(req('POST', '/appointments/r-today/arrive', token: userTok())),
          'r-today',
        )).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await arrive_route.onRequest(
          ctx(
            req(
              'GET',
              '/appointments/r-today/arrive',
              token: proTok(accountId),
            ),
          ),
          'r-today',
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });
  });
}
