import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../maintenance/salon_purge_repository.dart';
import '../storage/storage_service.dart';

/// The salon purge's SQL (B0.24, docs/design/deleted-owner-salon-purge.md
/// §4, §6.2–§6.4). Every per-salon write runs in ONE transaction, which the
/// rehearsal always rolls back (§6.3).
///
/// Proven on real Postgres, in its own database:
/// `test/db/postgres_salon_purge_test.dart`.
class PostgresSalonPurgeRepository implements SalonPurgeRepository {
  PostgresSalonPurgeRepository(this._pool);

  final Pool<void> _pool;
  final _rng = Random.secure();

  /// « Ownerless » (§6.3), for a salon aliased [p]. **Stricter than the
  /// membership repository's owner read**: any active `owner` row counts,
  /// with or without an account — a salon in doubt is treated as owned, so
  /// it is never purged.
  static String _ownerless(String p) =>
      'NOT EXISTS (SELECT 1 FROM provider_users u WHERE u.provider_id = $p.id) '
      'AND NOT EXISTS (SELECT 1 FROM provider_members m '
      "WHERE m.provider_id = $p.id AND m.role = 'owner' "
      "AND m.status = 'active') "
      'AND NOT EXISTS (SELECT 1 FROM demo_snapshot d '
      'WHERE d.provider_id = $p.id)';

  /// A jsonb column the driver may hand back as the JSON **string** some
  /// writers stored (`providers.data` is one in production, 8 of 8 rows on
  /// 2026-11-20) — decoded to an object either way.
  static String _decoded(String col) =>
      "CASE jsonb_typeof($col) WHEN 'string' THEN ($col #>> '{}')::jsonb "
      'ELSE $col END';

  /// The keys a document may reference (§2.4, §4.4): `gallery/…`, `logo/…`
  /// and `review/…` paths inside the stored URLs.
  static final _docKey = RegExp(r'''(?:gallery|logo|review)/[^"'\s?#\\]+''');

  @override
  Future<List<String>> staleQueueRows({required bool apply}) async {
    const stale =
        'q.rows_purged_at IS NULL AND ('
        'NOT EXISTS (SELECT 1 FROM providers p WHERE p.id = q.provider_id) '
        'OR EXISTS (SELECT 1 FROM provider_users u '
        'WHERE u.provider_id = q.provider_id) '
        'OR EXISTS (SELECT 1 FROM provider_members m '
        "WHERE m.provider_id = q.provider_id AND m.role = 'owner' "
        "AND m.status = 'active') "
        'OR EXISTS (SELECT 1 FROM demo_snapshot d '
        'WHERE d.provider_id = q.provider_id))';
    final r = await _pool.execute(
      apply
          ? 'DELETE FROM salon_purge_queue q WHERE $stale '
                'RETURNING q.provider_id'
          : 'SELECT q.provider_id FROM salon_purge_queue q WHERE $stale',
    );
    return [for (final row in r) row[0]! as String]..sort();
  }

  @override
  Future<List<String>> ownerlessNotQueued() async {
    final r = await _pool.execute(
      'SELECT p.id FROM providers p '
      "WHERE p.status <> 'active' AND ${_ownerless('p')} "
      'AND NOT EXISTS (SELECT 1 FROM salon_purge_queue q '
      'WHERE q.provider_id = p.id) ORDER BY p.id',
    );
    return [for (final row in r) row[0]! as String];
  }

  @override
  Future<List<String>> queuedWithoutClock() async {
    final r = await _pool.execute(
      'SELECT q.provider_id FROM salon_purge_queue q '
      'JOIN providers p ON p.id = q.provider_id '
      'WHERE q.rows_purged_at IS NULL AND q.clock_started_at IS NULL '
      "AND p.status <> 'active' AND ${_ownerless('p')} ORDER BY 1",
    );
    return [for (final row in r) row[0]! as String];
  }

  @override
  Future<bool> recordAndStartClock(String providerId, DateTime now) async {
    final r = await _pool.execute(
      Sql.named(
        'INSERT INTO salon_purge_queue '
        '(provider_id, owner_erased_at, clock_started_at) '
        'VALUES (@p, @now, @now) '
        'ON CONFLICT (provider_id) DO UPDATE '
        'SET clock_started_at = EXCLUDED.clock_started_at '
        'WHERE salon_purge_queue.clock_started_at IS NULL '
        'AND salon_purge_queue.rows_purged_at IS NULL '
        'RETURNING provider_id',
      ),
      parameters: {'p': providerId, 'now': now.toUtc()},
    );
    return r.isNotEmpty;
  }

  @override
  Future<List<ClaimedReminder>> claimReminders(
    DateTime now, {
    required Duration retention,
    required Duration lead,
  }) async {
    // Due within [lead] and still ahead: a reminder never announces a day
    // already past. Re-checked ownerless in the same statement (§6.3 step 2).
    final r = await _pool.execute(
      Sql.named(
        'UPDATE salon_purge_queue q SET reminder_sent_at = @now '
        'WHERE q.reminder_sent_at IS NULL AND q.rows_purged_at IS NULL '
        'AND q.clock_started_at IS NOT NULL '
        'AND q.clock_started_at <= @remindFrom '
        'AND q.clock_started_at > @dueBefore '
        'AND EXISTS (SELECT 1 FROM providers p WHERE p.id = q.provider_id '
        "AND p.status <> 'active' AND ${_ownerless('p')}) "
        'RETURNING q.provider_id, q.clock_started_at',
      ),
      parameters: {
        'now': now.toUtc(),
        'remindFrom': now.toUtc().subtract(retention).add(lead),
        'dueBefore': now.toUtc().subtract(retention),
      },
    );
    return [
      for (final row in r)
        (
          providerId: row[0]! as String,
          dueAt: (row[1]! as DateTime).toUtc().add(retention),
        ),
    ]..sort((a, b) => a.providerId.compareTo(b.providerId));
  }

  @override
  Future<List<String>> dueCandidates(
    DateTime now, {
    required Duration retention,
    required int limit,
  }) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT q.provider_id FROM salon_purge_queue q '
        'JOIN providers p ON p.id = q.provider_id '
        'WHERE q.rows_purged_at IS NULL AND q.clock_started_at IS NOT NULL '
        'AND q.clock_started_at < @cutoff '
        "AND p.status <> 'active' AND ${_ownerless('p')} "
        'ORDER BY q.clock_started_at, q.provider_id LIMIT @limit',
      ),
      parameters: {'cutoff': now.toUtc().subtract(retention), 'limit': limit},
    );
    return [for (final row in r) row[0]! as String];
  }

  @override
  Future<List<String>> rehearsalCandidates({required int limit}) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT p.id FROM providers p '
        "WHERE p.status <> 'active' AND ${_ownerless('p')} "
        'ORDER BY p.id LIMIT @limit',
      ),
      parameters: {'limit': limit},
    );
    return [for (final row in r) row[0]! as String];
  }

  @override
  Future<PurgeOutcome> purgeOne(
    String providerId, {
    required bool commit,
    required bool queued,
    required PurgeVerdict Function(LockedSalon) guard,
    required SalonPurgeAudit audit,
  }) async {
    try {
      return await _pool.runTx<PurgeOutcome>((tx) async {
        // A lock that cannot be had in 5 s fails this salon (the run's 500,
        // tried again the next night) rather than holding the cron past its
        // deadline.
        await tx.execute("SET LOCAL lock_timeout = '5s'");
        await tx.execute("SET LOCAL statement_timeout = '30s'");
        final p = {'p': providerId};

        // 4.1 — the queue row first, SKIP LOCKED: a concurrent run (a forced
        // run beside the daily one) skips this salon.
        if (queued) {
          final q = await tx.execute(
            Sql.named(
              'SELECT 1 FROM salon_purge_queue WHERE provider_id = @p '
              'AND rows_purged_at IS NULL FOR UPDATE SKIP LOCKED',
            ),
            parameters: p,
          );
          if (q.isEmpty) return const PurgeSkipped('locked_or_purged');
        }
        final salon = await tx.execute(
          Sql.named(
            'SELECT status, ${_decoded('data')}::text FROM providers '
            'WHERE id = @p FOR UPDATE',
          ),
          parameters: p,
        );
        if (salon.isEmpty) return const PurgeSkipped('gone');
        final status = salon.first[0]! as String;
        final document = salon.first[1] as String? ?? '';

        // 4.2 — what the tripwire reads, under the salon row's lock. The
        // owner rows are read FOR UPDATE too, so none can appear between
        // this read and the revoke.
        final facts = await tx.execute(
          Sql.named(
            'SELECT '
            'EXISTS (SELECT 1 FROM provider_users WHERE provider_id = @p), '
            "(SELECT count(*) FROM (SELECT 1 FROM provider_members WHERE "
            "provider_id = @p AND role = 'owner' AND status = 'active' "
            'FOR UPDATE) o), '
            'EXISTS (SELECT 1 FROM demo_snapshot WHERE provider_id = @p), '
            '(SELECT count(*) FROM disputes d JOIN appointments a '
            "ON a.id = d.appointment_id WHERE a.provider_id = @p "
            "AND d.status = 'open')",
          ),
          parameters: p,
        );
        final f = facts.first;
        final verdict = guard((
          providerId: providerId,
          status: status,
          linked: f[0]! as bool,
          activeOwner: (f[1]! as int) > 0,
          demo: f[2]! as bool,
          openDisputes: f[3]! as int,
        ));
        if (verdict == PurgeVerdict.postpone) {
          return const PurgePostponed('open_dispute');
        }

        // 4.4 — the ids and the keys, before anything goes.
        Future<List<String>> ids(String sql) async => [
          for (final row in await tx.execute(Sql.named(sql), parameters: p))
            row[0]! as String,
        ];
        final appointments = await ids(
          'SELECT id FROM appointments WHERE provider_id = @p',
        );
        final disputes = await ids(
          'SELECT d.id FROM disputes d JOIN appointments a '
          'ON a.id = d.appointment_id WHERE a.provider_id = @p',
        );
        final reviews = await ids(
          'SELECT id FROM reviews WHERE provider_id = @p',
        );
        final reviewPhotos = await ids(
          'SELECT e FROM reviews r, jsonb_array_elements_text('
          "CASE jsonb_typeof(r.photo_urls) WHEN 'string' THEN "
          "(r.photo_urls #>> '{}')::jsonb WHEN 'array' THEN r.photo_urls "
          "ELSE '[]'::jsonb END) AS e WHERE r.provider_id = @p",
        );
        final depositProofs = await ids(
          'SELECT deposit_screenshot_url FROM appointments '
          'WHERE provider_id = @p AND deposit_screenshot_url IS NOT NULL '
          "AND deposit_screenshot_url <> ''",
        );

        // What the cascades will take, counted before the salon goes, so the
        // response and the audit row say it (§6.3 step 4.8).
        final counts = <String, int>{};
        Future<void> count(String name, String sql) async {
          final r = await tx.execute(Sql.named(sql), parameters: p);
          counts[name] = r.first[0]! as int;
        }

        await count(
          'services',
          'SELECT count(*) FROM provider_services WHERE provider_id = @p',
        );
        await count(
          'availability',
          'SELECT count(*) FROM provider_availability WHERE provider_id = @p',
        );
        await count(
          'workingHours',
          'SELECT count(*) FROM provider_working_hours WHERE provider_id = @p',
        );
        await count(
          'breaks',
          'SELECT count(*) FROM provider_breaks WHERE provider_id = @p',
        );
        await count(
          'closedDays',
          'SELECT count(*) FROM provider_blocked_dates WHERE provider_id = @p',
        );
        await count(
          'reviews',
          'SELECT count(*) FROM reviews WHERE provider_id = @p',
        );
        await count(
          'reviewReports',
          'SELECT count(*) FROM review_reports rr JOIN reviews r '
              'ON r.id = rr.review_id WHERE r.provider_id = @p',
        );
        await count(
          'validations',
          'SELECT count(*) FROM salon_validations WHERE provider_id = @p',
        );
        await count(
          'validationEvents',
          'SELECT count(*) FROM salon_validation_events WHERE provider_id = @p',
        );
        await count(
          'placeNotices',
          'SELECT count(*) FROM salon_place_notices WHERE provider_id = @p',
        );
        await count(
          'reminders',
          'SELECT count(*) FROM appointment_reminders ar JOIN appointments a '
              'ON a.id = ar.appointment_id WHERE a.provider_id = @p',
        );
        counts['disputes'] = disputes.length;
        await count(
          'clientNotes',
          'SELECT count(*) FROM salon_client_notes n JOIN salon_clients c '
              'ON c.id = n.client_id WHERE c.provider_id = @p',
        );

        Future<int> run(
          String name,
          String sql, [
          Map<String, Object?>? params,
        ]) async {
          final r = await tx.execute(
            Sql.named(sql),
            parameters: {...p, ...?params},
          );
          return counts[name] = r.affectedRows;
        }

        // 4.5 — MyWeli's written reasons about the salon, its bookings, its
        // disputes and its reviews (decision 158): the rows stay.
        await run(
          'auditReasonsErased',
          'UPDATE audit_log SET reason = NULL WHERE reason IS NOT NULL AND ('
              "(target_type = 'provider' AND target_id = @p) OR "
              "(target_type = 'appointment' AND target_id = ANY(@appts)) OR "
              "(target_type = 'dispute' AND target_id = ANY(@disputes)) OR "
              "(target_type = 'review' AND target_id = ANY(@reviews)))",
          {
            'appts': TypedValue(Type.textArray, appointments),
            'disputes': TypedValue(Type.textArray, disputes),
            'reviews': TypedValue(Type.textArray, reviews),
          },
        );

        // The members' feed rows about this salon: its id is the route's
        // LAST parameter (§2.3). Matched as an exact suffix, never with
        // LIKE: salon ids hold `_`, a LIKE wildcard. Rows with the route
        // `/pro/appointments` name no salon and stay.
        final encoded = Uri.encodeComponent(providerId);
        await run(
          'notifications',
          'DELETE FROM notifications WHERE user_id IN ('
              'SELECT account_id FROM provider_members WHERE provider_id = @p '
              'AND account_id IS NOT NULL) AND route IS NOT NULL AND ('
              'right(route, length(@s1)) = @s1 OR '
              'right(route, length(@s2)) = @s2 OR '
              'right(route, length(@s3)) = @s3 OR '
              'right(route, length(@s4)) = @s4)',
          {
            's1': '?salon=$providerId',
            's2': '&salon=$providerId',
            's3': '?salon=$encoded',
            's4': '&salon=$encoded',
          },
        );

        // 4.6 — REVOKED, not deleted: a member left with no row at all would
        // get a new empty salon from GET /me/provider's self-heal (§4.2).
        // Invitations that carry an account are revoked for the same reason;
        // those to an address with no account are a third party's address,
        // and go.
        await run(
          'membersRevoked',
          "UPDATE provider_members SET status = 'revoked', revoked_at = now() "
              "WHERE provider_id = @p AND (status = 'active' OR "
              "(status = 'invited' AND account_id IS NOT NULL))",
        );
        await run(
          'invitationsDeleted',
          'DELETE FROM provider_members WHERE provider_id = @p '
              "AND status = 'invited' AND account_id IS NULL",
        );

        // 4.7 — the rows, the salon last (its cascades take the catalogue,
        // hours, breaks, closed days, reviews and their reports, the
        // validation, its history and the place notice).
        await run(
          'appointments',
          'DELETE FROM appointments WHERE provider_id = @p',
        );
        await run(
          'salonClients',
          'DELETE FROM salon_clients WHERE provider_id = @p',
        );
        await run(
          'teamLog',
          'DELETE FROM provider_audit_log WHERE provider_id = @p',
        );
        await run(
          'subscriptionNotices',
          'DELETE FROM subscription_notices WHERE provider_id = @p',
        );
        await run(
          'subscriptions',
          'DELETE FROM provider_subscriptions WHERE provider_id = @p',
        );
        await run('favorites', 'DELETE FROM favorites WHERE provider_id = @p');
        await run('providers', 'DELETE FROM providers WHERE id = @p');

        // 4.8 — once per salon, inside the transaction. `metadata` holds
        // numbers only, as an OBJECT (the admin reader takes either form).
        await tx.execute(
          Sql.named(
            'INSERT INTO audit_log (id, actor_admin_id, action, target_type, '
            'target_id, reason, metadata) VALUES (@id, @actor, @action, '
            "'provider', @p, NULL, @meta:jsonb)",
          ),
          parameters: {
            ...p,
            'id': _auditId(),
            'actor': audit.actor,
            'action': audit.action,
            'meta': {'counts': Map<String, int>.of(counts)},
          },
        );

        final objects = <PurgeObject>[
          for (final key in {..._docKey.allMatches(document).map((m) => m[0]!)})
            (bucket: StorageBucket.public, key: key),
          for (final raw in reviewPhotos)
            if (keyOf(raw).startsWith('review/'))
              (bucket: StorageBucket.public, key: keyOf(raw)),
          for (final raw in depositProofs)
            if (keyOf(raw).startsWith('deposit/'))
              (bucket: StorageBucket.deposit, key: keyOf(raw)),
        ];

        // 4.9 — the queue row knows the rows are gone and what is left.
        if (queued) {
          await tx.execute(
            Sql.named(
              'UPDATE salon_purge_queue SET rows_purged_at = now(), '
              'pending_objects = @objs:jsonb WHERE provider_id = @p',
            ),
            parameters: {...p, 'objs': _encodeObjects(objects)},
          );
        }

        final done = PurgeDone(Map.unmodifiable(counts), objects);
        // The rehearsal: every statement ran; nothing is kept.
        if (!commit) throw _Rollback(done);
        return done;
      });
    } on _Rollback catch (r) {
      return r.outcome;
    }
  }

  @override
  Future<List<PurgedRow>> purgedRows() async {
    final r = await _pool.execute(
      'SELECT provider_id, rows_purged_at, pending_objects '
      'FROM salon_purge_queue WHERE rows_purged_at IS NOT NULL '
      'ORDER BY provider_id',
    );
    return [
      for (final row in r)
        (
          providerId: row[0]! as String,
          rowsPurgedAt: (row[1]! as DateTime).toUtc(),
          pendingObjects: _decodeObjects(row[2]),
        ),
    ];
  }

  @override
  Future<void> setPendingObjects(
    String providerId,
    List<PurgeObject> left,
  ) async {
    await _pool.execute(
      Sql.named(
        'UPDATE salon_purge_queue SET pending_objects = @objs:jsonb '
        'WHERE provider_id = @p',
      ),
      parameters: {'p': providerId, 'objs': _encodeObjects(left)},
    );
  }

  @override
  Future<Map<String, Set<String>>> documentKeysBySalon() async {
    final r = await _pool.execute(
      'SELECT id, ${_decoded('data')}::text FROM providers',
    );
    return {
      for (final row in r)
        row[0]! as String: {
          for (final m in _docKey.allMatches(row[1] as String? ?? '')) m[0]!,
        },
    };
  }

  @override
  Future<int> sweepStragglers(String providerId, {required bool apply}) async {
    // Step 4.7's tables, read (and deleted when [apply]) for an id whose
    // salon is already gone: a booking or a client card written beside the
    // purge took no lock on the salon row (§6.3 step 6).
    const tables = [
      'appointments',
      'salon_clients',
      'provider_audit_log',
      'subscription_notices',
      'provider_subscriptions',
      'favorites',
    ];
    var found = 0;
    for (final t in tables) {
      final r = await _pool.execute(
        Sql.named(
          apply
              ? 'DELETE FROM $t WHERE provider_id = @p'
              : 'SELECT 1 FROM $t WHERE provider_id = @p',
        ),
        parameters: {'p': providerId},
      );
      found += apply ? r.affectedRows : r.length;
    }
    final invited = await _pool.execute(
      Sql.named(
        apply
            ? 'DELETE FROM provider_members WHERE provider_id = @p '
                  "AND status = 'invited' AND account_id IS NULL"
            : 'SELECT 1 FROM provider_members WHERE provider_id = @p '
                  "AND status = 'invited' AND account_id IS NULL",
      ),
      parameters: {'p': providerId},
    );
    return found + (apply ? invited.affectedRows : invited.length);
  }

  @override
  Future<void> dequeue(String providerId) async {
    await _pool.execute(
      Sql.named(
        'DELETE FROM salon_purge_queue WHERE provider_id = @p '
        'AND rows_purged_at IS NOT NULL',
      ),
      parameters: {'p': providerId},
    );
  }

  @override
  Future<int> eraseDeletedAccountReasons(
    DateTime now, {
    required Duration retention,
    required bool apply,
  }) async {
    const where =
        "target_type = 'provider_account' "
        "AND action <> 'provider_account.erase' "
        'AND reason IS NOT NULL AND created_at < @cutoff '
        'AND NOT EXISTS (SELECT 1 FROM provider_users u '
        'WHERE u.id = audit_log.target_id)';
    final r = await _pool.execute(
      Sql.named(
        apply
            ? 'UPDATE audit_log SET reason = NULL WHERE $where'
            : 'SELECT 1 FROM audit_log WHERE $where',
      ),
      parameters: {'cutoff': now.toUtc().subtract(retention)},
    );
    return apply ? r.affectedRows : r.length;
  }

  @override
  Future<int> scrubSearchText(
    DateTime now, {
    required Duration retention,
    required bool apply,
  }) async {
    // `meta ? 'query'` matches the partial index of 0046. It reads nothing
    // on a row stored as a JSON string; the writer stores objects (106 of
    // 106 rows on 2026-11-20), and a test pins it.
    const where =
        "action = 'clients.list' AND meta ? 'query' AND created_at < @cutoff";
    final r = await _pool.execute(
      Sql.named(
        apply
            ? "UPDATE provider_audit_log SET meta = meta - 'query' WHERE $where"
            : 'SELECT 1 FROM provider_audit_log WHERE $where',
      ),
      parameters: {'cutoff': now.toUtc().subtract(retention)},
    );
    return apply ? r.affectedRows : r.length;
  }

  @override
  Future<void> stampDeletion(
    String providerId,
    DateTime now, {
    required bool startClock,
  }) async {
    // The deletion is the authoritative event: it OVERWRITES a row left by
    // a creation's ownerless instant (§2.5, §6.2), so no stale date stays.
    // A row already purged is never touched.
    await _pool.execute(
      Sql.named(
        'INSERT INTO salon_purge_queue '
        '(provider_id, owner_erased_at, clock_started_at) '
        'VALUES (@p, @now, @clock:timestamptz) '
        'ON CONFLICT (provider_id) DO UPDATE SET '
        'owner_erased_at = EXCLUDED.owner_erased_at, '
        'clock_started_at = EXCLUDED.clock_started_at, '
        'reminder_sent_at = NULL '
        'WHERE salon_purge_queue.rows_purged_at IS NULL',
      ),
      parameters: {
        'p': providerId,
        'now': now.toUtc(),
        'clock': startClock ? now.toUtc() : null,
      },
    );
  }

  String _auditId() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return 'audit_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  /// `https://cdn…/review/u1/x.jpg` → `review/u1/x.jpg`; a bare key is
  /// returned unchanged; a query or fragment is dropped. As
  /// `UserErasureService._keyOf`, plus the query.
  static String keyOf(String raw) {
    var s = raw.trim();
    final i = s.indexOf('://');
    if (i >= 0) {
      final slash = s.indexOf('/', i + 3);
      s = slash < 0 ? '' : s.substring(slash + 1);
    }
    final cut = s.indexOf(RegExp('[?#]'));
    return cut < 0 ? s : s.substring(0, cut);
  }

  static List<Map<String, String>> _encodeObjects(List<PurgeObject> objs) => [
    for (final o in objs) {'bucket': o.bucket.name, 'key': o.key},
  ];

  static List<PurgeObject> _decodeObjects(Object? raw) {
    final v = raw is String ? jsonDecode(raw) : raw;
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map &&
            e['key'] is String &&
            StorageBucket.values.any((b) => b.name == e['bucket']))
          (
            bucket: StorageBucket.values.byName(e['bucket'] as String),
            key: e['key'] as String,
          ),
    ];
  }
}

/// Carries a rehearsal's outcome out of the transaction it rolls back.
final class _Rollback implements Exception {
  const _Rollback(this.outcome);
  final PurgeOutcome outcome;
}
