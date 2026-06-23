@Tags(['postgres'])
library;

import 'dart:io';

import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_auth_repository.dart';
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
    // Isolate auth state between tests; the seeded providers stay.
    await pool.execute('TRUNCATE refresh_tokens, otp_codes, users CASCADE');
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
