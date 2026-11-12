import 'package:postgres/postgres.dart';

import '../validation/salon_validation_repository.dart';

/// Postgres salon validations (migration 0044 —
/// docs/design/salon-go-live-approval.md §2, §3). Parameterized queries
/// throughout; the only text spliced into SQL is fixed fragments chosen in
/// Dart (an ORDER BY, the final refusal codes from a `const` set).
///
/// **Single winner by the database.** Every transition is a compare-and-set
/// whose WHERE carries the state the caller expects, and every write that
/// has an event writes it in the same transaction. Two calls racing on one
/// salon serialise on the row lock; the second re-reads the row it waited
/// for, its WHERE no longer matches, and it writes nothing.
class PostgresSalonValidationRepository implements SalonValidationRepository {
  PostgresSalonValidationRepository(this._pool);

  final Pool<void> _pool;

  /// `'outside_ci', 'test_salon'` — from [kFinalRefusalCodes], so the SQL and
  /// the Dart rule cannot drift. Each code is a lowercase identifier (checked
  /// here), so quoting it is all the escaping it needs.
  static final String _finalCodesSql = () {
    for (final c in kFinalRefusalCodes) {
      if (!RegExp(r'^[a-z_]+$').hasMatch(c)) {
        throw StateError('refusal code $c is not a plain identifier');
      }
    }
    return kFinalRefusalCodes.map((c) => "'$c'").join(', ');
  }();

  @override
  Future<SalonValidation?> get(String providerId) async {
    final r = await _pool.execute(
      Sql.named('SELECT * FROM salon_validations WHERE provider_id = @p'),
      parameters: {'p': providerId},
    );
    return r.isEmpty ? null : _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Map<String, SalonValidation>> getMany(
    Iterable<String> providerIds,
  ) async {
    final ids = providerIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final r = await _pool.execute(
      Sql.named(
        'SELECT * FROM salon_validations WHERE provider_id = ANY(@ids)',
      ),
      parameters: {'ids': ids},
    );
    return {
      for (final row in r)
        row.toColumnMap()['provider_id'] as String: _fromRow(row.toColumnMap()),
    };
  }

  @override
  Future<SubmitOutcome> submit(String providerId, DateTime at) async {
    final recorded = await _pool.runTx<SalonValidation?>((tx) async {
      // §3.1's two upserts in one statement. No row: the INSERT. A row:
      // `DO UPDATE` only `WHERE state = 'refused'` with a code that is not
      // final — the request asked again; for any other row the WHERE is
      // false and nothing is written, which is the first upsert's
      // `DO NOTHING`. Either way RETURNING yields a row only when THIS
      // statement recorded a request, so a double tap records once.
      final r = await tx.execute(
        Sql.named(
          'INSERT INTO salon_validations '
          '(provider_id, state, submitted_at) '
          "VALUES (@p, 'pending', @at) "
          'ON CONFLICT (provider_id) DO UPDATE SET '
          "state = 'pending', submitted_at = EXCLUDED.submitted_at, "
          'decided_at = NULL, decided_by = NULL, '
          'refusal_code = NULL, refusal_note = NULL '
          "WHERE salon_validations.state = 'refused' "
          'AND (salon_validations.refusal_code IS NULL '
          'OR salon_validations.refusal_code NOT IN ($_finalCodesSql)) '
          'RETURNING *',
        ),
        parameters: {'p': providerId, 'at': at.toUtc()},
      );
      if (r.isEmpty) return null;
      await _insertEvent(
        tx,
        providerId,
        ValidationEventKinds.submitted,
        at.toUtc(),
      );
      return _fromRow(r.first.toColumnMap());
    });
    if (recorded != null) return (recorded: true, validation: recorded);
    // Nothing recorded: answer from the row as it stands now.
    return (recorded: false, validation: await get(providerId));
  }

  @override
  Future<SalonValidation?> decide(
    String providerId, {
    required String from,
    required String to,
    required String adminId,
    String? code,
    String? note,
    DateTime? at,
  }) async {
    checkDecision(from: from, to: to, code: code, note: note);
    final when = (at ?? DateTime.now()).toUtc();
    final refused = to == ValidationStates.refused;
    return _pool.runTx<SalonValidation?>((tx) async {
      final r = await tx.execute(
        Sql.named(
          'UPDATE salon_validations SET state = @to, decided_at = @at, '
          'decided_by = @admin, refusal_code = @code:text, '
          'refusal_note = @note:text '
          'WHERE provider_id = @p AND state = @from RETURNING *',
        ),
        parameters: {
          'p': providerId,
          'from': from,
          'to': to,
          'at': when,
          'admin': adminId,
          // Approving clears the refusal from the state row (the history
          // keeps it): NULL for both.
          'code': refused ? code : null,
          'note': refused ? note : null,
        },
      );
      if (r.isEmpty) return null;
      await _insertEvent(
        tx,
        providerId,
        to,
        when,
        byAdmin: adminId,
        code: refused ? code : null,
        note: refused ? note : null,
      );
      return _fromRow(r.first.toColumnMap());
    });
  }

  @override
  Future<GoLiveOutcome> goLive(String providerId, {DateTime? at}) async {
    final when = (at ?? DateTime.now()).toUtc();
    return _pool.runTx<GoLiveOutcome>((tx) async {
      // 1. The single-winner step: only one call ever sets it.
      final v = await tx.execute(
        Sql.named(
          'UPDATE salon_validations SET went_live_at = @at '
          "WHERE provider_id = @p AND state = 'approved' "
          'AND went_live_at IS NULL RETURNING provider_id',
        ),
        parameters: {'p': providerId, 'at': when},
      );
      if (v.isEmpty) {
        // Nothing written yet; say why.
        final row = await tx.execute(
          Sql.named(
            'SELECT state FROM salon_validations WHERE provider_id = @p',
          ),
          parameters: {'p': providerId},
        );
        return row.isEmpty ||
                row.first.toColumnMap()['state'] != ValidationStates.approved
            ? GoLiveOutcome.notApproved
            : GoLiveOutcome.alreadyLive;
      }
      // 2. Public only from `draft`: a salon suspended since the checks
      //    stays suspended, and step 1 is rolled back.
      final p = await tx.execute(
        Sql.named(
          "UPDATE providers SET status = 'active' "
          "WHERE id = @p AND status = 'draft' RETURNING id",
        ),
        parameters: {'p': providerId},
      );
      if (p.isEmpty) {
        final s = await tx.execute(
          Sql.named('SELECT status FROM providers WHERE id = @p'),
          parameters: {'p': providerId},
        );
        final suspended =
            s.isNotEmpty && s.first.toColumnMap()['status'] == 'suspended';
        return _rollBack(
          tx,
          suspended ? GoLiveOutcome.suspended : GoLiveOutcome.notDraft,
        );
      }
      // 3. Someone can run it. FOR SHARE: an erasure deleting this row waits
      //    for the commit instead of slipping between the check and it.
      final owner = await tx.execute(
        Sql.named(
          'SELECT 1 FROM provider_members '
          "WHERE provider_id = @p AND role = 'owner' AND status = 'active' "
          'AND account_id IS NOT NULL LIMIT 1 FOR SHARE',
        ),
        parameters: {'p': providerId},
      );
      if (owner.isEmpty) return _rollBack(tx, GoLiveOutcome.noOwner);
      return GoLiveOutcome.live;
    });
  }

  /// Rolls [tx] back — both writes of [goLive] or neither — and answers
  /// [outcome]. An explicit ROLLBACK rather than a thrown exception: `runTx`
  /// then neither commits nor rethrows, and the pool keeps the connection,
  /// which it discards after any exception.
  static Future<GoLiveOutcome> _rollBack(
    TxSession tx,
    GoLiveOutcome outcome,
  ) async {
    await tx.rollback();
    return outcome;
  }

  @override
  Future<({List<SalonValidation> items, int total})> queue(
    String state, {
    int page = 1,
    int pageSize = 50,
  }) async {
    checkQueueArgs(state, page, pageSize);
    final pending = state == ValidationStates.pending;
    final where = _queueWhere(pending: pending);
    final count = await _pool.execute(
      Sql.named('SELECT count(*)::int AS n $where'),
      parameters: {'state': state},
    );
    final rows = await _pool.execute(
      Sql.named(
        'SELECT v.* $where ORDER BY '
        '${pending ? 'v.submitted_at ASC' : 'v.decided_at DESC'} NULLS LAST, '
        'v.provider_id ASC LIMIT @ps OFFSET @off',
      ),
      parameters: {
        'state': state,
        'ps': pageSize,
        'off': (page - 1) * pageSize,
      },
    );
    return (
      items: [for (final r in rows) _fromRow(r.toColumnMap())],
      total: count.first.toColumnMap()['n'] as int,
    );
  }

  @override
  Future<int> countPending() async {
    final r = await _pool.execute(
      Sql.named('SELECT count(*)::int AS n ${_queueWhere(pending: true)}'),
      parameters: {'state': ValidationStates.pending},
    );
    return r.first.toColumnMap()['n'] as int;
  }

  /// The queue's definition, shared by [queue] and [countPending]: one
  /// state, and for `pending` no suspended salon (§3.5).
  static String _queueWhere({required bool pending}) =>
      'FROM salon_validations v JOIN providers p ON p.id = v.provider_id '
      'WHERE v.state = @state'
      "${pending ? " AND p.status <> 'suspended'" : ''}";

  @override
  Future<List<SalonValidationEvent>> events(String providerId) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT * FROM salon_validation_events WHERE provider_id = @p '
        'ORDER BY occurred_at, id',
      ),
      parameters: {'p': providerId},
    );
    return [
      for (final row in r)
        () {
          final m = row.toColumnMap();
          return SalonValidationEvent(
            id: m['id'] as int,
            providerId: m['provider_id'] as String,
            kind: m['kind'] as String,
            at: (m['occurred_at'] as DateTime).toUtc(),
            byAdmin: m['by_admin'] as String?,
            refusalCode: m['refusal_code'] as String?,
            refusalNote: m['refusal_note'] as String?,
          );
        }(),
    ];
  }

  @override
  Future<bool> deletePending(String providerId) async {
    final r = await _pool.execute(
      Sql.named(
        'DELETE FROM salon_validations '
        "WHERE provider_id = @p AND state = 'pending'",
      ),
      parameters: {'p': providerId},
    );
    return r.affectedRows > 0;
  }

  @override
  Future<void> clearNotes(String providerId) async {
    await _pool.runTx<void>((tx) async {
      await tx.execute(
        Sql.named(
          'UPDATE salon_validations SET refusal_note = NULL '
          'WHERE provider_id = @p AND refusal_note IS NOT NULL',
        ),
        parameters: {'p': providerId},
      );
      await tx.execute(
        Sql.named(
          'UPDATE salon_validation_events SET refusal_note = NULL '
          'WHERE provider_id = @p AND refusal_note IS NOT NULL',
        ),
        parameters: {'p': providerId},
      );
    });
  }

  Future<void> _insertEvent(
    TxSession tx,
    String providerId,
    String kind,
    DateTime at, {
    String? byAdmin,
    String? code,
    String? note,
  }) => tx.execute(
    Sql.named(
      'INSERT INTO salon_validation_events '
      '(provider_id, kind, occurred_at, by_admin, refusal_code, refusal_note) '
      'VALUES (@p, @kind, @at, @by:text, @code:text, @note:text)',
    ),
    parameters: {
      'p': providerId,
      'kind': kind,
      'at': at,
      'by': byAdmin,
      'code': code,
      'note': note,
    },
  );

  SalonValidation _fromRow(Map<String, dynamic> r) => SalonValidation(
    providerId: r['provider_id'] as String,
    state: r['state'] as String,
    submittedAt: (r['submitted_at'] as DateTime?)?.toUtc(),
    decidedAt: (r['decided_at'] as DateTime?)?.toUtc(),
    decidedBy: r['decided_by'] as String?,
    refusalCode: r['refusal_code'] as String?,
    refusalNote: r['refusal_note'] as String?,
    wentLiveAt: (r['went_live_at'] as DateTime?)?.toUtc(),
  );
}
