@Tags(['postgres'])
library;

import 'dart:io';

import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/db/postgres_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_providers_repository.dart';
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
  });

  tearDownAll(() async => pool.close());

  setUp(() async {
    // Isolate state between tests; the seeded providers stay.
    await pool.execute(
      'TRUNCATE appointments, refresh_tokens, otp_codes, users, '
      'provider_users, provider_otp_codes, provider_refresh_tokens CASCADE',
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
}
