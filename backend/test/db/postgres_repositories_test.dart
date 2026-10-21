@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart'
    show RefreshOutcome, RefreshResult, TokenPair, kRefreshReuseGrace;
import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/boot_config.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart'
    show GuestPhoneChange, GuestPhoneOutcome;
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/db/postgres_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_client_version_repository.dart';
import 'package:myweli_backend/src/db/postgres_clients_repository.dart';
import 'package:myweli_backend/src/db/postgres_device_token_repository.dart';
import 'package:myweli_backend/src/db/postgres_favorites_repository.dart';
import 'package:myweli_backend/src/db/postgres_membership_repository.dart';
import 'package:myweli_backend/src/db/postgres_notification_prefs_repository.dart';
import 'package:myweli_backend/src/db/postgres_notifications_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_audit_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_providers_repository.dart';
import 'package:myweli_backend/src/db/postgres_reviews_repository.dart';
import 'package:myweli_backend/src/db/postgres_salon_subscription_repository.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/salon_time.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../idempotency/idempotency_contract.dart';

import '../access/invite_contract.dart';

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
    initSalonTime(); // salonWallClock needs the tz database
    pool = createPool(url);
    // **Under the schema lock, exactly as `dependencies.dart` does it.**
    // `runMigrations` does not take the lock itself — the caller does — and
    // calling it bare was safe here only while this was the ONLY test file that
    // did. A second DB-gated file made the two race, and `CREATE TABLE IF NOT
    // EXISTS` is not atomic against a concurrent creator: both check, both find
    // it absent, and one loses with 23505 on `pg_type_typname_nsp_index`.
    // Production already knew this — "Cloud Run boots cold instances in
    // parallel where Render never did" — and the tests were the copy that had
    // drifted.
    await withSchemaLock(pool, () async {
      await runMigrations(pool);
      await seedProvidersIfEmpty(pool, env: Env.dev);
      await backfillCatalogueIfNeeded(
        pool,
      ); // match production: catalogue → tables
    });
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

  /// Moves a token's rotation [ago] into the past on the DATABASE clock — the
  /// clock the grace is measured on — or, with null, clears it the way a row
  /// rotated before migration 0037 has it. How a test reaches either side of
  /// the 30 s grace without sleeping.
  Future<void> rotatedAgo(String table, String token, Duration? ago) =>
      pool.execute(
        Sql.named(
          ago == null
              ? 'UPDATE $table SET rotated_at = NULL WHERE token_hash = @h'
              : 'UPDATE $table SET rotated_at = now() - @ago:interval '
                    'WHERE token_hash = @h',
        ),
        parameters: {'h': tokens.hashToken(token), 'ago': ?ago},
      );

  /// The refresh-token family [token] belongs to, or null once it is gone.
  Future<String?> familyOf(String table, String token) async {
    final r = await pool.execute(
      Sql.named('SELECT family_id FROM $table WHERE token_hash = @h'),
      parameters: {'h': tokens.hashToken(token)},
    );
    return r.isEmpty ? null : r.first.toColumnMap()['family_id'] as String;
  }

  /// The token's `rotated_at` exactly as stored, or null.
  Future<DateTime?> rotatedAtOf(String table, String token) async {
    final r = await pool.execute(
      Sql.named('SELECT rotated_at FROM $table WHERE token_hash = @h'),
      parameters: {'h': tokens.hashToken(token)},
    );
    return r.first.toColumnMap()['rotated_at'] as DateTime?;
  }

  Future<int> familySize(String table, String familyId) async {
    final r = await pool.execute(
      Sql.named('SELECT count(*)::int AS n FROM $table WHERE family_id = @f'),
      parameters: {'f': familyId},
    );
    return r.first.toColumnMap()['n'] as int;
  }

  Map<String, dynamic> apptMap({
    required String id,
    String userId = 'u1',
    String providerId = 'provider1',
    String status = 'pending',
    int durationMinutes = 30,
    required DateTime when,
    String? artistId,
  }) => {
    'id': id,
    'userId': userId,
    'providerId': providerId,
    'serviceIds': ['service1'],
    'artistId': artistId,
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

    test('the partial unique index blocks a second booking on the same slot '
        'FOR THE SAME ARTIST (capacity model, migration 0026)', () async {
      final repo = PostgresAppointmentRepository(pool);
      expect(
        await repo.create(apptMap(id: 'a1', when: when, artistId: 'ar1')),
        isNotNull,
      );
      // Same provider + artist + exact start, still pending → null.
      expect(
        await repo.create(
          apptMap(id: 'a2', userId: 'u2', when: when, artistId: 'ar1'),
        ),
        isNull,
      );
      // A DIFFERENT artist takes the same slot — the multi-chair win.
      expect(
        await repo.create(
          apptMap(id: 'a2b', userId: 'u2', when: when, artistId: 'ar2'),
        ),
        isNotNull,
      );
      // After the first is cancelled, ar1's chair frees up.
      await repo.update('a1', {'status': 'cancelled'});
      expect(
        await repo.create(
          apptMap(id: 'a3', userId: 'u3', when: when, artistId: 'ar1'),
        ),
        isNotNull,
      );
      // Unassigned bookings are UNGUARDED at the DB level by design — the
      // slot engine's pool count owns them (spec §2.2).
      expect(await repo.create(apptMap(id: 'a4', when: when)), isNotNull);
      expect(
        await repo.create(apptMap(id: 'a5', userId: 'u5', when: when)),
        isNotNull,
      );
    });

    test(
      'btree_gist exclusion blocks duration overlaps (not just exact start)',
      () async {
        final repo = PostgresAppointmentRepository(pool);
        final at9 = DateTime.utc(2030, 6, 25, 9);
        // ar1, 09:00 for 120 min → occupies [09:00, 11:00).
        expect(
          await repo.create(
            apptMap(id: 'o1', when: at9, durationMinutes: 120, artistId: 'ar1'),
          ),
          isNotNull,
        );
        // ar1 again at 10:00 overlaps [09:00, 11:00) → rejected.
        expect(
          await repo.create(
            apptMap(
              id: 'o2',
              userId: 'u2',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
              artistId: 'ar1',
            ),
          ),
          isNull,
        );
        // The SAME overlap on another artist → allowed (per-artist chairs).
        expect(
          await repo.create(
            apptMap(
              id: 'o2b',
              userId: 'u2',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
              artistId: 'ar2',
            ),
          ),
          isNotNull,
        );
        // 11:00 is back-to-back for ar1 (half-open range) → allowed.
        expect(
          await repo.create(
            apptMap(
              id: 'o3',
              userId: 'u3',
              when: DateTime.utc(2030, 6, 25, 11),
              durationMinutes: 60,
              artistId: 'ar1',
            ),
          ),
          isNotNull,
        );
        // Same artist id at a DIFFERENT provider → allowed (per-provider).
        expect(
          await repo.create(
            apptMap(
              id: 'o4',
              userId: 'u4',
              providerId: 'provider2',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
              artistId: 'ar1',
            ),
          ),
          isNotNull,
        );
        // Cancelling o1 frees ar1's [09:00, 11:00) → a 10:00 booking fits.
        await repo.update('o1', {'status': 'cancelled'});
        expect(
          await repo.create(
            apptMap(
              id: 'o5',
              userId: 'u5',
              when: DateTime.utc(2030, 6, 25, 10),
              durationMinutes: 60,
              artistId: 'ar1',
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
        // Both bookings on the SAME artist — per-artist guards (0026).
        await repo.create(
          apptMap(
            id: 'r1',
            when: DateTime.utc(2030, 6, 25, 9),
            durationMinutes: 120,
            artistId: 'ar1',
          ),
        );
        await repo.create(
          apptMap(
            id: 'r2',
            userId: 'u2',
            when: DateTime.utc(2030, 6, 25, 14),
            durationMinutes: 60,
            artistId: 'ar1',
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
          echoDevCode: true,
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

        // Past the 30 s grace — inside it a replay gets a sibling (the
        // `refresh exchange` group below).
        await rotatedAgo(
          'provider_refresh_tokens',
          first.refreshToken,
          kRefreshReuseGrace + const Duration(seconds: 1),
        );
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
    /// Delete a salon this suite created, on the way out.
    ///
    /// **`providers` is the one table `setUp` deliberately does NOT truncate**
    /// — the seeded demo salons have to survive, because sibling tests read
    /// `provider1` by id and assert on the seeded ordering. So anything
    /// `createSalon` writes here lives forever unless the test removes it, and
    /// six such rows had accumulated in a local database before this was
    /// noticed.
    void deleteOnTearDown(String id) => addTearDown(
      () => pool.execute(
        Sql.named('DELETE FROM providers WHERE id = @id'),
        parameters: {'id': id},
      ),
    );

    test('createSalon persists a hidden draft; linkProvider attaches it '
        '(pro-salon-lifecycle.md)', () async {
      final repo = PostgresProvidersRepository(pool);
      final before = (await repo.query()).length;
      final salon = await repo.createSalon(
        name: 'Salon Test Lifecycle',
        category: 'salon',
        phoneNumber: '+2250700000042',
        address: 'Rue du Test',
      );
      final id = salon['id'] as String;
      deleteOnTearDown(id);
      expect(salon['status'], 'draft');
      // Hidden from discovery (T51)…
      expect((await repo.query()).length, before);
      // …readable by id, and by slug at repo level (the route gates it).
      expect((await repo.byId(id))?['name'], 'Salon Test Lifecycle');
      // **The slug is read back from the document, never guessed.**
      //
      // This asserted `bySlug('salon-test-lifecycle')` for a long time, and
      // that is only correct against an EMPTY providers table. `slug` carries a
      // unique index, so `createSalon` suffixes on collision — the second run
      // against the same database creates `salon-test-lifecycle-2`, while
      // `bySlug('salon-test-lifecycle')` keeps returning the row the FIRST run
      // left behind. The test therefore passed exactly once per database and
      // failed on every run after, which reads like flakiness and is not: the
      // repository was behaving correctly and the assertion was wrong.
      //
      // CI never saw it, because CI runs `dart test` with no `DATABASE_URL` and
      // every postgres-tagged suite self-skips. Only a developer with a local
      // database ever ran it twice.
      expect((await repo.bySlug(salon['slug'] as String))?['id'], id);

      // Publish → discoverable.
      await repo.setStatus(id, 'active');
      expect((await repo.query()).any((x) => x['id'] == id), isTrue);

      // linkProvider round-trip on the auth side.
      final auth = PostgresProviderAuthRepository(
        pool,
        tokens: TokenService(secret: 'test-secret'),
        echoDevCode: true,
      );
      final reg = await auth.register(
        businessName: 'Salon Test Lifecycle',
        businessType: 'salon',
        phoneNumber: '+2250700000042',
        email: 'lifecycle@salon.test',
        authProvider: 'google',
        googleSub: 'sub-lifecycle',
      );
      expect(reg.ok, isTrue);
      expect(reg.provider!.providerId, isNull);
      await auth.linkProvider(reg.provider!.id, id);
      expect((await auth.accountById(reg.provider!.id))?.providerId, id);
    });

    test(
      'two salons of the same name get distinct slugs, each addressable',
      () async {
        // The behaviour that made the bug above look like flakiness, and which
        // nothing exercised on purpose. `slug` carries a unique index
        // (`providers_slug_idx`), so `createSalon` walks `-2`, `-3`, … until it
        // finds a free one. Two salons genuinely may share a name — « Chez Awa »
        // is not reserved to whoever registered first — so the suffix is product
        // behaviour, not a workaround, and it deserves a test that says so.
        final repo = PostgresProvidersRepository(pool);
        const name = 'Salon Slug Collision';
        const base = 'salon-slug-collision';

        final first = await repo.createSalon(
          name: name,
          category: 'salon',
          phoneNumber: '+2250700000043',
        );
        deleteOnTearDown(first['id'] as String);
        final second = await repo.createSalon(
          name: name,
          category: 'salon',
          phoneNumber: '+2250700000044',
        );
        deleteOnTearDown(second['id'] as String);

        // Asserted as "shares the base, differs overall" rather than as the
        // literal `$base-2`: on a database where an earlier row already holds
        // the base, these are `-2` and `-3`. Pinning the exact suffix would
        // reintroduce the very assumption this file just stopped making.
        expect(first['slug'], startsWith(base));
        expect(second['slug'], startsWith(base));
        expect(second['slug'], isNot(first['slug']));

        // Each resolves to ITS OWN row — the property the old assertion meant to
        // check and could not, because it guessed the slug instead of reading it.
        expect(
          (await repo.bySlug(first['slug'] as String))?['id'],
          first['id'],
        );
        expect(
          (await repo.bySlug(second['slug'] as String))?['id'],
          second['id'],
        );
      },
    );

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

    test('a blocked date is the SALON calendar day, not the UTC one', () async {
      // `provider_blocked_dates.blocked_date` is a `date` column, and the write
      // took `(d as String).split('T').first` — the UTC calendar date of what
      // the client sent. The client sends SALON midnight, so for any salon east
      // of Greenwich that instant belongs to the PREVIOUS UTC day:
      //
      //   Lagos (UTC+1), blocking the 15th
      //     client sends  2026-03-14T23:00:00.000Z
      //     split('T')    2026-03-14        ← the pro blocked the 15th
      //     read back     2026-03-14T00:00Z → salon day 14. Wrong day, closed.
      //
      // Latent only because every seeded city is Africa/Abidjan (UTC+0). A14e
      // writes these in BULK, which is why this is fixed ahead of it.
      final repo = PostgresProvidersRepository(pool);
      // `providers.data` is jsonb holding a JSON *string* (the doc is
      // jsonEncode-d into it), so `jsonb_set` cannot path into it — read,
      // decode, set, re-encode, exactly as the repository's own writes do.
      final row = await pool.execute(
        Sql.named('SELECT data FROM providers WHERE id = @pid'),
        parameters: {'pid': 'provider3'},
      );
      final raw = row.first.toColumnMap()['data'];
      final doc =
          (raw is String ? jsonDecode(raw) : jsonDecode(jsonEncode(raw)))
              as Map<String, dynamic>;
      doc['timezone'] = 'Africa/Lagos';
      await pool.execute(
        Sql.named('UPDATE providers SET data = @data:jsonb WHERE id = @pid'),
        parameters: {'pid': 'provider3', 'data': jsonEncode(doc)},
      );

      // Salon midnight, 15 March 2026, in Lagos = 14 March 23:00 UTC.
      const salonMidnightUtc = '2026-03-14T23:00:00.000Z';
      await repo.replaceAvailability('provider3', {
        'providerId': 'provider3',
        'weeklySchedule': const <String, dynamic>{},
        'breaks': const <String, dynamic>{},
        'blockedDates': const [salonMidnightUtc],
        'bufferMinutes': 0,
      });

      final avail = (await repo.byId('provider3'))!['availability'] as Map;
      final stored = (avail['blockedDates'] as List).single as String;

      // What the client will make of it: the same conversion every reader
      // already does (mock_appointment_service.dart, mock_provider_service.dart
      // and slot_service.dart all compare through salonWallClock).
      final asSalonDay = salonWallClock(DateTime.parse(stored), 'Africa/Lagos');
      expect(
        asSalonDay.day,
        15,
        reason:
            'the pro blocked 15 March; a UTC-derived date closes 14 March '
            'instead — one day early, silently, on every salon east of UTC',
      );
      expect(asSalonDay.month, 3);
      expect(asSalonDay.year, 2026);
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
          echoDevCode: true,
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

        // Past the 30 s grace — inside it a replay gets a sibling (the
        // `refresh exchange` group below).
        await rotatedAgo(
          'refresh_tokens',
          first.refreshToken,
          kRefreshReuseGrace + const Duration(seconds: 1),
        );
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

  // The atomic exchange with the 30 s grace, on the two tables this file owns
  // (docs/design/backend-refresh-rotation-atomic.md §8). Here and not in a file
  // of its own because this file TRUNCATEs both tables in `setUp`: a second
  // file would race that. Admin is pinned in postgres_admin_auth_test.dart.
  group('refresh exchange — atomic, 30 s grace', () {
    // A second pool, so eight exchanges can hold eight connections AT ONCE —
    // one pool is capped at four per instance (kMaxConnectionsPerInstance).
    late Pool<void> pool2;
    setUpAll(() => pool2 = createPool(url));
    tearDownAll(() => pool2.close());

    // Holds a child INSERT into one family until the test lets go: a BEFORE
    // INSERT trigger, scoped to that family, that must take an advisory lock
    // the test holds. Keys are this file's own (postgres_admin_auth_test.dart
    // uses another range), so a concurrently running file never waits on one.
    const kHoldClass = 0x4D57;
    var nextHoldKey = 1000;
    Future<int> holdChildInserts(String table, String family) async {
      final key = nextHoldKey++;
      await pool.execute(
        r'CREATE OR REPLACE FUNCTION mw_test_hold_child() RETURNS trigger '
        r'LANGUAGE plpgsql AS $$ BEGIN '
        r'PERFORM pg_advisory_xact_lock(TG_ARGV[0]::int, TG_ARGV[1]::int); '
        r'RETURN NEW; END $$',
      );
      Future<void> drop() =>
          pool.execute('DROP TRIGGER IF EXISTS mw_test_hold_child ON $table');
      addTearDown(drop);
      await pool.execute(
        'CREATE TRIGGER mw_test_hold_child BEFORE INSERT ON $table '
        "FOR EACH ROW WHEN (NEW.family_id = '$family') "
        "EXECUTE FUNCTION mw_test_hold_child('$kHoldClass', '$key')",
      );
      return key;
    }

    Future<bool> childInsertWaiting(int key) async {
      final r = await pool.execute(
        'SELECT count(*)::int AS n FROM pg_locks '
        "WHERE locktype = 'advisory' AND NOT granted "
        'AND classid = $kHoldClass AND objid = $key AND objsubid = 2',
      );
      return r.first.toColumnMap()['n'] == 1;
    }

    Future<bool> familyDeleteWaiting(String table) async {
      final r = await pool.execute(
        'SELECT count(*)::int AS n FROM pg_stat_activity '
        "WHERE wait_event_type = 'Lock' "
        "AND query LIKE 'DELETE FROM $table WHERE family_id%'",
      );
      return r.first.toColumnMap()['n'] == 1;
    }

    /// Polls [probe] until true — bounded, so a setup that never reaches the
    /// interleaving fails loudly instead of hanging or passing.
    Future<void> until(Future<bool> Function() probe, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!await probe()) {
        if (DateTime.now().isAfter(deadline)) fail('never reached: $what');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    var n = 0;
    // `email_otp_codes` is not truncated between tests, so addresses carry a
    // per-run nonce — a re-run must not meet its own unexpired codes.
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final principals =
        <
          ({
            String name,
            String table,
            Future<TokenPair> Function() login,
            Future<RefreshResult> Function(Pool<void> on, String token) refresh,
          })
        >[
          (
            name: 'consumer',
            table: 'refresh_tokens',
            login: () async {
              final r = PostgresAuthRepository(
                pool,
                tokens: tokens,
                echoDevCode: true,
              );
              final email = 'rot${n++}-$nonce@myweli.test';
              final code = (await r.requestEmailOtp(email)).devCode!;
              return (await r.verifyEmailOtp(email, code)).tokens!;
            },
            refresh: (on, t) => PostgresAuthRepository(
              on,
              tokens: tokens,
              echoDevCode: true,
            ).refresh(t),
          ),
          (
            name: 'provider',
            table: 'provider_refresh_tokens',
            login: () async {
              final i = n++;
              return (await PostgresProviderAuthRepository(
                    pool,
                    tokens: tokens,
                    echoDevCode: true,
                  ).register(
                    email: 'rot$i@test.pro',
                    authProvider: 'google',
                    googleSub: 'rot-sub-$i',
                    phoneNumber: '+2250566${i.toString().padLeft(6, '0')}',
                    businessName: 'Rotation $i',
                    businessType: 'salon',
                  ))
                  .tokens!;
            },
            refresh: (on, t) => PostgresProviderAuthRepository(
              on,
              tokens: tokens,
              echoDevCode: true,
            ).refresh(t),
          ),
        ];

    for (final p in principals) {
      test('${p.name}: N = 8 concurrent exchanges of one token → all ok, '
          'EXACTLY ONE rotated, seven grace siblings, all in its family '
          '(repeated, to make an interleaving likely)', () async {
        for (var round = 0; round < 6; round++) {
          final first = await p.login();
          final family = (await familyOf(p.table, first.refreshToken))!;
          final results = await Future.wait([
            for (var i = 0; i < 8; i++)
              p.refresh(i.isEven ? pool : pool2, first.refreshToken),
          ]);
          expect(
            results.map((r) => r.ok),
            everyElement(isTrue),
            reason: 'round $round: every racer is a legitimate use',
          );
          expect(
            results.where((r) => r.outcome == RefreshOutcome.rotated),
            hasLength(1),
            reason: 'round $round: the claim is atomic — exactly one winner',
          );
          expect(
            results.where((r) => r.outcome == RefreshOutcome.grace),
            hasLength(7),
            reason: 'round $round',
          );
          for (final r in results) {
            expect(
              await familyOf(p.table, r.tokens!.refreshToken),
              family,
              reason: 'round $round: no fork — every child is in the family',
            );
          }
          // The parent plus eight children, and the parent rotated once.
          expect(await familySize(p.table, family), 9, reason: 'round $round');
          final parent = await pool.execute(
            Sql.named(
              'SELECT rotated, rotated_at FROM ${p.table} WHERE token_hash = @h',
            ),
            parameters: {'h': tokens.hashToken(first.refreshToken)},
          );
          expect(parent.first.toColumnMap()['rotated'], isTrue);
          expect(parent.first.toColumnMap()['rotated_at'], isNotNull);
        }
      });

      test('${p.name}: rotated 29 s ago → GRACE, family intact; '
          '31 s ago → refresh_reused and the family is gone', () async {
        final first = await p.login();
        final child = await p.refresh(pool, first.refreshToken);
        expect(child.outcome, RefreshOutcome.rotated);
        final family = (await familyOf(p.table, first.refreshToken))!;

        await rotatedAgo(
          p.table,
          first.refreshToken,
          const Duration(seconds: 29),
        );
        final rotatedAt = await rotatedAtOf(p.table, first.refreshToken);
        expect(rotatedAt, isNotNull);
        final sibling = await p.refresh(pool, first.refreshToken);
        expect(sibling.outcome, RefreshOutcome.grace);
        expect(sibling.ok, isTrue);
        expect(sibling.error, isNull);
        expect(
          await familyOf(p.table, sibling.tokens!.refreshToken),
          family,
          reason: 'a sibling joins the SAME family',
        );
        expect(await familySize(p.table, family), 3, reason: 'nothing revoked');
        // The grace runs from the FIRST rotation. A grace exchange that moved
        // `rotated_at` would let a replay every 29 s keep it open forever, and
        // reuse would never be detected. The 31 s step below backdates the
        // row itself, so it cannot see this; only this read can.
        expect(
          await rotatedAtOf(p.table, first.refreshToken),
          rotatedAt,
          reason: 'a grace exchange must not move the parent\'s rotated_at',
        );

        await rotatedAgo(
          p.table,
          first.refreshToken,
          const Duration(seconds: 31),
        );
        final reuse = await p.refresh(pool, first.refreshToken);
        expect(reuse.outcome, RefreshOutcome.reused);
        expect(reuse.ok, isFalse);
        expect(reuse.error, 'refresh_reused');
        expect(reuse.tokens, isNull);
        expect(await familySize(p.table, family), 0, reason: 'family revoked');
        for (final dead in [child, sibling]) {
          final r = await p.refresh(pool, dead.tokens!.refreshToken);
          expect(r.outcome, RefreshOutcome.invalid);
          expect(r.error, 'refresh_invalid');
        }
      });

      test('${p.name}: a row rotated before migration 0037 (rotated_at NULL) '
          'is outside the grace → refresh_reused', () async {
        final first = await p.login();
        final child = await p.refresh(pool, first.refreshToken);
        expect(child.outcome, RefreshOutcome.rotated);
        await rotatedAgo(p.table, first.refreshToken, null);

        final reuse = await p.refresh(pool, first.refreshToken);
        expect(reuse.outcome, RefreshOutcome.reused);
        expect(reuse.error, 'refresh_reused');
        expect(
          (await p.refresh(pool, child.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      });

      test(
        '${p.name}: a grace exchange that arrives while a family revoke '
        'already holds the rows WAITS for it and mints nothing (FOR UPDATE)',
        () async {
          final first = await p.login();
          await p.refresh(pool, first.refreshToken); // rotated: now in grace
          final family = (await familyOf(p.table, first.refreshToken))!;

          late Future<RefreshResult> racing;
          await pool.runTx((tx) async {
            await tx.execute(
              Sql.named('DELETE FROM ${p.table} WHERE family_id = @f'),
              parameters: {'f': family},
            );
            // The revoke holds the family's rows, uncommitted. The exchange
            // starts now, on another connection, and must wait for it.
            racing = p.refresh(pool2, first.refreshToken);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          });

          final r = await racing;
          expect(r.outcome, RefreshOutcome.invalid);
          expect(r.error, 'refresh_invalid');
          expect(
            await familySize(p.table, family),
            0,
            reason: 'no sibling slipped into the family as it was revoked',
          );
        },
      );

      // The other order: the exchange locked its row FIRST and is inserting
      // its child when the revoke arrives. The revoke's DELETE waits on that
      // row, and its snapshot predates the child — so ONE DELETE left the child
      // alive, unrotated, in a family whose reuse caller was told
      // refresh_reused. The revoke now repeats until it deletes nothing.
      // Ordered with an advisory lock the child insert must take (a trigger
      // scoped to this family), not with sleeps.
      for (final grace in [true, false]) {
        final what = grace
            ? 'a grace sibling'
            : 'the child of a plain rotation of the newest token';
        test(
          '${p.name}: $what, minted while a family revoke waits on its '
          'row, is deleted by that revoke too (the DELETE repeats)',
          () async {
            final t0 = await p.login();
            final t1 = (await p.refresh(pool, t0.refreshToken)).tokens!;
            final newest = (await p.refresh(pool, t1.refreshToken)).tokens!;
            final family = (await familyOf(p.table, t0.refreshToken))!;
            // t0 past the grace: presenting it is reuse. t1 was rotated just
            // now, so it is in the grace; the newest is unrotated.
            await rotatedAgo(
              p.table,
              t0.refreshToken,
              const Duration(minutes: 1),
            );
            final key = await holdChildInserts(p.table, family);

            late Future<RefreshResult> minting;
            late Future<RefreshResult> revoking;
            await pool.runTx((hold) async {
              await hold.execute(
                'SELECT pg_advisory_xact_lock($kHoldClass, $key)',
              );
              minting = p.refresh(
                pool2,
                grace ? t1.refreshToken : newest.refreshToken,
              );
              await until(
                () => childInsertWaiting(key),
                'the exchange holds its row and waits to insert its child',
              );
              revoking = p.refresh(pool2, t0.refreshToken);
              await until(
                () => familyDeleteWaiting(p.table),
                'the revoke DELETE waits on the row the exchange holds',
              );
            }); // the hold ends: the child commits, then the DELETE resumes

            final m = await minting;
            expect(
              m.outcome,
              grace ? RefreshOutcome.grace : RefreshOutcome.rotated,
            );
            final r = await revoking;
            expect(r.outcome, RefreshOutcome.reused);
            expect(r.error, 'refresh_reused');
            expect(
              await familySize(p.table, family),
              0,
              reason:
                  'the child committed while the revoke waited is revoked '
                  'with the rest of its family',
            );
            expect(
              (await p.refresh(pool, m.tokens!.refreshToken)).outcome,
              RefreshOutcome.invalid,
            );
          },
        );
      }

      test('${p.name}: an unknown token → refresh_invalid', () async {
        final r = await p.refresh(pool, 'never-issued');
        expect(r.outcome, RefreshOutcome.invalid);
        expect(r.ok, isFalse);
        expect(r.error, 'refresh_invalid');
        expect(r.tokens, isNull);
      });
    }
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

  group(
    'PostgresNotificationPrefsRepository — emailAlerts (migration 0039)',
    () {
      // docs/design/salon-email-alerts.md: on by default; merges like the rest.
      test('default on; an update merges and keeps the others', () async {
        final repo = PostgresNotificationPrefsRepository(pool);
        final id = 'prefs-${DateTime.now().microsecondsSinceEpoch}';
        expect((await repo.get(id)).emailAlerts, isTrue);
        var p = await repo.update(id, emailAlerts: false);
        expect(p.emailAlerts, isFalse);
        expect(p.push, isTrue);
        p = await repo.update(id, push: false);
        expect(p.emailAlerts, isFalse, reason: 'preserved');
        expect((await repo.get(id)).emailAlerts, isFalse);
        await repo.deleteForUser(id);
      });
    },
  );

  group('PostgresClientVersionRepository (migration 0032)', () {
    test('the migration seeds four rows, all with NO floor', () async {
      // The mechanism must be inert on the day it ships. If this fails, a
      // deploy has started making version policy nobody decided.
      final r = PostgresClientVersionRepository(pool);
      final all = await r.all();
      expect(all, hasLength(4));
      expect(all.every((f) => f.minimumBuild == 0), isTrue);
      expect(all.every((f) => f.recommendedBuild == 0), isTrue);
      expect(all.map((f) => '${f.appId}/${f.platform}').toList(), [
        'com.myweli.app/android',
        'com.myweli.app/ios',
        'com.myweli.pro/android',
        'com.myweli.pro/ios',
      ]);
    });

    test('android is seeded with a store URL, ios deliberately NULL', () async {
      // Play's listing key IS the applicationId; iOS needs an adamId that does
      // not exist yet. The nullability is the design, not an oversight.
      final r = PostgresClientVersionRepository(pool);
      final android = await r.floor('com.myweli.app', 'android');
      final ios = await r.floor('com.myweli.app', 'ios');
      expect(android!.updateUrl, contains('play.google.com'));
      expect(ios!.updateUrl, isNull);
    });

    test('setFloor round-trips and UPDATEs, never inserts', () async {
      final r = PostgresClientVersionRepository(pool);
      final updated = await r.setFloor(
        'com.myweli.pro',
        'android',
        minimumBuild: 4,
        recommendedBuild: 6,
        updateUrl: 'https://x.test/p',
      );
      expect(updated!.minimumBuild, 4);
      expect((await r.floor('com.myweli.pro', 'android'))!.recommendedBuild, 6);

      // A typo'd app id must not silently create a row that governs nothing.
      expect(
        await r.setFloor(
          'com.myweli.typo',
          'android',
          minimumBuild: 1,
          recommendedBuild: 0,
          updateUrl: null,
        ),
        isNull,
      );
      expect(await r.all(), hasLength(4));

      // Leave the shared fixture as we found it.
      await r.setFloor(
        'com.myweli.pro',
        'android',
        minimumBuild: 0,
        recommendedBuild: 0,
        updateUrl:
            'https://play.google.com/store/apps/details?id=com.myweli.pro',
      );
    });

    test('an unknown pair reads as null, not an error', () async {
      final r = PostgresClientVersionRepository(pool);
      expect(await r.floor('com.myweli.app', 'windows'), isNull);
    });
  });

  group('journal J1 columns (module journal)', () {
    test('update round-trips arrivedAt + artistId (migration 0025)', () async {
      final repo = PostgresAppointmentRepository(pool);
      final when = DateTime.utc(2026, 8, 3, 10);
      await repo.create(apptMap(id: 'j1', status: 'confirmed', when: when));
      final arrived = await repo.update('j1', {
        'arrivedAt': when.toIso8601String(),
        'artistId': 'artist1',
      });
      expect(arrived?['arrivedAt'], when.toIso8601String());
      expect(arrived?['artistId'], 'artist1');
      // Clearing works too.
      final cleared = await repo.update('j1', {'arrivedAt': null});
      expect(cleared?['arrivedAt'], isNull);
    });
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

    test(
      'list: rows tied on both sort keys come back in id order, so a page '
      'walk sees each exactly once (web-pro-export-completeness.md §5)',
      () async {
        // One statement, one now(): the 0024 backfill's shape — the same
        // created_at, and no completed visit (NULL last_visit_at). Inserted
        // out of id order, so the heap order is not the answer by luck.
        await pool.execute(
          'INSERT INTO salon_clients '
          '(id, provider_id, user_id, display_name, phone) VALUES '
          "('t5', 'provider1', NULL, 'E', NULL), "
          "('t3', 'provider1', NULL, 'C', NULL), "
          "('t1', 'provider1', NULL, 'A', NULL), "
          "('t4', 'provider1', NULL, 'D', NULL), "
          "('t2', 'provider1', NULL, 'B', NULL)",
        );

        final walked = <String>[];
        for (var page = 1; page <= 3; page++) {
          final r = await clients.list('provider1', page: page, pageSize: 2);
          expect(r.total, 5);
          walked.addAll(r.items.map((c) => c['id'] as String));
        }
        expect(walked, ['t1', 't2', 't3', 't4', 't5']);

        final whole = await clients.list('provider1', page: 1, pageSize: 50);
        expect(whole.items.map((c) => c['id']), walked);
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

    // docs/design/phone-leftovers.md §8 — a guest's history resolves by
    // phone, so the card and its manual bookings move in ONE transaction.
    group('changeGuestPhone', () {
      const oldPhone = '+2250700000101';
      const newPhone = '+2250500000202';
      late PostgresAppointmentRepository appts;

      setUp(() => appts = PostgresAppointmentRepository(pool));

      Future<void> booking(
        String id, {
        String providerId = 'provider1',
        String userId = 'manual',
        String? phone = oldPhone,
        required int day,
      }) => appts.create({
        ...apptMap(
          id: id,
          userId: userId,
          providerId: providerId,
          status: 'completed',
          when: DateTime.utc(2030, 7, day, 9),
        ),
        'clientPhone': phone,
      });

      Future<String?> phoneOf(String appointmentId) async =>
          (await appts.byId(appointmentId))?['clientPhone'] as String?;

      test('the card and THIS salon\'s manual bookings with the old number '
          'move — never another salon\'s (T45), never a consumer\'s own, '
          'never a phone-less walk-in', () async {
        await clients.create(clientMap(id: 'pc1', phone: oldPhone));
        await booking('pm1', day: 1);
        await booking('pm2', day: 2);
        await booking('px1', providerId: 'provider2', day: 3);
        await booking('pu1', userId: 'u1', day: 4);
        await booking('pw1', phone: null, day: 5);

        final r = await clients.changeGuestPhone('provider1', 'pc1', newPhone);
        expect(r.outcome, GuestPhoneOutcome.changed);
        expect(r.client?['phone'], newPhone);
        expect((await clients.byId('provider1', 'pc1'))?['phone'], newPhone);
        expect(await phoneOf('pm1'), newPhone);
        expect(await phoneOf('pm2'), newPhone);
        expect(await phoneOf('px1'), oldPhone);
        expect(await phoneOf('pu1'), oldPhone);
        expect(await phoneOf('pw1'), isNull);
      });

      test('notFound across salons; linked; unchanged; taken — each writes '
          'nothing', () async {
        await clients.create(clientMap(id: 'pc1', phone: oldPhone));
        await clients.create(
          clientMap(id: 'pl1', userId: 'uL', phone: '+2250100000303'),
        );
        await clients.create(clientMap(id: 'pc2', phone: newPhone));
        await booking('pm1', day: 1);

        expect(
          (await clients.changeGuestPhone(
            'provider2',
            'pc1',
            '+2250500000404',
          )).outcome,
          GuestPhoneOutcome.notFound,
        );
        expect(
          (await clients.changeGuestPhone(
            'provider1',
            'pl1',
            '+2250500000404',
          )).outcome,
          GuestPhoneOutcome.linked,
        );
        expect(
          (await clients.changeGuestPhone(
            'provider1',
            'pc1',
            oldPhone,
          )).outcome,
          GuestPhoneOutcome.unchanged,
        );
        final taken = await clients.changeGuestPhone(
          'provider1',
          'pc1',
          newPhone,
        );
        expect(taken.outcome, GuestPhoneOutcome.taken);
        expect(taken.takenBy, 'pc2');

        expect((await clients.byId('provider1', 'pc1'))?['phone'], oldPhone);
        expect(
          (await clients.byId('provider1', 'pl1'))?['phone'],
          '+2250100000303',
        );
        expect(await phoneOf('pm1'), oldPhone);
      });

      test('a race lost on salon_clients_phone_key is `taken` — never a '
          'throw — and the loser moves nothing', () async {
        await clients.create(clientMap(id: 'rc1', phone: oldPhone));
        await booking('rm1', day: 1);

        late Future<Object> loser;
        await pool.runTx((tx) async {
          // Another request files the number and has not committed: the
          // loser's own look-up cannot see it, so its UPDATE waits on the
          // index entry — then fails 23505 when this commits.
          await tx.execute(
            Sql.named(
              'INSERT INTO salon_clients '
              '(id, provider_id, user_id, display_name, phone) '
              "VALUES ('rc2', 'provider1', NULL, 'Arrivée', @p)",
            ),
            parameters: {'p': newPhone},
          );
          loser = clients
              .changeGuestPhone('provider1', 'rc1', newPhone)
              .then<Object>((r) => r, onError: (Object e) => e);
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });

        final outcome = await loser;
        expect(outcome, isA<GuestPhoneChange>(), reason: '$outcome');
        final r = outcome as GuestPhoneChange;
        expect(r.outcome, GuestPhoneOutcome.taken);
        expect(r.takenBy, 'rc2');
        expect((await clients.byId('provider1', 'rc1'))?['phone'], oldPhone);
        expect(await phoneOf('rm1'), oldPhone);
      });
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

    test(
      'ratingDistribution: per star, visible only (salon-reviews-summary)',
      () async {
        // `reviews.provider_id` references a real salon, and the shared
        // fixture salon carries other tests' reviews: measure the change.
        final r = PostgresReviewsRepository(pool);
        final before = await r.ratingDistribution('provider1');
        expect(before.keys.toSet(), {5, 4, 3, 2, 1});
        Map<String, dynamic> one(String appt, int rating) => {
          'id': 'rev_dist_$appt',
          'appointmentId': 'dist_$appt',
          'providerId': 'provider1',
          'userId': 'u_dist_$appt',
          'userName': 'U',
          'rating': rating,
          'text': 'ok',
          'verified': true,
          'photoUrls': const <String>[],
          'createdAt': DateTime.utc(2030, 7, 1).toIso8601String(),
        };
        await r.upsertByAppointment(one('1', 5));
        await r.upsertByAppointment(one('2', 5));
        await r.upsertByAppointment(one('3', 2));
        await r.upsertByAppointment(one('4', 1));
        await pool.execute(
          Sql.named(
            "UPDATE reviews SET moderation_status = 'hidden' "
            'WHERE appointment_id = @a',
          ),
          parameters: {'a': 'dist_4'},
        );
        final after = await r.ratingDistribution('provider1');
        expect(
          {for (final k in after.keys) k: after[k]! - before[k]!},
          {
            5: 2,
            4: 0,
            3: 0,
            2: 1,
            1: 0, // hidden: counts nowhere
          },
        );
        expect(await r.ratingDistribution('no-such-salon'), {
          5: 0,
          4: 0,
          3: 0,
          2: 0,
          1: 0,
        });
      },
    );

    test('reviewByAppointment finds a HIDDEN review too', () async {
      // The moderation filter every other read carries would be wrong here: a
      // hidden review still owns its photo objects, so filtering it out makes
      // its author's own resubmit fail on their own stored urls — the
      // moderation state leaking out as an unexplained 400 on a path that has
      // nothing to do with it.
      final r = PostgresReviewsRepository(pool);
      await r.upsertByAppointment(rv('7'));
      await pool.execute(
        Sql.named(
          "UPDATE reviews SET moderation_status = 'hidden' "
          'WHERE appointment_id = @a',
        ),
        parameters: {'a': '7'},
      );
      final got = await r.reviewByAppointment('7');
      expect(got, isNotNull, reason: 'hidden is still the author\'s review');
      expect(got!['photoUrls'], ['https://cdn/x.jpg']);
      expect(await r.reviewByAppointment('no-such-appt'), isNull);
    });
  });

  /// The statement that actually deletes production rows.
  ///
  /// `PostgresDeviceTokenRepository` had **no** coverage here at all, which is
  /// how an unscoped `DELETE` driven by a misclassified FCM error went
  /// unnoticed. `remove` is deliberately not user-scoped — the provider reports
  /// a dead token, not a user — so the test pins that, and pins that the
  /// user-scoped variant refuses to cross accounts.
  // The invitation contract on the REAL schema — `UNIQUE (provider_id,
  // email)` is what the in-memory twin never had: re-inviting a revoked or
  // expired address raised 23505 here and answered 500 in production.
  // docs/design/backend-team-reinvite.md
  group('PostgresMembershipRepository — invite, the twin contract', () {
    var n = 0;
    inviteContract(
      repo: () => PostgresMembershipRepository(pool),
      providerId: 'provider1', // seeded
      account: (email) async {
        n++;
        final reg =
            await PostgresProviderAuthRepository(
              pool,
              tokens: tokens,
              echoDevCode: true,
            ).register(
              email: email,
              authProvider: 'google',
              googleSub: 'sub-contract-$n',
              phoneNumber: '+22505000020${n.toString().padLeft(2, '0')}',
              businessName: 'Contract',
              businessType: 'salon',
            );
        return reg.provider!.id;
      },
    );
  });

  // docs/design/write-idempotency.md §3 — the same contract as the in-memory
  // twin, on the real table (migration 0040).
  group('PostgresIdempotencyStore — the twin contract', () {
    idempotencyContract(
      store: (now) => PostgresIdempotencyStore(pool, now: now),
      prefix: 'pg-${DateTime.now().microsecondsSinceEpoch}-',
    );
  });

  group('PostgresDeviceTokenRepository (module push)', () {
    test(
      'remove deletes exactly one token; removeForUser is owner-scoped',
      () async {
        final r = PostgresDeviceTokenRepository(pool);
        await r.upsert(
          token: 'tok-a',
          userId: 'dtu1',
          role: 'user',
          platform: 'android',
        );
        await r.upsert(
          token: 'tok-b',
          userId: 'dtu1',
          role: 'user',
          platform: 'ios',
        );
        await r.upsert(
          token: 'tok-c',
          userId: 'dtu2',
          role: 'user',
          platform: 'android',
        );

        // Unscoped: takes the one token and nothing adjacent.
        await r.remove('tok-a');
        expect(await r.tokensForUser('dtu1'), ['tok-b']);
        expect(await r.tokensForUser('dtu2'), ['tok-c']);

        // Scoped: dtu1 must not be able to remove dtu2's token.
        await r.removeForUser('dtu1', 'tok-c');
        expect(await r.tokensForUser('dtu2'), [
          'tok-c',
        ], reason: 'removeForUser is owner-scoped');

        await r.removeForUser('dtu2', 'tok-c');
        expect(await r.tokensForUser('dtu2'), isEmpty);
      },
    );

    test('devicesForUser returns each token with its platform', () async {
      // docs/design/web-pro-browser-push.md §4: the notifier tells the app
      // from browsers by this column.
      final r = PostgresDeviceTokenRepository(pool);
      await r.upsert(
        token: 'tok-web',
        userId: 'dtu3',
        role: 'provider',
        platform: 'web',
      );
      await r.upsert(
        token: 'tok-and',
        userId: 'dtu3',
        role: 'provider',
        platform: 'android',
      );
      expect((await r.devicesForUser('dtu3')).toSet(), {
        (token: 'tok-web', platform: 'web'),
        (token: 'tok-and', platform: 'android'),
      });
      await r.deleteForUser('dtu3');
    });

    test('removing a token that is already gone is a no-op', () async {
      // The prune loop can race two fan-outs to the same user.
      final r = PostgresDeviceTokenRepository(pool);
      await r.remove('never-existed');
      expect(await r.tokensForUser('dtu1'), isNot(contains('never-existed')));
    });
  });

  /// The publish-time trial start (docs/design/pro-companion-path.md §3.1)
  /// writes through `createIfAbsent`, and its whole claim is the SQL: `ON
  /// CONFLICT DO NOTHING`, where `create` says `DO UPDATE SET tier`. The
  /// in-memory twin proves the interface; only this proves the statement.
  group('PostgresSalonSubscriptionRepository (companion path)', () {
    /// `provider_subscriptions` references `providers(id)`, which `setUp`
    /// does not truncate — so each test makes its own salon and removes
    /// both rows on the way out.
    Future<String> freshSalon() async {
      final salon = await PostgresProvidersRepository(pool).createSalon(
        name: 'Salon Test Offre',
        category: 'salon',
        phoneNumber: '+2250700000043',
      );
      final id = salon['id'] as String;
      addTearDown(() async {
        await pool.execute(
          Sql.named(
            'DELETE FROM provider_subscriptions WHERE provider_id = @id',
          ),
          parameters: {'id': id},
        );
        await pool.execute(
          Sql.named('DELETE FROM providers WHERE id = @id'),
          parameters: {'id': id},
        );
      });
      return id;
    }

    test('createIfAbsent inserts once, then NEVER overwrites tier, clock or '
        'paid coverage', () async {
      final repo = PostgresSalonSubscriptionRepository(pool);
      final id = await freshSalon();
      final t1 = DateTime.utc(2027, 1, 1);
      final created = await repo.createIfAbsent(
        providerId: id,
        tier: 'business',
        trialEndsAt: t1,
      );
      expect(created.tier, 'business');
      expect(created.trialEndsAt.toUtc(), t1);
      final paid = DateTime.utc(2027, 2, 1);
      await repo.update(id, paidUntil: paid);

      final again = await repo.createIfAbsent(
        providerId: id,
        tier: 'pro',
        trialEndsAt: DateTime.utc(2030, 1, 1),
      );
      expect(again.tier, 'business', reason: 'the winner row is read back');
      expect(again.trialEndsAt.toUtc(), t1);
      expect(again.paidUntil?.toUtc(), paid);
      final stored = (await repo.byProvider(id))!;
      expect(stored.tier, 'business');
      expect(stored.trialEndsAt.toUtc(), t1);
    });

    test('two concurrent createIfAbsent calls leave exactly ONE row, and both '
        'callers see it', () async {
      final repo = PostgresSalonSubscriptionRepository(pool);
      final id = await freshSalon();
      final results = await Future.wait([
        repo.createIfAbsent(
          providerId: id,
          tier: 'pro',
          trialEndsAt: DateTime.utc(2027, 1, 1),
        ),
        repo.createIfAbsent(
          providerId: id,
          tier: 'reseau',
          trialEndsAt: DateTime.utc(2028, 1, 1),
        ),
      ]);
      expect(results[0].tier, results[1].tier);
      expect(results[0].trialEndsAt, results[1].trialEndsAt);
      final count = await pool.execute(
        Sql.named(
          'SELECT count(*)::int AS n FROM provider_subscriptions '
          'WHERE provider_id = @id',
        ),
        parameters: {'id': id},
      );
      expect(count.first.toColumnMap()['n'], 1);
    });

    test('create keeps its upsert: a later CHOICE switches the tier and keeps '
        'the clock (chooseOffer semantics unchanged)', () async {
      final repo = PostgresSalonSubscriptionRepository(pool);
      final id = await freshSalon();
      final t1 = DateTime.utc(2027, 1, 1);
      await repo.createIfAbsent(providerId: id, tier: 'pro', trialEndsAt: t1);

      final chosen = await repo.create(
        providerId: id,
        tier: 'business',
        trialEndsAt: DateTime.utc(2030, 1, 1),
      );
      expect(chosen.tier, 'business');
      expect(chosen.trialEndsAt.toUtc(), t1);
    });
  });

  // ---- Provider account deletion on the REAL schema (T53) -----------------
  // Production answered 500 `ForeignKeyViolationException` to every
  // `DELETE /me/provider` from a salon owner (2026-10-14, revision
  // myweli-api-00037-zzq): the service REVOKED the account's
  // `provider_members` rows — an UPDATE that keeps `account_id` — and the
  // identity delete then met `provider_members.account_id`, a foreign key
  // with no ON DELETE action. Every deletion test ran on the in-memory twins,
  // which have no foreign keys at all. These run the production wiring
  // (`dependencies.dart`) over the real schema.
  // docs/design/backend-provider-deletion-member-fk.md
  group('provider account deletion — on the real schema (T53)', () {
    PostgresProviderAuthRepository authRepo() =>
        PostgresProviderAuthRepository(pool, tokens: tokens, echoDevCode: true);

    ProviderAccountService service() => ProviderAccountService(
      authRepo(),
      PostgresProvidersRepository(pool),
      PostgresAppointmentRepository(pool),
      FakeStorageService(),
      PostgresMembershipRepository(pool),
      devices: PostgresDeviceTokenRepository(pool),
      notifications: PostgresNotificationsRepository(pool),
      client: MockClient((_) async => http.Response('', 204)),
    );

    Future<int> count(String sql, Map<String, Object?> parameters) async {
      final r = await pool.execute(Sql.named(sql), parameters: parameters);
      return r.first.first! as int;
    }

    /// An owner exactly as production makes one: a draft salon, the account
    /// linked to it, and the owner membership row
    /// (`SalonProvisioningService.ensureSalon`).
    Future<({String id, String salonId})> owner(
      String email,
      String phone,
    ) async {
      final salon = await PostgresProvidersRepository(pool).createSalon(
        name: 'Salon $email',
        category: 'salon',
        phoneNumber: phone,
      );
      final salonId = salon['id'] as String;
      final reg = await authRepo().register(
        email: email,
        authProvider: 'google',
        googleSub: 'sub-$email',
        phoneNumber: phone,
        businessName: 'Salon',
        businessType: 'salon',
        providerId: salonId,
      );
      final id = reg.provider!.id;
      await PostgresMembershipRepository(
        pool,
      ).ensureOwner(providerId: salonId, accountId: id, email: email);
      return (id: id, salonId: salonId);
    }

    test('a salon owner with a team is erased — the production path, end to '
        'end', () async {
      final members = PostgresMembershipRepository(pool);
      final providers = PostgresProvidersRepository(pool);
      final devices = PostgresDeviceTokenRepository(pool);
      final notifications = PostgresNotificationsRepository(pool);

      final o = await owner('del-owner@test.pro', '+2250500001001');
      await providers.setStatus(o.salonId, 'active');

      // A teammate in the owner's salon — their row must survive.
      final mate = (await authRepo().register(
        email: 'del-mate@test.pro',
        authProvider: 'google',
        googleSub: 'sub-del-mate',
        phoneNumber: '+2250500001002',
        businessName: 'Mate',
        businessType: 'salon',
      )).provider!.id;
      final mateInvite = await members.invite(
        providerId: o.salonId,
        email: 'del-mate@test.pro',
        role: 'staff',
        artistId: 'a1',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await members.activate(mateInvite!.id, mate);

      // A second salon where the owner is only STAFF: the row goes with the
      // identity, the salon itself is untouched (R6 — member-only salons).
      final other = await owner('del-other@test.pro', '+2250500001003');
      await providers.setStatus(other.salonId, 'active');
      final staffInvite = await members.invite(
        providerId: other.salonId,
        email: 'del-owner@test.pro',
        role: 'staff',
        artistId: 'a1',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await members.activate(staffInvite!.id, o.id);

      await devices.upsert(
        token: 'tok-del-owner',
        userId: o.id,
        role: 'provider',
        platform: 'ios',
      );
      await notifications.add(
        userId: o.id,
        type: 'system',
        title: 'Bienvenue',
        body: 'Votre salon est prêt.',
      );
      expect(
        await count(
          'SELECT count(*)::int FROM provider_members WHERE account_id = @a',
          {'a': o.id},
        ),
        2,
        reason: 'the control: the owner row and the staff row exist',
      );

      final r = await service().deleteAccount(o.id);

      expect(r.ok, isTrue);
      expect(r.error, isNull);
      expect(await authRepo().accountById(o.id), isNull);
      expect(
        await count(
          'SELECT count(*)::int FROM provider_members WHERE account_id = @a',
          {'a': o.id},
        ),
        0,
        reason: 'a member row never outlives its account',
      );
      expect(
        await count(
          'SELECT count(*)::int FROM provider_refresh_tokens '
          'WHERE account_id = @a',
          {'a': o.id},
        ),
        0,
      );
      expect((await providers.byId(o.salonId))!['status'], 'draft');
      // Scoped: the teammate keeps their seat, the other salon its owner and
      // its listing.
      expect(await members.activeMember(mate, o.salonId), isNotNull);
      expect(await members.activeMember(other.id, other.salonId), isNotNull);
      expect((await providers.byId(other.salonId))!['status'], 'active');
      expect(await devices.tokensForUser(o.id), isEmpty);
      expect(await notifications.listForUser(o.id, limit: 10), isEmpty);
    });

    test('no foreign key into an identity table can block its delete', () async {
      // The class of the defect, not just its instance: a table added later
      // that references an identity without ON DELETE would re-open the same
      // 500 on the same button. Each row is (table.column → identity, action);
      // `a`/`r` (no action / restrict) block the delete.
      final rows = await pool.execute('''
SELECT c.conrelid::regclass::text, a.attname::text,
       c.confrelid::regclass::text, c.confdeltype::text
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f'
  AND c.confrelid IN ('users'::regclass, 'provider_users'::regclass,
                      'admins'::regclass)''');
      final all = [for (final r in rows) '${r[0]}.${r[1]} → ${r[2]}: ${r[3]}'];
      // Not vacuous: the refresh-token tables of all three identities and the
      // member table are found.
      expect(all.length, greaterThanOrEqualTo(4), reason: all.join('\n'));
      expect(
        all.where((r) => !r.endsWith(': c') && !r.endsWith(': n')),
        isEmpty,
        reason: all.join('\n'),
      );
    });

    test('a failed identity delete changes nothing — the sessions survive '
        '(one transaction)', () async {
      final reg = await authRepo().register(
        email: 'del-atomic@test.pro',
        authProvider: 'google',
        googleSub: 'sub-del-atomic',
        phoneNumber: '+2250500001004',
        businessName: 'Atomic',
        businessType: 'salon',
      );
      final id = reg.provider!.id;
      Future<int> sessions() => count(
        'SELECT count(*)::int FROM provider_refresh_tokens '
        'WHERE account_id = @a',
        {'a': id},
      );
      final before = await sessions();
      expect(before, greaterThan(0));

      // A dependent row the delete cannot pass: a probe table, created and
      // dropped here (a TEMP table cannot reference a permanent one).
      await pool.execute(
        'CREATE TABLE deletion_blocker_probe '
        '(account_id text REFERENCES provider_users(id))',
      );
      try {
        await pool.execute(
          Sql.named('INSERT INTO deletion_blocker_probe VALUES (@a)'),
          parameters: {'a': id},
        );

        await expectLater(
          authRepo().deleteAccount(id),
          throwsA(isA<ServerException>()),
        );

        expect(await authRepo().accountById(id), isNotNull);
        expect(
          await sessions(),
          before,
          reason:
              'the sessions were deleted before the failing statement — the '
              'account is left signed out and undeletable',
        );
      } finally {
        await pool.execute('DROP TABLE IF EXISTS deletion_blocker_probe');
      }
    });

    test('a deletion that fails at the identity keeps the team rows — nothing '
        'of the account is lost before the last step', () async {
      // The rows go WITH the identity (0038's cascade, inside its
      // transaction), never before it: deleted first, a failed identity
      // delete lost them for good, and in between an account with no
      // membership at all let GET /me/provider auto-create a salon for a
      // staff account (adversarial review of 959c9634).
      final o = await owner('del-order@test.pro', '+2250500001005');
      Future<int> rows() => count(
        'SELECT count(*)::int FROM provider_members WHERE account_id = @a',
        {'a': o.id},
      );
      expect(await rows(), 1, reason: 'the control: the owner row exists');

      await pool.execute(
        'CREATE TABLE deletion_blocker_probe '
        '(account_id text REFERENCES provider_users(id))',
      );
      try {
        await pool.execute(
          Sql.named('INSERT INTO deletion_blocker_probe VALUES (@a)'),
          parameters: {'a': o.id},
        );

        await expectLater(
          service().deleteAccount(o.id),
          throwsA(isA<ServerException>()),
        );

        expect(await authRepo().accountById(o.id), isNotNull);
        expect(
          await rows(),
          1,
          reason: 'the team row was deleted before the identity delete failed',
        );
      } finally {
        await pool.execute('DROP TABLE IF EXISTS deletion_blocker_probe');
      }
    });
  });
}
