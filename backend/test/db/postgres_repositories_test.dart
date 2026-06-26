@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/db/postgres_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_favorites_repository.dart';
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
      'favorites, reviews CASCADE',
    );
  });

  Map<String, dynamic> apptMap({
    required String id,
    String userId = 'u1',
    String providerId = 'provider1',
    String status = 'pending',
    required DateTime when,
  }) => {
    'id': id,
    'userId': userId,
    'providerId': providerId,
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': when.toUtc().toIso8601String(),
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
          phoneNumber: provPhone,
          businessName: 'Élégance',
          businessType: 'salon',
          providerId: 'provider1',
        );
        expect(reg.ok, isTrue);
        expect(reg.provider!.providerId, 'provider1');
        expect(reg.devCode, isNotNull);

        // Duplicate phone is rejected.
        expect(
          (await r.register(
            phoneNumber: provPhone,
            businessName: 'X',
            businessType: 'salon',
          )).error,
          'provider_exists',
        );

        final ok = await r.verifyOtp(provPhone, reg.devCode!);
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
          phoneNumber: provPhone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        final first = (await r.verifyOtp(provPhone, reg.devCode!)).tokens!;

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
        phoneNumber: provPhone,
        businessName: 'X',
        businessType: 'salon',
      );
      final wrong = reg.devCode == '111111' ? '222222' : '111111';
      expect((await r.verifyOtp(provPhone, wrong)).error, 'otp_invalid');
      expect((await r.verifyOtp(provPhone, wrong)).error, 'otp_locked');
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
