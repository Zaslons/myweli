@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/db/postgres_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_clients_repository.dart';
import 'package:myweli_backend/src/db/postgres_favorites_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_audit_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_providers_repository.dart';
import 'package:myweli_backend/src/db/postgres_reviews_repository.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres repositories (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  final tokens = TokenService(secret: 'test-secret');
  const phone = '+2250707010101';

  setUpAll(() async {
    pool = createPool(url);
    await runMigrations(pool);
    await seedProvidersIfEmpty(pool);
    await backfillCatalogueIfNeeded(
      pool,
    ); // match production: catalogue → tables
  });

  tearDownAll(() async => pool.close());

  setUp(() async {
    // Isolate state between tests; the seeded providers stay.
    await pool.execute(
      'TRUNCATE appointments, refresh_tokens, otp_codes, users, '
      'provider_users, provider_otp_codes, provider_refresh_tokens, '
      'favorites, reviews, salon_clients, salon_client_notes, '
      'provider_audit_log CASCADE',
    );
  });

  Map<String, dynamic> apptMap({
    required String id,
    String userId = 'u1',
    String providerId = 'provider1',
    String status = 'pending',
    int durationMinutes = 30,
    required DateTime when,
  }) => {
    'id': id,
    'userId': userId,
    'providerId': providerId,
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': when.toUtc().toIso8601String(),
    'durationMinutes': durationMinutes,
    'status': status,
    'totalPrice': 15000,
    'depositAmount': 0,
    'balanceDue': 15000,
    'cancellationWindowHours': 24,
    'clientName': null,
    'clientPhone': null,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };

  group('PostgresAppointmentRepository', () {
    final when = DateTime.utc(2030, 6, 25, 9);

    test('create + byId + listForUser/Provider + update', () async {
      final repo = PostgresAppointmentRepository(pool);
      final created = await repo.create(apptMap(id: 'a1', when: when));
      expect(created, isNotNull);
      expect(created!['totalPrice'], 15000);
      expect(created['appointmentDate'], when.toIso8601String());

      expect((await repo.byId('a1'))?['id'], 'a1');
      expect((await repo.listForUser('u1')).single['id'], 'a1');
      expect((await repo.listForProvider('provider1')).single['id'], 'a1');
      expect((await repo.listForUser('u1', status: 'confirmed')), isEmpty);

      final updated = await repo.update('a1', {'status': 'confirmed'});
      expect(updated!['status'], 'confirmed');

      // Provider list honours the status filter.
      expect(
        (await repo.listForProvider(
          'provider1',
          status: 'confirmed',
        )).single['id'],
        'a1',
      );
      expect(
        await repo.listForProvider('provider1', status: 'pending'),
        isEmpty,
      );
    });

    test(
      'the partial unique index blocks a second booking on the same slot',
      () async {
        final repo = PostgresAppointmentRepository(pool);
        expect(await repo.create(apptMap(id: 'a1', when: when)), isNotNull);
        // Same provider + exact start, still pending → conflict → null.
        expect(
          await repo.create(apptMap(id: 'a2', userId: 'u2', when: when)),
          isNull,
        );
        // After the first is cancelled, the slot frees up.
        await repo.update('a1', {'status': 'cancelled'});
        expect(
          await repo.create(apptMap(id: 'a3', userId: 'u2', when: when)),
          isNotNull,
        );
      },
    );

    test(
      'btree_gist exclusion blocks duration overlaps (not just exact start)',
      () async {
        final repo = PostgresAppointmentRepository(pool);
        final at9 = DateTime.utc(2030, 6, 25, 9);
        // 09:00 for 120 min → occupies [09:00, 11:00).
        expect(
          await repo.create(apptMap(id: 'o1', when: at9, durationMinutes: 120)),
          isNotNull,
        );
        // 10:00 (different start) overlaps the 09:00–11:00 booking → rejected.
        expect(
          await repo.create(
            apptMap(
              id: 'o2',
              userId: 'u2',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
            ),
          ),
          isNull,
        );
        // 11:00 is back-to-back (half-open range) → allowed.
        expect(
          await repo.create(
            apptMap(
              id: 'o3',
              userId: 'u3',
              when: DateTime.utc(2030, 6, 25, 11),
              durationMinutes: 60,
            ),
          ),
          isNotNull,
        );
        // Same overlapping time at a DIFFERENT provider → allowed (per-provider).
        expect(
          await repo.create(
            apptMap(
              id: 'o4',
              userId: 'u4',
              providerId: 'provider2',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
            ),
          ),
          isNotNull,
        );
        // Cancelling o1 frees [09:00, 11:00) → a 10:00 booking now fits.
        await repo.update('o1', {'status': 'cancelled'});
        expect(
          await repo.create(
            apptMap(
              id: 'o5',
              userId: 'u5',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
            ),
          ),
          isNotNull,
        );
      },
    );

    test(
      'reschedule update onto an overlapping slot is rejected (null)',
      () async {
        final repo = PostgresAppointmentRepository(pool);
        await repo.create(
          apptMap(
            id: 'r1',
            when: DateTime.utc(2030, 6, 25, 9),
            durationMinutes: 120,
          ),
        );
        await repo.create(
          apptMap(
            id: 'r2',
            userId: 'u2',
            when: DateTime.utc(2030, 6, 25, 14),
            durationMinutes: 60,
          ),
        );
        // Move r2 to 10:00–11:00 → overlaps r1's [09:00, 11:00) → null.
        expect(
          await repo.update('r2', {
            'appointmentDate': DateTime.utc(2030, 6, 25, 10).toIso8601String(),
            'endsAt': DateTime.utc(2030, 6, 25, 11).toIso8601String(),
          }),
          isNull,
        );
        // A non-overlapping move (12:00–13:00) succeeds.
        expect(
          await repo.update('r2', {
            'appointmentDate': DateTime.utc(2030, 6, 25, 12).toIso8601String(),
            'endsAt': DateTime.utc(2030, 6, 25, 13).toIso8601String(),
          }),
          isNotNull,
        );
      },
    );
  });

  group('PostgresProviderAuthRepository', () {
    const provPhone = '+2250544556677';
    PostgresProviderAuthRepository repo({int maxAttempts = 5}) =>
        PostgresProviderAuthRepository(
          pool,
          tokens: tokens,
          isProd: false,
          maxAttempts: maxAttempts,
        );

    test(
      'register creates the account (+ link) then verify returns a token',
      () async {
        final r = repo();
        final reg = await r.register(
          email: 'reg28@test.pro',
          authProvider: 'google',
          googleSub: 'reg-sub-28',
          phoneNumber: provPhone,
          businessName: 'Élégance',
          businessType: 'salon',
          providerId: 'provider1',
        );
        expect(reg.ok, isTrue);
        expect(reg.provider!.providerId, 'provider1');
        expect(reg.tokens!.accessToken, isNotEmpty);

        // Duplicate identity (same email) is rejected.
        expect(
          (await r.register(
            email: 'reg28@test.pro',
            authProvider: 'google',
            googleSub: 'reg-sub-28b',
            phoneNumber: provPhone,
            businessName: 'X',
            businessType: 'salon',
          )).error,
          'provider_exists',
        );

        // The dormant phone-OTP path still logs the salon in.
        final code = (await r.requestOtp(provPhone)).devCode!;
        final ok = await r.verifyOtp(provPhone, code);
        expect(ok.ok, isTrue);
        expect(
          tokens.verifyAccessToken(ok.tokens!.accessToken)!.payload,
          containsPair('role', 'provider'),
        );
        expect((await r.accountById(ok.provider!.id))!.providerId, 'provider1');
      },
    );

    test(
      'refresh rotates; replaying a rotated token revokes the family',
      () async {
        final r = repo();
        final reg = await r.register(
          email: 'reg29@test.pro',
          authProvider: 'google',
          googleSub: 'reg-sub-29',
          phoneNumber: provPhone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        final first = reg.tokens!;

        final rotated = await r.refresh(first.refreshToken);
        expect(rotated.ok, isTrue);

        final reuse = await r.refresh(first.refreshToken);
        expect(reuse.error, 'refresh_reused');
        expect(
          (await r.refresh(rotated.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      },
    );

    test('verify requires registration; wrong codes lock out', () async {
      final r = repo(maxAttempts: 2);
      // Unregistered phone: a code can be requested, but verify → not found.
      final code = (await r.requestOtp('+2250500000000')).devCode!;
      expect(
        (await r.verifyOtp('+2250500000000', code)).error,
        'provider_not_found',
      );

      final reg = await r.register(
        email: 'reg30@test.pro',

        authProvider: 'google',

        googleSub: 'reg-sub-30',
        phoneNumber: provPhone,
        businessName: 'X',
        businessType: 'salon',
      );
      expect(reg.ok, isTrue);
      final sent = await r.requestOtp(provPhone);
      final wrong = sent.devCode == '111111' ? '222222' : '111111';
      expect((await r.verifyOtp(provPhone, wrong)).error, 'otp_invalid');
      expect((await r.verifyOtp(provPhone, wrong)).error, 'otp_locked');
    });

    test('submitKyc persists kyc_docs + pending; survives re-read', () async {
      final r = repo();
      final reg = await r.register(
        email: 'reg31@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-31',
        phoneNumber: provPhone,
        businessName: 'X',
        businessType: 'salon',
      );
      final id = reg.provider!.id;

      final updated = await r.submitKyc(id, [
        {
          'type': 'idCard',
          'fileName': 'id.jpg',
          'key': 'kyc/$id/a.jpg',
          'submittedAt': '2030-06-26T09:00:00.000Z',
        },
      ]);
      expect(updated!.verificationStatus, 'pending');
      expect(updated.kycDocs.single['type'], 'idCard');

      final reread = await r.accountById(id);
      expect(reread!.kycDocs.single['key'], 'kyc/$id/a.jpg');
      expect(await r.submitKyc('nope', const []), isNull);
    });
  });

  group('PostgresProvidersRepository', () {
    test('query returns seeded providers sorted by rating desc', () async {
      final repo = PostgresProvidersRepository(pool);
      final all = await repo.query();
      expect(all, isNotEmpty);
      for (var i = 1; i < all.length; i++) {
        expect(
          (all[i - 1]['rating'] as num) >= (all[i]['rating'] as num),
          isTrue,
        );
      }
    });

    test('filters by category and resolves byId', () async {
      final repo = PostgresProvidersRepository(pool);
      final barbers = await repo.query(category: 'barber');
      expect(barbers, isNotEmpty);
      expect(barbers.every((p) => p['category'] == 'barber'), isTrue);
      expect((await repo.byId('provider1'))?['id'], 'provider1');
      expect(await repo.byId('nope'), isNull);
    });

    test(
      'byId assembles services + availability from the normalized tables',
      () async {
        final p = await PostgresProvidersRepository(pool).byId('provider1');
        expect(p, isNotNull);

        final services = p!['services'] as List;
        expect(services, isNotEmpty);
        final svc = (services.first as Map).cast<String, dynamic>();
        expect(svc['providerId'], 'provider1');
        expect(svc.containsKey('active'), isTrue); // normalized flag present

        final avail = (p['availability'] as Map).cast<String, dynamic>();
        expect(avail['providerId'], 'provider1');
        expect(avail.containsKey('bufferMinutes'), isTrue);
        expect(avail['weeklySchedule'], isA<Map<dynamic, dynamic>>());
      },
    );

    test(
      'the backfill stripped services/availability from the providers doc',
      () async {
        final rows = await pool.execute(
          Sql.named('SELECT data FROM providers WHERE id = @id'),
          parameters: {'id': 'provider1'},
        );
        final data = rows.first.toColumnMap()['data'];
        final doc = data is String
            ? jsonDecode(data) as Map<String, dynamic>
            : Map<String, dynamic>.from(data as Map);
        expect(doc.containsKey('services'), isFalse);
        expect(doc.containsKey('availability'), isFalse);
      },
    );

    test(
      'query assembles the catalogue for every provider (no N+1 gaps)',
      () async {
        final all = await PostgresProvidersRepository(pool).query();
        expect(all, isNotEmpty);
        expect(
          all.every(
            (p) => p.containsKey('services') && p.containsKey('availability'),
          ),
          isTrue,
        );
      },
    );

    // Writes mutate provider3, kept last so the read assertions above (which
    // use provider1) are unaffected.
    test('addService / updateService / deleteService persist', () async {
      final repo = PostgresProvidersRepository(pool);
      final created = await repo.addService('provider3', {
        'id': 'svc_pr2_1',
        'name': 'Test',
        'description': '',
        'price': 5000.0,
        'priceMax': null,
        'durationMinutes': 30,
        'durationVariants': const <String, dynamic>{},
        'artistIds': const <String>[],
        'active': true,
      });
      expect(created, isNotNull);
      expect(created!['providerId'], 'provider3');

      final p = await repo.byId('provider3');
      expect(
        (p!['services'] as List).any((s) => s['id'] == 'svc_pr2_1'),
        isTrue,
      );

      final upd = await repo.updateService('provider3', 'svc_pr2_1', {
        'price': 6000.0,
        'active': false,
      });
      expect(upd!['price'], 6000);
      expect(upd['active'], false);

      expect(await repo.deleteService('provider3', 'svc_pr2_1'), isTrue);
      expect(await repo.deleteService('provider3', 'svc_pr2_1'), isFalse);
    });

    test('replaceAvailability replaces wholesale', () async {
      final repo = PostgresProvidersRepository(pool);
      final saved = await repo.replaceAvailability('provider3', {
        'providerId': 'provider3',
        'weeklySchedule': {
          '0': [
            {
              'startTime': '2024-01-01T08:00:00.000Z',
              'endTime': '2024-01-01T12:00:00.000Z',
              'isAvailable': true,
            },
          ],
        },
        'breaks': const <String, dynamic>{},
        'blockedDates': const ['2030-12-25T00:00:00.000Z'],
        'bufferMinutes': 25,
      });
      expect(saved!['bufferMinutes'], 25);

      final avail = (await repo.byId('provider3'))!['availability'] as Map;
      expect(avail['bufferMinutes'], 25);
      expect((avail['weeklySchedule'] as Map)['0'], isNotEmpty);
      expect((avail['blockedDates'] as List).length, 1);
    });

    test('addArtist / updateArtist / deleteArtist persist into data', () async {
      final repo = PostgresProvidersRepository(pool);
      final created = await repo.addArtist('provider3', {
        'id': 'artist_pr3_1',
        'name': 'Awa',
        'specialization': 'Tresses',
        'imageUrl': null,
        'providerId': 'provider3',
        'rating': null,
        'reviewCount': null,
        'workingHours': const <String, dynamic>{},
      });
      expect(created!['name'], 'Awa');
      expect(
        ((await repo.byId('provider3'))!['artists'] as List).any(
          (a) => a['id'] == 'artist_pr3_1',
        ),
        isTrue,
      );

      final upd = await repo.updateArtist('provider3', 'artist_pr3_1', {
        'name': 'Awa K.',
      });
      expect(upd!['name'], 'Awa K.');
      expect(
        await repo.updateArtist('provider3', 'nope', {'name': 'X'}),
        isNull,
      );

      expect(await repo.deleteArtist('provider3', 'artist_pr3_1'), isTrue);
      expect(await repo.deleteArtist('provider3', 'artist_pr3_1'), isFalse);
    });

    test('updateGallery persists into data and survives re-read', () async {
      final repo = PostgresProvidersRepository(pool);
      final saved = await repo.updateGallery('provider3', [
        'https://cdn/p3-a.jpg',
        'https://cdn/p3-b.jpg',
      ]);
      expect(saved, ['https://cdn/p3-a.jpg', 'https://cdn/p3-b.jpg']);

      final urls = (await repo.byId('provider3'))!['imageUrls'] as List;
      expect(urls, ['https://cdn/p3-a.jpg', 'https://cdn/p3-b.jpg']);

      expect(await repo.updateGallery('nope', const []), isNull);
    });

    test(
      'updateBeforeAfters persists into data and survives re-read',
      () async {
        final repo = PostgresProvidersRepository(pool);
        final saved = await repo.updateBeforeAfters('provider3', [
          {
            'before': 'https://cdn/b.jpg',
            'after': 'https://cdn/a.jpg',
            'caption': 'Tresses',
          },
        ]);
        expect(saved!.single['after'], 'https://cdn/a.jpg');

        final pairs = (await repo.byId('provider3'))!['beforeAfters'] as List;
        expect((pairs.single as Map)['caption'], 'Tresses');

        expect(await repo.updateBeforeAfters('nope', const []), isNull);
      },
    );

    test(
      'updateDepositPolicy persists into data and survives re-read',
      () async {
        final repo = PostgresProvidersRepository(pool);
        final saved = await repo.updateDepositPolicy('provider3', {
          'depositRequired': true,
          'depositPercentage': 0.35,
          'cancellationWindowHours': 48,
          'depositMobileMoneyOperator': 'wave',
          'depositMobileMoneyNumber': '+2250700000000',
        });
        expect(saved!['depositRequired'], true);

        final p = (await repo.byId('provider3'))!;
        expect(p['depositRequired'], true);
        expect(p['depositPercentage'], 0.35);
        expect(p['cancellationWindowHours'], 48);
        expect(p['depositMobileMoneyOperator'], 'wave');

        expect(await repo.updateDepositPolicy('nope', const {}), isNull);
      },
    );
  });

  group('PostgresAuthRepository', () {
    PostgresAuthRepository repo({int maxAttempts = 5}) =>
        PostgresAuthRepository(
          pool,
          tokens: tokens,
          isProd: false,
          maxAttempts: maxAttempts,
        );

    test(
      'verify issues tokens and find-or-creates one user per phone',
      () async {
        final r = repo();
        final v = await r.verifyOtp(
          phone,
          (await r.requestOtp(phone)).devCode!,
        );
        expect(v.ok, isTrue);
        expect(v.user!.phoneNumber, phone);
        final v2 = await r.verifyOtp(
          phone,
          (await r.requestOtp(phone)).devCode!,
        );
        expect(v2.user!.id, v.user!.id);
      },
    );

    test('wrong code decrements then locks out', () async {
      final r = repo(maxAttempts: 2);
      final code = (await r.requestOtp(phone)).devCode!;
      final wrong = code == '111111' ? '222222' : '111111';
      expect((await r.verifyOtp(phone, wrong)).error, 'otp_invalid');
      expect((await r.verifyOtp(phone, wrong)).error, 'otp_locked');
    });

    test(
      'refresh rotates; replaying a rotated token revokes the family',
      () async {
        final r = repo();
        final first = (await r.verifyOtp(
          phone,
          (await r.requestOtp(phone)).devCode!,
        )).tokens!;
        final rotated = await r.refresh(first.refreshToken);
        expect(rotated.ok, isTrue);

        final reuse = await r.refresh(first.refreshToken);
        expect(reuse.error, 'refresh_reused');
        expect(
          (await r.refresh(rotated.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      },
    );

    test('updateUser + deleteUser', () async {
      final r = repo();
      final user = (await r.verifyOtp(
        phone,
        (await r.requestOtp(phone)).devCode!,
      )).user!;
      expect((await r.updateUser(user.id, name: 'Awa'))!.name, 'Awa');
      expect((await r.updateUser(user.id, email: ''))!.email, isNull);
      expect(await r.deleteUser(user.id), isTrue);
      expect(await r.userById(user.id), isNull);
    });
  });

  group('PostgresFavoritesRepository', () {
    test(
      'add idempotent + newest-first + remove + per-user isolation',
      () async {
        final r = PostgresFavoritesRepository(pool);
        await r.add('fav_user_A', 'provider1');
        await r.add('fav_user_A', 'provider1'); // dup → no-op
        await r.add('fav_user_A', 'provider2');
        expect(await r.listForUser('fav_user_A'), ['provider2', 'provider1']);
        expect(await r.listForUser('fav_user_B'), isEmpty);

        await r.remove('fav_user_A', 'provider1');
        await r.remove('fav_user_A', 'provider1'); // already gone → no-op
        expect(await r.listForUser('fav_user_A'), ['provider2']);
      },
    );
  });

  group('PostgresClientsRepository (module clients C1)', () {
    late PostgresClientsRepository clients;
    late PostgresProviderAuditLogRepository audit;

    setUp(() {
      clients = PostgresClientsRepository(pool);
      audit = PostgresProviderAuditLogRepository(pool);
    });

    Map<String, dynamic> clientMap({
      required String id,
      String providerId = 'provider1',
      String? userId,
      String name = 'Aïcha',
      String? phone,
      List<String> tags = const [],
    }) => {
      'id': id,
      'providerId': providerId,
      'userId': userId,
      'displayName': name,
      'phone': phone,
      'tags': tags,
      'lastVisitAt': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    test('create + scoped lookups + uniqueness upsert', () async {
      await clients.create(
        clientMap(id: 'c1', phone: '+2250700000001', userId: null),
      );
      // Same phone again → conflict swallowed, existing row returned.
      final dup = await clients.create(
        clientMap(id: 'c1bis', phone: '+2250700000001'),
      );
      expect(dup['id'], 'c1');

      expect(await clients.byId('provider1', 'c1'), isNotNull);
      // T45: scoped — the same id under another salon resolves to nothing.
      expect(await clients.byId('provider2', 'c1'), isNull);
      expect(
        (await clients.byPhone('provider1', '+2250700000001'))?['id'],
        'c1',
      );
    });

    test(
      'list: search by name/digits, tag filter, pagination + sort',
      () async {
        await clients.create(
          clientMap(id: 'l1', name: 'Aminata', phone: '+2250701112233'),
        );
        await clients.create(
          clientMap(
            id: 'l2',
            name: 'Binta',
            phone: '+2250704445566',
            tags: ['VIP'],
          ),
        );
        await clients.touchLastVisit('provider1', 'l2', DateTime.utc(2026, 7));

        final all = await clients.list('provider1', page: 1, pageSize: 20);
        expect(all.total, 2);
        // last_visit_at DESC NULLS LAST → l2 first.
        expect(all.items.first['id'], 'l2');

        final byName = await clients.list(
          'provider1',
          query: 'amin',
          page: 1,
          pageSize: 20,
        );
        expect(byName.items.single['id'], 'l1');

        final byDigits = await clients.list(
          'provider1',
          query: '0704 44',
          page: 1,
          pageSize: 20,
        );
        expect(byDigits.items.single['id'], 'l2');

        final byTag = await clients.list(
          'provider1',
          tag: 'VIP',
          page: 1,
          pageSize: 20,
        );
        expect(byTag.items.single['id'], 'l2');
        expect(await clients.tagsFor('provider1'), ['VIP']);
      },
    );

    test('tags update, notes CRUD, anonymize (T48)', () async {
      await clients.create(
        clientMap(id: 'n1', userId: 'uX', phone: '+2250700000002'),
      );
      final updated = await clients.updateTags('provider1', 'n1', [
        'VIP',
        'Fidèle',
      ]);
      expect(updated?['tags'], ['VIP', 'Fidèle']);

      await clients.addNote({
        'id': 'note1',
        'clientId': 'n1',
        'authorAccountId': 'acct1',
        'body': 'Préfère Awa',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect((await clients.notesFor('n1')).single['body'], 'Préfère Awa');
      expect(await clients.deleteNote('n1', 'note1'), isTrue);
      expect(await clients.notesFor('n1'), isEmpty);

      await clients.anonymizeUser('uX');
      final anon = await clients.byId('provider1', 'n1');
      expect(anon?['userId'], isNull);
      expect(anon?['displayName'], 'Client');
      expect(anon?['phone'], isNull);
    });

    test('audit log round-trips (T46)', () async {
      await audit.log(
        providerId: 'provider1',
        actorAccountId: 'acct1',
        action: 'clients.list',
        meta: {'query': 'ami'},
      );
      final entries = await audit.entriesFor('provider1');
      expect(entries.single['action'], 'clients.list');
      expect((entries.single['meta'] as Map)['query'], 'ami');
    });

    test('0024 backfill created rows from historical bookings', () async {
      // The migration ran in setUpAll against whatever appointments existed;
      // here we assert the derived-upsert path stays consistent with it:
      // a completed booking + touchLastVisit orders the list.
      await clients.create(clientMap(id: 'b1', phone: '+2250700000003'));
      await clients.touchLastVisit('provider1', 'b1', DateTime.utc(2026, 7, 2));
      // Regressions never move it backwards.
      await clients.touchLastVisit('provider1', 'b1', DateTime.utc(2026, 6, 1));
      final row = await clients.byId('provider1', 'b1');
      expect(row?['lastVisitAt'], DateTime.utc(2026, 7, 2).toIso8601String());
    });
  });

  group('PostgresReviewsRepository', () {
    Map<String, dynamic> rv(String appt, {int rating = 5, String? artist}) => {
      'id': 'rev_$appt',
      'appointmentId': appt,
      'providerId': 'provider1',
      'userId': 'u_$appt',
      'userName': 'U',
      'rating': rating,
      'text': 'ok',
      'verified': true,
      'artistId': artist,
      'artistName': artist == null ? null : 'A',
      'serviceName': 'Coupe',
      'photoUrls': ['https://cdn/x.jpg'],
      'createdAt': DateTime.utc(2030, 6, int.parse(appt)).toIso8601String(),
    };

    test(
      'upsert-by-appointment + paginate + aggregate (provider + artist)',
      () async {
        final r = PostgresReviewsRepository(pool);
        await r.upsertByAppointment(rv('1', rating: 4, artist: 'artist1'));
        await r.upsertByAppointment(rv('1', rating: 2, artist: 'artist1'));
        await r.upsertByAppointment(rv('2', rating: 5));

        final page = await r.listForProvider('provider1', pageSize: 1);
        expect(page.total, 2);
        expect(page.items, hasLength(1));
        expect(page.items.first['photoUrls'], ['https://cdn/x.jpg']);

        final agg = await r.aggregateProvider('provider1');
        expect(agg.count, 2);
        expect(agg.rating, (2 + 5) / 2);

        final byArtist = await r.aggregateByArtist('provider1');
        expect(byArtist['artist1']!.count, 1);
        expect(byArtist['artist1']!.rating, 2);

        expect(await r.recentForProvider('provider1', 1), hasLength(1));
      },
    );
  });
}
