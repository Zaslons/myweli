import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
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
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/localities/localities_repository.dart';
import 'package:myweli_backend/src/localities/localities_service.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:myweli_backend/src/provider_earnings_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/slug.dart';
import 'package:test/test.dart';

import '../routes/localities/index.dart' as localities_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// Multi-pays MP1 (docs/design/multi-pays-end-version.md): the locality
/// tree, the derived salon market facts (T57), the reserved-slug guard, the
/// catalog-driven deposit operators — and the LIBREVILLE ARC proving the
/// per-salon timezone end-to-end (slots · arrive · journal · dashboard),
/// with Abidjan (≡ UTC) as the bit-identical control.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  final localities = LocalitiesService(InMemoryLocalitiesRepository());

  /// The seed providers with provider1 moved to Libreville (UTC+1).
  List<Map<String, dynamic>> librevilleSeed() =>
      (jsonDecode(jsonEncode(seedProviders)) as List)
          .cast<Map<String, dynamic>>()
          .map((p) => p..['timezone'] = 'Africa/Libreville')
          .toList();

  group('localities service + route (T56)', () {
    test('the tree: CI → 4 operators → abidjan → 11 communes', () async {
      final tree = await localities.tree();
      final countries = tree['countries'] as List;
      final ci = countries.single as Map<String, dynamic>;
      expect(ci['code'], 'CI');
      expect(ci['currency'], 'XOF');
      expect(ci['phonePrefix'], '+225');
      final ops = (ci['operators'] as List).cast<Map<String, dynamic>>();
      expect(ops.map((o) => o['id']), [
        'wave',
        'orangeMoney',
        'mtnMoMo',
        'moov',
      ]);
      expect(ops.singleWhere((o) => o['id'] == 'wave')['deepLinkKind'], 'wave');
      expect(
        ops.singleWhere((o) => o['id'] == 'orangeMoney')['deepLinkKind'],
        isNull,
      );
      final city = (ci['cities'] as List).single as Map<String, dynamic>;
      expect(city['slug'], 'abidjan');
      expect(city['timezone'], 'Africa/Abidjan');
      expect((city['areas'] as List), hasLength(11));
    });

    test('resolveArea derives the full market; unknown → null', () async {
      final m = await localities.resolveArea('cocody');
      expect(m!.areaName, 'Cocody');
      expect(m.citySlug, 'abidjan');
      expect(m.timezone, 'Africa/Abidjan');
      expect(m.countryCode, 'CI');
      expect(m.currency, 'XOF');
      expect(await localities.resolveArea('nowhere'), isNull);
    });

    test('resolveCommuneName is accent/case/whitespace-insensitive', () async {
      expect((await localities.resolveCommuneName('Adjame'))!.areaId, 'adjame');
      expect((await localities.resolveCommuneName('ADJAMÉ'))!.areaId, 'adjame');
      expect(
        (await localities.resolveCommuneName(' cocody '))!.areaId,
        'cocody',
      );
      expect(await localities.resolveCommuneName('Garbage'), isNull);
      expect(await localities.resolveCommuneName('  '), isNull);
    });

    test('operatorIdsForCountry: the catalog per country', () async {
      expect(await localities.operatorIdsForCountry('CI'), {
        'wave',
        'orangeMoney',
        'mtnMoMo',
        'moov',
      });
      expect(await localities.operatorIdsForCountry('XX'), isEmpty);
    });

    test('GET /localities → 200 + cache header; POST → 405', () async {
      RequestContext ctx(String method) {
        final context = _MockRequestContext();
        when(
          () => context.request,
        ).thenReturn(Request(method, Uri.parse('http://x/localities')));
        when(() => context.read<LocalitiesService>()).thenReturn(localities);
        return context;
      }

      final ok = await localities_route.onRequest(ctx('GET'));
      expect(ok.statusCode, HttpStatus.ok);
      expect(ok.headers['Cache-Control'], 'public, max-age=3600');
      expect(await ok.body(), contains('"code":"CI"'));

      final nope = await localities_route.onRequest(ctx('POST'));
      expect(nope.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('reserved slugs', () {
    test('every seeded city slug is reserved (the sync pin)', () {
      for (final c in seedCities) {
        expect(
          reservedPublicSlugs,
          contains(c.slug),
          reason: 'add ${c.slug} to reservedPublicSlugs (slug.dart)',
        );
      }
    });

    test('a salon named after a taxonomy root gets uniquified', () async {
      final repo = InMemoryProvidersRepository([]);
      final s1 = await repo.createSalon(
        name: 'Coiffure',
        category: 'salon',
        phoneNumber: '+2250700000001',
      );
      expect(s1['slug'], 'coiffure-2'); // never /coiffure
      final s2 = await repo.createSalon(
        name: 'Tresses',
        category: 'salon',
        phoneNumber: '+2250700000002',
      );
      expect(s2['slug'], 'tresses-2');
      final s3 = await repo.createSalon(
        name: 'Abidjan Beauté',
        category: 'salon',
        phoneNumber: '+2250700000003',
      );
      expect(s3['slug'], 'abidjan-beaute'); // compound names stay untouched
    });
  });

  group('applySalonMarketDefaults (the backfill matrix)', () {
    test('matched communes stamp the derived market + canonical names', () {
      final doc = applySalonMarketDefaults({'commune': 'Adjame'});
      expect(doc['areaId'], 'adjame');
      expect(doc['commune'], 'Adjamé'); // canonical display name
      expect(doc['city'], 'Abidjan');
      expect(doc['citySlug'], 'abidjan');
      expect(doc['countryCode'], 'CI');
      expect(doc['timezone'], 'Africa/Abidjan');
      expect(doc['currency'], 'XOF');
    });

    test('a miss keeps Wave-0 defaults with a null areaId', () {
      final doc = applySalonMarketDefaults({'commune': 'Nulle Part'});
      expect(doc['areaId'], isNull);
      expect(doc['citySlug'], isNull);
      expect(doc['commune'], 'Nulle Part'); // untouched free text
      expect(doc['timezone'], 'Africa/Abidjan');
      expect(doc['currency'], 'XOF');
    });
  });

  group('the areaId write path (T57)', () {
    late InMemoryProvidersRepository providers;
    late InMemoryProviderAuthRepository providerAuth;
    late MembershipService members;
    late ProviderCatalogService catalog;
    late String accountId;

    setUp(() async {
      providers = InMemoryProvidersRepository(
        (jsonDecode(jsonEncode(seedProviders)) as List)
            .cast<Map<String, dynamic>>(),
      );
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      members = MembershipService(InMemoryMembershipRepository(), providerAuth);
      catalog = ProviderCatalogService(
        providers,
        providerAuth,
        members,
        localities: localities,
      );
      final reg = await providerAuth.register(
        email: 'mp@test.pro',
        authProvider: 'google',
        googleSub: 'sub-mp-1',
        phoneNumber: '+2250500000070',
        businessName: 'Salon MP',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    test('PATCH areaId derives every market fact server-side', () async {
      final r = await catalog.updateProfile(accountId, 'provider1', {
        'areaId': 'marcory',
      });
      expect(r.ok, isTrue);
      final doc = r.data! as Map<String, dynamic>;
      expect(doc['areaId'], 'marcory');
      expect(doc['commune'], 'Marcory');
      expect(doc['city'], 'Abidjan');
      expect(doc['timezone'], 'Africa/Abidjan');
      expect(doc['currency'], 'XOF');
    });

    test('a forged areaId → invalid_area; nothing written', () async {
      final r = await catalog.updateProfile(accountId, 'provider1', {
        'areaId': 'forged-area',
      });
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_area');
      final doc = await providers.byId('provider1');
      expect(doc!['areaId'], 'cocody'); // the seeded value survived
    });

    test(
      'client-sent timezone/currency are IGNORED (never editable)',
      () async {
        final r = await catalog.updateProfile(accountId, 'provider1', {
          'description': 'Nouveau texte',
          'timezone': 'Europe/Paris',
          'currency': 'EUR',
          'countryCode': 'FR',
        });
        expect(r.ok, isTrue);
        final doc = r.data! as Map<String, dynamic>;
        expect(doc['timezone'], 'Africa/Abidjan');
        expect(doc['currency'], 'XOF');
        expect(doc['countryCode'], 'CI');
      },
    );

    test('a legacy commune display name self-heals to its area', () async {
      final r = await catalog.updateProfile(accountId, 'provider1', {
        'commune': 'yopougon',
      });
      expect(r.ok, isTrue);
      final doc = r.data! as Map<String, dynamic>;
      expect(doc['areaId'], 'yopougon');
      expect(doc['commune'], 'Yopougon'); // canonicalized
      expect(doc['timezone'], 'Africa/Abidjan');
    });

    test('ensureSalon stamps a route-resolved market at creation', () async {
      final reg = await providerAuth.register(
        email: 'fresh@test.pro',
        authProvider: 'google',
        googleSub: 'sub-mp-2',
        phoneNumber: '+2250500000071',
        businessName: 'Institut Frais',
        businessType: 'spa',
      );
      final provisioning = SalonProvisioningService(
        providers,
        providerAuth,
        InMemoryMembershipRepository(),
      );
      final market = await localities.resolveArea('plateau');
      final account = await provisioning.ensureSalon(
        reg.provider!,
        market: market,
      );
      final doc = await providers.byId(account.providerId!);
      expect(doc!['areaId'], 'plateau');
      expect(doc['commune'], 'Plateau');
      expect(doc['timezone'], 'Africa/Abidjan');
      expect(doc['currency'], 'XOF');
    });

    test('deposit operators come from the country catalog', () async {
      Future<String?> save(String op) async {
        final r = await catalog.updateDepositPolicy(accountId, 'provider1', {
          'depositRequired': false,
          'depositPercentage': 0.2,
          'cancellationWindowHours': 24,
          'mobileMoneyOperator': op,
        });
        return r.ok ? null : r.error;
      }

      expect(await save('wave'), isNull);
      expect(await save('mpesa'), 'invalid_input'); // not in CI's catalog
    });
  });

  group('publish gate + self-heal', () {
    late InMemoryProvidersRepository providers;
    late SalonProvisioningService provisioning;

    Map<String, dynamic> completeDoc(Map<String, dynamic> over) => {
      'id': 'pX',
      'slug': 'p-x',
      'name': 'Salon X',
      'description': 'Un salon complet.',
      'address': 'Rue 1',
      'city': 'Abidjan',
      'commune': 'Cocody',
      'areaId': null,
      'citySlug': null,
      'countryCode': 'CI',
      'timezone': 'Africa/Abidjan',
      'currency': 'XOF',
      'latitude': 5.3,
      'longitude': -4.0,
      'imageUrls': ['a', 'b', 'c'],
      'services': [
        {'id': 's1', 'active': true},
        {'id': 's2', 'active': true},
        {'id': 's3', 'active': true},
      ],
      'availability': {
        'weeklySchedule': {
          '0': [
            {'startTime': '2024-01-01T09:00:00.000Z'},
          ],
        },
      },
      'status': 'draft',
      ...over,
    };

    setUp(() {
      providers = InMemoryProvidersRepository([]);
      provisioning = SalonProvisioningService(
        providers,
        InMemoryProviderAuthRepository(tokens: tokens, isProd: false),
        InMemoryMembershipRepository(),
      );
    });

    test('an unmatched free-text commune blocks under `profile`', () {
      final missing = SalonProvisioningService.publishGate(
        completeDoc({'commune': 'Nulle Part'}),
      );
      expect(missing, contains('profile'));
    });

    test(
      'a matching commune passes and publish() self-heals the areaId',
      () async {
        expect(SalonProvisioningService.publishGate(completeDoc({})), isEmpty);
        final created = await providers.createSalon(
          name: 'Salon X',
          category: 'salon',
          phoneNumber: '+2250700000009',
        );
        final id = created['id'] as String;
        await providers.updateProfile(
          id,
          completeDoc({})
            ..remove('id')
            ..remove('slug'),
        );
        final r = await provisioning.publish(id);
        expect(r.ok, isTrue);
        final after = await providers.byId(id);
        expect(after!['areaId'], 'cocody'); // self-healed before gating
        expect(after['status'], 'active');
      },
    );
  });

  group('THE LIBREVILLE ARC (per-salon timezone, end to end)', () {
    late InMemoryProvidersRepository abidjanRepo;
    late InMemoryProvidersRepository librevilleRepo;
    late InMemoryAppointmentRepository appts;
    late InMemoryProviderAuthRepository providerAuth;
    late MembershipService members;
    late String accountId;

    setUp(() async {
      abidjanRepo = InMemoryProvidersRepository(
        (jsonDecode(jsonEncode(seedProviders)) as List)
            .cast<Map<String, dynamic>>(),
      );
      librevilleRepo = InMemoryProvidersRepository(librevilleSeed());
      appts = InMemoryAppointmentRepository();
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      members = MembershipService(InMemoryMembershipRepository(), providerAuth);
      final reg = await providerAuth.register(
        email: 'arc@test.pro',
        authProvider: 'google',
        googleSub: 'sub-arc-1',
        phoneNumber: '+2250500000080',
        businessName: 'Salon Arc',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    Future<void> seedBooking(
      String id,
      DateTime whenUtc, {
      String status = 'confirmed',
    }) => appts.create({
      'id': id,
      'userId': 'manual',
      'providerId': 'provider1',
      'serviceIds': ['service1'],
      'artistId': null,
      'appointmentDate': whenUtc.toIso8601String(),
      'durationMinutes': 60,
      'status': status,
      'totalPrice': 10000,
      'depositAmount': 0,
      'balanceDue': 10000,
      'cancellationWindowHours': 24,
      'clientName': 'Koffi',
      'clientPhone': null,
      'notes': null,
      'depositScreenshotUrl': null,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    });

    test('slots: the 09:00 wall-clock is 08:00Z in Libreville, 09:00Z in '
        'Abidjan', () async {
      // A future open weekday (never today — the ≥1h gate reads the clock).
      var day = DateTime.now().toUtc().add(const Duration(days: 7));
      while (day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      final ab = await SlotService(
        abidjanRepo,
        appts,
      ).availableSlots(providerId: 'provider1', date: day, durationMinutes: 30);
      expect(ab.slots!.first, DateTime.utc(day.year, day.month, day.day, 9));
      final lb = await SlotService(
        librevilleRepo,
        appts,
      ).availableSlots(providerId: 'provider1', date: day, durationMinutes: 30);
      expect(lb.slots!.first, DateTime.utc(day.year, day.month, day.day, 8));
    });

    test('arrive: 23:30Z is TOMORROW in Libreville → not_today; today in '
        'Abidjan → stamped', () async {
      await seedBooking('b2330', DateTime.utc(2026, 8, 12, 23, 30));
      final now = DateTime.utc(2026, 8, 12, 22); // 23:00 Libreville, same day
      final libreville = ProAppointmentService(
        members,
        appts,
        providers: librevilleRepo,
      );
      final denied = await libreville.arrive('b2330', accountId, now: now);
      expect(denied.error, 'not_today'); // 23:30Z = 00:30 Libreville, Aug 13
      final abidjan = ProAppointmentService(
        members,
        appts,
        providers: abidjanRepo,
      );
      final stamped = await abidjan.arrive('b2330', accountId, now: now);
      expect(stamped.ok, isTrue);
    });

    test(
      'journal: a 23:30Z booking belongs to the NEXT Libreville day',
      () async {
        await seedBooking('bday', DateTime.utc(2026, 8, 12, 23, 30));
        ClientsService clientsFor(InMemoryProvidersRepository repo) =>
            ClientsService(
              providerAuth,
              members,
              InMemoryAuthRepository(tokens: tokens, isProd: false),
              InMemoryClientsRepository(),
              appts,
              InMemoryProviderAuditLogRepository(),
            );
        final journal = JournalService(
          members,
          librevilleRepo,
          appts,
          clientsFor(librevilleRepo),
        );
        final on12 = await journal.dayFor(
          accountId,
          'provider1',
          DateTime.utc(2026, 8, 12),
        );
        expect((on12.data!['appointments'] as List), isEmpty);
        final on13 = await journal.dayFor(
          accountId,
          'provider1',
          DateTime.utc(2026, 8, 13),
        );
        expect(
          ((on13.data!['appointments'] as List).single as Map)['id'],
          'bday',
        );
      },
    );

    test('dashboard: today buckets follow the salon midnight', () async {
      await seedBooking('in-day', DateTime.utc(2026, 8, 12, 10));
      await seedBooking('past-midnight', DateTime.utc(2026, 8, 12, 23, 30));
      DateTime clock() => DateTime.utc(2026, 8, 12, 12);
      final lb = await ProviderDashboardService(
        members,
        appts,
        providers: librevilleRepo,
        clock: clock,
      ).statsFor(accountId, 'provider1');
      // 23:30Z is already Aug 13 in Libreville — outside today.
      expect(lb.data!['todayAppointments'], 1);
      final ab = await ProviderDashboardService(
        members,
        appts,
        providers: abidjanRepo,
        clock: clock,
      ).statsFor(accountId, 'provider1');
      expect(ab.data!['todayAppointments'], 2);
    });

    test(
      'earnings: the response carries the salon currency + stamped rows',
      () async {
        await seedBooking(
          'done1',
          DateTime.utc(2026, 8, 10, 10),
          status: 'completed',
        );
        final r = await ProviderEarningsService(
          members,
          appts,
          providers: abidjanRepo,
        ).earningsFor(accountId, 'provider1');
        expect(r.data!['currency'], 'XOF');
        final tx = (r.data!['transactions'] as List).single as Map;
        expect(tx['currency'], 'XOF'); // pre-MP1 row inherits the salon's
      },
    );
  });
}
