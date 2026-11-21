import 'dart:io';

import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_membership_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_audit_repository.dart';
import 'package:myweli_backend/src/db/postgres_provider_auth_repository.dart';
import 'package:myweli_backend/src/db/postgres_salon_purge_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/maintenance/salon_purge_repository.dart';
import 'package:myweli_backend/src/maintenance/salon_purge_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The salon purge's SQL on the REAL schema (B0.24,
/// docs/design/deleted-owner-salon-purge.md §9): 0046's dropped key, every
/// statement of §4, the rehearsal's rollback, `SKIP LOCKED`, the guards'
/// inputs, the deletion's stamp, steps 7–8 and the writer's encoding.
///
/// **Its OWN database, made here and dropped at the end — never the shared
/// one** (the precedent and the reasons: `postgres_admin_provider_account_
/// test.dart`). The purge is GLOBAL — « every ownerless salon » — so on the
/// shared database it would rehearse and record the other files' salons, and
/// their wipes would land in the middle of these tests.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'postgres salon purge (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  late PostgresSalonPurgeRepository repo;
  late FakeStorageService storage;
  late _Mail mail;
  final ownDbName = 'myweli_purge_${DateTime.now().microsecondsSinceEpoch}';
  final now = DateTime.now().toUtc();
  final dueClock = now.subtract(const Duration(days: 91));

  setUpAll(() async {
    final admin = createPool(url);
    await admin.execute('CREATE DATABASE $ownDbName');
    await admin.close();
    pool = createPool(_withDatabase(url, ownDbName));
    await withSchemaLock(pool, () => runMigrations(pool));
  });

  tearDownAll(() async {
    await pool.close();
    final admin = createPool(url);
    await admin.execute('DROP DATABASE IF EXISTS $ownDbName WITH (FORCE)');
    await admin.close();
  });

  setUp(() async {
    await pool.execute(
      'TRUNCATE providers, provider_users, salon_purge_queue, audit_log, '
      'notifications, appointments, salon_clients, provider_audit_log, '
      'favorites, demo_snapshot, provider_members CASCADE',
    );
    repo = PostgresSalonPurgeRepository(pool);
    storage = FakeStorageService();
    mail = _Mail();
  });

  SalonPurgeService service(SalonPurgeMode mode, {int max = 10}) =>
      SalonPurgeService(
        repo,
        storage,
        SalonPurgeNotifier(
          PostgresMembershipRepository(pool),
          InMemoryProvidersRepository([]),
          mail,
        ),
        mode: mode,
        maxPerRun: max,
        log: (_) {},
      );

  Future<void> sql(String s, [Map<String, Object?>? p]) =>
      pool.execute(Sql.named(s), parameters: p ?? const {});

  Future<int> count(String s, [Map<String, Object?>? p]) async =>
      (await pool.execute(Sql.named(s), parameters: p ?? const {})).first[0]!
          as int;

  /// A salon. [data] is stored as a JSON **string**, as production holds
  /// `providers.data` (8 of 8 rows, 2026-11-20).
  Future<void> salon(
    String id, {
    String status = 'draft',
    String data = '{}',
  }) => sql(
    'INSERT INTO providers (id, category, commune, rating, name, '
    "description, address, data, status) VALUES (@id, 'salon', 'Cocody', 0, "
    "@id, '', '', to_jsonb(@data::text), @status)",
    {'id': id, 'data': data, 'status': status},
  );

  Future<void> account(String id, {String? providerId}) => sql(
    'INSERT INTO provider_users (id, phone_number, name, business_name, '
    'business_type, email, address, verification_status, provider_id) '
    "VALUES (@id, '', '', '', '', @mail, '', 'pending', @p)",
    {'id': id, 'mail': '$id@x.com', 'p': providerId},
  );

  Future<void> member(
    String id,
    String salonId, {
    String? accountId,
    String role = 'staff',
    String status = 'active',
  }) => sql(
    'INSERT INTO provider_members (id, provider_id, account_id, email, role, '
    'status, invited_at) VALUES (@id, @p, @a, @mail, @role, @status, now())',
    {
      'id': id,
      'p': salonId,
      'a': accountId,
      'mail': '$id@x.com',
      'role': role,
      'status': status,
    },
  );

  Future<void> queue(String id, DateTime? clock) => sql(
    'INSERT INTO salon_purge_queue (provider_id, owner_erased_at, '
    'clock_started_at) VALUES (@p, @at, @clock:timestamptz)',
    {'p': id, 'at': clock ?? now, 'clock': clock},
  );

  Future<void> booking(
    String id,
    String salonId, {
    bool ahead = false,
    String? deposit,
  }) => sql(
    'INSERT INTO appointments (id, user_id, provider_id, service_ids, '
    'appointment_date, status, total_price, deposit_amount, balance_due, '
    "deposit_screenshot_url) VALUES (@id, 'u1', @p, '[]', @at, 'confirmed', "
    '1000, 0, 0, @dep:text)',
    {
      'id': id,
      'p': salonId,
      'at': ahead
          ? now.add(const Duration(days: 30))
          : now.subtract(const Duration(days: 30)),
      'dep': deposit,
    },
  );

  /// A full salon: every table of §2.2 and §2.3 holds a row for it.
  Future<void> fullSalon(String id) async {
    await salon(
      id,
      data:
          '{"imageUrls":["https://cdn.x/gallery/$id/a.jpg"],'
          '"logoUrl":"https://cdn.x/logo/$id/l.jpg"}',
    );
    await account('acct_${id}_m');
    await account('acct_${id}_i');
    await member('${id}_m1', id, accountId: 'acct_${id}_m');
    await member('${id}_m2', id, accountId: 'acct_${id}_i', status: 'invited');
    await member('${id}_m3', id, status: 'invited');
    await sql(
      'INSERT INTO provider_services (id, provider_id, name, price, '
      "duration_minutes) VALUES (@s, @p, 'Coupe', 1000, 30)",
      {'s': '${id}_svc', 'p': id},
    );
    await sql(
      'INSERT INTO provider_working_hours (id, provider_id, weekday, '
      "start_time, end_time, is_available) VALUES (@h, @p, 1, '09:00', "
      "'18:00', true)",
      {'h': '${id}_h', 'p': id},
    );
    await booking('${id}_a1', id, deposit: 'deposit/u1/$id.jpg');
    await booking('${id}_a2', id, ahead: true);
    await sql(
      "INSERT INTO disputes (id, appointment_id, opened_by, status, reason) "
      "VALUES (@d, @a, 'admin', 'resolved', 'motif')",
      {'d': '${id}_d', 'a': '${id}_a1'},
    );
    await sql(
      'INSERT INTO reviews (id, appointment_id, provider_id, user_id, '
      "user_name, rating, text, photo_urls) VALUES (@r, @a, @p, 'u1', 'n', 5, "
      "'t', to_jsonb(@photos::text))",
      {
        'r': '${id}_r',
        'a': '${id}_a1',
        'p': id,
        'photos': '["https://cdn.x/review/u1/$id.jpg"]',
      },
    );
    await sql(
      'INSERT INTO salon_clients (id, provider_id, display_name, phone) '
      "VALUES (@c, @p, 'Awa', '')",
      {'c': '${id}_c', 'p': id},
    );
    await sql(
      'INSERT INTO salon_client_notes (id, client_id, author_account_id, body) '
      "VALUES (@n, @c, 'acct_x', 'note')",
      {'n': '${id}_n', 'c': '${id}_c'},
    );
    await sql(
      'INSERT INTO provider_audit_log (id, provider_id, actor_account_id, '
      "action, meta) VALUES (@l, @p, 'acct_x', 'clients.list', "
      "'{\"query\":\"Awa\"}'::jsonb)",
      {'l': '${id}_l', 'p': id},
    );
    await sql(
      'INSERT INTO provider_subscriptions (provider_id, tier, trial_ends_at) '
      "VALUES (@p, 'trial', now())",
      {'p': id},
    );
    await sql(
      "INSERT INTO subscription_notices (provider_id, kind) VALUES (@p, 'trial_j7')",
      {'p': id},
    );
    await sql(
      "INSERT INTO favorites (user_id, provider_id) VALUES ('u1', @p)",
      {'p': id},
    );
    for (final (n, route) in [
      ('a', '/pro/appointment/${id}_a1?salon=$id'),
      ('b', '/pro/onboarding?salon=$id'),
      ('c', '/pro/appointments'),
    ]) {
      await sql(
        'INSERT INTO notifications (id, user_id, type, title, body, route) '
        "VALUES (@n, @u, 't', 't', 'b', @r)",
        {'n': '${id}_n$n', 'u': 'acct_${id}_m', 'r': route},
      );
    }
    await sql(
      'INSERT INTO audit_log (id, actor_admin_id, action, target_type, '
      "target_id, reason) VALUES (@i1, 'adm', 'provider.suspend', 'provider', "
      "@p, 'motif'), (@i2, 'adm', 'dispute.open', 'appointment', @a, 'motif'), "
      "(@i3, 'adm', 'dispute.resolve', 'dispute', @d, 'motif'), "
      "(@i4, 'adm', 'review.hide', 'review', @r, 'motif')",
      {
        'i1': '${id}_x1',
        'i2': '${id}_x2',
        'i3': '${id}_x3',
        'i4': '${id}_x4',
        'p': id,
        'a': '${id}_a1',
        'd': '${id}_d',
        'r': '${id}_r',
      },
    );
  }

  /// Every table the purge reads or writes, hashed — equal before and after
  /// means nothing changed (§6.6).
  Future<Map<String, String?>> fingerprint() async {
    const tables = [
      'providers',
      'provider_users',
      'provider_members',
      'provider_services',
      'provider_working_hours',
      'appointments',
      'disputes',
      'reviews',
      'salon_clients',
      'salon_client_notes',
      'provider_audit_log',
      'provider_subscriptions',
      'subscription_notices',
      'favorites',
      'notifications',
      'audit_log',
      'salon_purge_queue',
    ];
    return {
      for (final t in tables)
        t:
            (await pool.execute(
                  'SELECT md5(coalesce(string_agg(x::text, \',\' '
                  'ORDER BY x::text), \'\')) FROM $t x',
                )).first[0]
                as String?,
    };
  }

  test(
    '0046 dropped the members key: a revoked row may outlive its salon',
    () async {
      final keys = await count(
        'SELECT count(*) FROM pg_constraint WHERE conname = '
        "'provider_members_provider_id_fkey'",
      );
      expect(keys, 0);
      await salon('k1');
      await member('k1_m', 'k1', status: 'revoked');
      await sql("DELETE FROM providers WHERE id = 'k1'");
      expect(
        await count("SELECT count(*) FROM provider_members WHERE id = 'k1_m'"),
        1,
      );
    },
  );

  group('test 1 — a due salon is purged', () {
    test('every table empty for it; members and account-bearing invitations '
        'revoked; the others gone; its reasons null; one salon.purge', () async {
      await fullSalon('p1');
      await fullSalon('live');
      await account('owner_live', providerId: 'live');
      await queue('p1', dueClock);
      storage.listable[StorageBucket.public] = {'gallery/p1/old.jpg'};

      final body = await service(SalonPurgeMode.execute).run(now);
      final purged = (body['purged']! as List).single as Map;
      expect(purged['id'], 'p1');
      final counts = purged['counts'] as Map;
      expect(counts, containsPair('providers', 1));
      expect(counts, containsPair('appointments', 2));
      expect(counts, containsPair('membersRevoked', 2));
      expect(counts, containsPair('invitationsDeleted', 1));
      expect(counts, containsPair('notifications', 2));
      expect(counts, containsPair('auditReasonsErased', 4));

      for (final t in [
        'provider_services',
        'provider_working_hours',
        'appointments',
        'reviews',
        'salon_clients',
        'provider_audit_log',
        'provider_subscriptions',
        'subscription_notices',
        'favorites',
      ]) {
        expect(
          await count("SELECT count(*) FROM $t WHERE provider_id = 'p1'"),
          0,
          reason: t,
        );
      }
      expect(await count("SELECT count(*) FROM providers WHERE id = 'p1'"), 0);
      expect(await count("SELECT count(*) FROM disputes WHERE id = 'p1_d'"), 0);
      expect(
        await count(
          "SELECT count(*) FROM salon_client_notes WHERE id = 'p1_n'",
        ),
        0,
      );
      expect(
        await count(
          "SELECT count(*) FROM provider_members WHERE provider_id = 'p1' "
          "AND status = 'revoked' AND id IN ('p1_m1', 'p1_m2')",
        ),
        2,
      );
      expect(
        await count("SELECT count(*) FROM provider_members WHERE id = 'p1_m3'"),
        0,
      );
      expect(
        await count(
          "SELECT count(*) FROM notifications WHERE id LIKE 'p1\\_n%' ESCAPE '\\'",
        ),
        1,
        reason: 'only /pro/appointments, which names no salon, stays',
      );
      expect(
        await count(
          "SELECT count(*) FROM audit_log WHERE target_id LIKE 'p1%' "
          "AND reason IS NOT NULL",
        ),
        0,
      );
      expect(
        await count(
          "SELECT count(*) FROM audit_log WHERE action = 'salon.purge' "
          "AND target_id = 'p1' AND actor_admin_id = 'system:salon-purge' "
          "AND jsonb_typeof(metadata) = 'object' "
          "AND (metadata #>> '{counts,providers}') = '1'",
        ),
        1,
      );
      // The live salon: untouched, its own reasons kept.
      expect(
        await count(
          "SELECT count(*) FROM appointments WHERE provider_id = 'live'",
        ),
        2,
      );
      expect(
        await count(
          "SELECT count(*) FROM audit_log WHERE target_id LIKE 'live%' "
          'AND reason IS NOT NULL',
        ),
        4,
      );
      // The files: the listing, the document, the review photo, the deposit.
      expect(
        storage.deleted,
        unorderedEquals([
          'gallery/p1/old.jpg',
          'gallery/p1/a.jpg',
          'logo/p1/l.jpg',
          'review/u1/p1.jpg',
          'deposit/u1/p1.jpg',
        ]),
      );
      expect(
        await count(
          "SELECT count(*) FROM salon_purge_queue WHERE provider_id = 'p1' "
          'AND rows_purged_at IS NOT NULL',
        ),
        1,
      );
    });
  });

  group('test 2 — the retention, strictly', () {
    test('89 days and exactly 90 days: untouched; 90 days and a minute: '
        'purged', () async {
      for (final (id, days, minutes) in [
        ('d89', 89, 0),
        ('d90', 90, 0),
        ('d90m', 90, 1),
      ]) {
        await salon(id);
        await queue(id, now.subtract(Duration(days: days, minutes: minutes)));
      }
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(
        [for (final p in body['purged']! as List) (p as Map)['id']],
        ['d90m'],
      );
      expect(
        await count(
          "SELECT count(*) FROM providers WHERE id IN ('d89', 'd90')",
        ),
        2,
      );
    });
  });

  group('tests 3–6 — the guards, from the real rows', () {
    test('the candidate SQL excludes an active, a linked, an owned and the '
        'demo salon, all queued and due', () async {
      await salon('g_active', status: 'active');
      await salon('g_linked');
      await account('g_owner', providerId: 'g_linked');
      await salon('g_owned');
      await account('g_owner2');
      await member('g_om', 'g_owned', accountId: 'g_owner2', role: 'owner');
      await salon('g_demo');
      await sql(
        "INSERT INTO demo_snapshot (provider_id, doc, captured_at) "
        "VALUES ('g_demo', '{}', now())",
      );
      for (final id in ['g_active', 'g_linked', 'g_owned', 'g_demo']) {
        await queue(id, dueClock);
      }
      final before = await fingerprint();
      expect(
        await repo.dueCandidates(
          now,
          retention: kSalonPurgeRetention,
          limit: 10,
        ),
        isEmpty,
      );
      expect(await repo.rehearsalCandidates(limit: 10), isEmpty);
      expect(await repo.ownerlessNotQueued(), isEmpty);
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['purged'], isEmpty);
      // Step 0 took the owned and demo rows off the queue; nothing else moved.
      expect(body['unqueued'], 3);
      final after = await fingerprint();
      for (final t in before.keys.where((t) => t != 'salon_purge_queue')) {
        expect(after[t], before[t], reason: t);
      }
    });

    test('the tripwire reads the locked rows right, and its throw commits '
        'nothing', () async {
      await salon('t_active', status: 'active');
      await salon('t_linked');
      await account('t_o', providerId: 't_linked');
      await salon('t_owned');
      await account('t_o2');
      await member('t_m', 't_owned', accountId: 't_o2', role: 'owner');
      await salon('t_demo');
      await sql(
        "INSERT INTO demo_snapshot (provider_id, doc, captured_at) "
        "VALUES ('t_demo', '{}', now())",
      );
      await fullSalon('t_dispute');
      await sql("UPDATE disputes SET status = 'open' WHERE id = 't_dispute_d'");
      final before = await fingerprint();
      final seen = <String, LockedSalon>{};
      for (final id in [
        't_active',
        't_linked',
        't_owned',
        't_demo',
        't_dispute',
      ]) {
        await expectLater(
          repo.purgeOne(
            id,
            commit: true,
            queued: false,
            guard: (s) {
              seen[id] = s;
              throw StateError('tripwire');
            },
            audit: (action: 'salon.purge', actor: 'test'),
          ),
          throwsStateError,
        );
      }
      expect(seen['t_active']!.status, 'active');
      expect(seen['t_linked']!.linked, isTrue);
      expect(seen['t_owned']!.activeOwner, isTrue);
      expect(seen['t_demo']!.demo, isTrue);
      expect(seen['t_dispute']!.openDisputes, 1);
      expect(
        seen['t_dispute']!.linked || seen['t_dispute']!.activeOwner,
        isFalse,
      );
      expect(await fingerprint(), before, reason: 'nothing committed');
    });
  });

  group('test 7 — an open dispute postpones; a booking ahead does not', () {
    test('the dispute waits; the salon with a booking ahead goes', () async {
      await fullSalon('x_dispute');
      await sql("UPDATE disputes SET status = 'open' WHERE id = 'x_dispute_d'");
      await queue('x_dispute', dueClock);
      await fullSalon('x_ahead');
      await queue('x_ahead', dueClock);
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['postponed'], [
        {'id': 'x_dispute', 'reason': 'open_dispute'},
      ]);
      expect(
        [for (final p in body['purged']! as List) (p as Map)['id']],
        ['x_ahead'],
      );
      expect(
        await count("SELECT count(*) FROM providers WHERE id = 'x_dispute'"),
        1,
      );
      expect(
        await count(
          "SELECT count(*) FROM appointments WHERE provider_id = 'x_ahead'",
        ),
        0,
      );
    });
  });

  group(
    'test 8 — the rehearsal writes nothing, and counts what execute does',
    () {
      test('every table and the queue unchanged; the same counts', () async {
        await fullSalon('r1');
        await queue('r1', dueClock);
        await fullSalon('r2');
        storage.listable[StorageBucket.public] = {'gallery/r1/a.jpg'};
        final before = await fingerprint();
        final rehearsal = await service(SalonPurgeMode.rehearse).run(now);
        expect(await fingerprint(), before);
        expect(mail.sent, isEmpty);
        expect(storage.deleted, isEmpty);
        final rehearsed = {
          for (final r in rehearsal['rehearsed']! as List)
            (r as Map)['id']: r['counts'],
        };
        expect(rehearsed.keys, unorderedEquals(['r1', 'r2']));

        final real = await service(SalonPurgeMode.execute).run(now);
        final purged = (real['purged']! as List).single as Map;
        expect(purged['id'], 'r1');
        expect(purged['counts'], rehearsed['r1']);
      });
    },
  );

  group('test 9 — two runs at once purge once', () {
    test('SKIP LOCKED: one purge, one salon.purge row', () async {
      await fullSalon('c1');
      await queue('c1', dueClock);
      final runs = await Future.wait([
        service(SalonPurgeMode.execute).run(now),
        service(SalonPurgeMode.execute).run(now),
      ]);
      final purgedIds = [
        for (final r in runs)
          for (final p in r['purged']! as List) (p as Map)['id'],
      ];
      expect(purgedIds, ['c1']);
      expect(
        await count(
          "SELECT count(*) FROM audit_log WHERE action = 'salon.purge'",
        ),
        1,
      );
    });
  });

  group(
    'test 11 — a revoked member gets « not a member », not a new salon',
    () {
      test('a membership exists, none is active', () async {
        await fullSalon('m1');
        await queue('m1', dueClock);
        await service(SalonPurgeMode.execute).run(now);
        final members = MembershipService(
          PostgresMembershipRepository(pool),
          PostgresProviderAuthRepository(
            pool,
            tokens: TokenService(secret: 'test-secret'),
            echoDevCode: false,
          ),
        );
        // GET /me/provider's two reads (routes/me/provider/index.dart:79-99):
        // a membership exists, so no salon is provisioned; none is active, so
        // the answer is 403 `not_a_member`.
        for (final a in ['acct_m1_m', 'acct_m1_i']) {
          expect(await members.hasAnyMembership(a), isTrue, reason: a);
          expect(await members.activeSalonFor(a), isNull, reason: a);
        }
        expect(
          await PostgresMembershipRepository(pool).listForAccount('acct_m1_m'),
          hasLength(1),
          reason: 'the dangling row reads back; GET /me/salons skips it',
        );
      });
    },
  );

  group('test 14 — a creation\'s ownerless instant', () {
    test(
      'owned since: unqueued the next run; the deletion overwrites the date',
      () async {
        await salon('i1');
        await queue('i1', null);
        await account('i1_owner', providerId: 'i1');
        final body = await service(SalonPurgeMode.execute).run(now);
        expect(body['unqueued'], 1);
        expect(
          await count(
            "SELECT count(*) FROM salon_purge_queue WHERE provider_id = 'i1'",
          ),
          0,
        );

        // A stale row with an old date, then the owner's real deletion.
        await sql(
          "UPDATE provider_users SET provider_id = NULL WHERE id = 'i1_owner'",
        );
        await queue('i1', DateTime.utc(2020));
        await sql(
          "UPDATE salon_purge_queue SET reminder_sent_at = now() WHERE provider_id = 'i1'",
        );
        await repo.stampDeletion('i1', now, startClock: false);
        final row = (await pool.execute(
          "SELECT owner_erased_at, clock_started_at, reminder_sent_at "
          "FROM salon_purge_queue WHERE provider_id = 'i1'",
        )).single;
        expect(
          (row[0]! as DateTime).difference(now).inSeconds.abs(),
          lessThan(2),
        );
        expect(row[1], isNull, reason: 'no clock while rehearsing');
        expect(row[2], isNull);
        await repo.stampDeletion('i1', now, startClock: true);
        expect(
          await count(
            "SELECT count(*) FROM salon_purge_queue WHERE provider_id = 'i1' "
            'AND clock_started_at IS NOT NULL',
          ),
          1,
        );
      },
    );
  });

  group('test 16 — the reminder on the real queue', () {
    test('claimed once, inside 7 days, never for a day already past', () async {
      await salon('e_soon');
      await queue('e_soon', now.subtract(const Duration(days: 84)));
      await salon('e_late');
      await queue('e_late', now.subtract(const Duration(days: 80)));
      await salon('e_past');
      await queue('e_past', now.subtract(const Duration(days: 95)));
      // Due soon, but owned again since: re-checked in the claim itself.
      await salon('e_owned');
      await account('e_owner', providerId: 'e_owned');
      await queue('e_owned', now.subtract(const Duration(days: 84)));
      final first = await repo.claimReminders(
        now,
        retention: kSalonPurgeRetention,
        lead: kSalonPurgeReminderLead,
      );
      expect(first.map((r) => r.providerId), ['e_soon']);
      final again = await repo.claimReminders(
        now,
        retention: kSalonPurgeRetention,
        lead: kSalonPurgeReminderLead,
      );
      expect(again, isEmpty);
    });
  });

  group('test 17 — the next-day pass', () {
    test('a booking written beside the purge goes the night after', () async {
      await fullSalon('n1');
      await queue('n1', dueClock);
      await service(SalonPurgeMode.execute).run(now);
      await booking('n1_late', 'n1');
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['stragglers'], 1);
      expect(
        await count(
          "SELECT count(*) FROM appointments WHERE provider_id = 'n1'",
        ),
        0,
      );
    });
  });

  group('test 13 — a file another salon references stays', () {
    test('kept and reported, never deleted', () async {
      await salon(
        's_purged',
        data: '{"imageUrls":["https://cdn.x/gallery/s_purged/shared.jpg"]}',
      );
      await queue('s_purged', dueClock);
      await salon(
        's_live',
        status: 'active',
        data: '{"imageUrls":["https://cdn.x/gallery/s_purged/shared.jpg"]}',
      );
      await account('s_live_owner', providerId: 's_live');
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['keptShared'], 1);
      expect(storage.deleted, isEmpty);
    });
  });

  group('test 18 — the deleted accounts\' reasons (decision 158)', () {
    test(
      '91 days and gone → null; live, young, or the erase row → kept',
      () async {
        await account('still_here');
        final old = now.subtract(const Duration(days: 91));
        final young = now.subtract(const Duration(days: 89));
        for (final (id, action, target, at) in [
          ('k_old_gone', 'kyc.reject', 'gone', old),
          ('k_old_live', 'kyc.reject', 'still_here', old),
          ('k_young_gone', 'kyc.reject', 'gone', young),
          ('k_erase', 'provider_account.erase', 'gone', old),
        ]) {
          await sql(
            'INSERT INTO audit_log (id, actor_admin_id, action, target_type, '
            "target_id, reason, created_at) VALUES (@id, 'adm', @action, "
            "'provider_account', @t, 'motif', @at)",
            {'id': id, 'action': action, 't': target, 'at': at},
          );
        }
        expect(
          await repo.eraseDeletedAccountReasons(
            now,
            retention: kSalonPurgeRetention,
            apply: false,
          ),
          1,
        );
        expect(
          await count(
            "SELECT count(*) FROM audit_log WHERE reason IS NOT NULL",
          ),
          4,
          reason: 'counted, not applied',
        );
        await repo.eraseDeletedAccountReasons(
          now,
          retention: kSalonPurgeRetention,
          apply: true,
        );
        expect(
          await count(
            "SELECT count(*) FROM audit_log WHERE reason IS NULL AND id = 'k_old_gone'",
          ),
          1,
        );
        expect(
          await count(
            "SELECT count(*) FROM audit_log WHERE reason IS NOT NULL",
          ),
          3,
        );
      },
    );
  });

  group('tests 19 and 24 — the Clients search text (decision 157)', () {
    test('the writer stores an object; 91 days loses `query`, keeps the rest; '
        '89 days keeps it', () async {
      await salon('q1', status: 'active');
      final writer = PostgresProviderAuditLogRepository(pool);
      await writer.log(
        providerId: 'q1',
        actorAccountId: 'acct',
        action: 'clients.list',
        meta: {'query': 'Awa', 'tag': 'vip', 'page': 1},
      );
      expect(
        await count(
          "SELECT count(*) FROM provider_audit_log WHERE jsonb_typeof(meta) = 'object'",
        ),
        1,
        reason: 'test 24: `?` and `-` need an object',
      );
      await sql(
        "INSERT INTO provider_audit_log (id, provider_id, actor_account_id, "
        "action, meta, created_at) VALUES ('young', 'q1', 'a', 'clients.list', "
        "'{\"query\":\"Koffi\"}'::jsonb, @at)",
        {'at': now.subtract(const Duration(days: 89))},
      );
      await sql(
        "UPDATE provider_audit_log SET created_at = @at WHERE id <> 'young'",
        {'at': now.subtract(const Duration(days: 91))},
      );
      final n = await repo.scrubSearchText(
        now,
        retention: kSalonPurgeRetention,
        apply: true,
      );
      expect(n, 1);
      final old =
          (await pool.execute(
                "SELECT meta FROM provider_audit_log WHERE id <> 'young'",
              )).single[0]!
              as Map;
      expect(old, {'tag': 'vip', 'page': 1});
      final kept =
          (await pool.execute(
                "SELECT meta FROM provider_audit_log WHERE id = 'young'",
              )).single[0]!
              as Map;
      expect(kept, {'query': 'Koffi'});
    });
  });

  test('the shared-file rule reads documents stored as JSON strings', () async {
    await salon(
      'doc1',
      data: '{"artists":[{"imageUrl":"https://cdn.x/gallery/doc1/t.jpg"}]}',
    );
    expect(await repo.documentKeysBySalon(), {
      'doc1': {'gallery/doc1/t.jpg'},
    });
  });
}

class _Mail implements EmailProvider {
  final sent = <String>[];

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    sent.add(to);
    return (ok: true, providerMessageId: 'm', error: null);
  }
}

/// Swap the database name in a Postgres URL, keeping host/credentials/query.
String _withDatabase(String url, String db) {
  final u = Uri.parse(url);
  return u.replace(path: '/$db').toString();
}
