import 'package:postgres/postgres.dart';

import '../auth/auth_repository.dart';

/// The refresh-token exchange, written ONCE for the three principals' tables —
/// `refresh_tokens`, `provider_refresh_tokens`, `admin_refresh_tokens`.
/// Design: docs/design/backend-refresh-rotation-atomic.md §5.
///
/// **What it replaced.** Each repository read `rotated` with a lock-free
/// `SELECT`, then in a separate statement ran `UPDATE … SET rotated = true`
/// with no `AND rotated = false` and the row count ignored — so two concurrent
/// exchanges of one token BOTH succeeded and forked the family, which
/// production shows on cold starts (two `/auth/refresh` 200s 6 ms apart).
/// Admin had no transaction at all. And a sequential second use, arriving just
/// after the first committed, revoked the family — signing out clients that
/// raced slightly more slowly.
///
/// **[session] is the caller's transaction** — typed [TxSession], so passing
/// the pool does not compile. The claim, the child insert and the family revoke
/// commit or roll back together; [issueChild] must write through that same
/// transaction, or a child can outlive a rolled-back claim.
///
/// [table] and [ownerColumns] are code constants, never input.
Future<RefreshResult> exchangeRefreshToken(
  TxSession session, {
  required String table,
  required String ownerColumns,
  required String tokenHash,
  required Future<TokenPair> Function(Map<String, dynamic> row) issueChild,
}) async {
  // 1 — The claim. Under READ COMMITTED a concurrent second UPDATE blocks on
  // the winner's row lock, re-evaluates `rotated = false` against the row the
  // winner committed, and matches nothing. Exactly one caller gets this row.
  final claimed = await session.execute(
    Sql.named(
      'UPDATE $table SET rotated = true, rotated_at = now() '
      'WHERE token_hash = @h AND rotated = false '
      'RETURNING $ownerColumns, family_id',
    ),
    parameters: {'h': tokenHash},
  );
  if (claimed.isNotEmpty) {
    return refreshRotated(await issueChild(claimed.first.toColumnMap()));
  }

  // 2 — Already rotated, or unknown. `FOR UPDATE`, so a family revoke that has
  // ALREADY locked this row finishes first: the deleted row is then simply not
  // returned and no sibling is minted. The other order — this lock taken
  // first, the revoke arriving while the sibling is being minted — is closed
  // by step 4's repeated DELETE, not here.
  //
  // The grace is compared on the DATABASE clock on both sides — `rotated_at`
  // was written by `now()` in step 1 — so no instance's clock is involved. A
  // NULL `rotated_at` (rotated before migration 0037) is outside the grace.
  final seen = await session.execute(
    Sql.named(
      'SELECT $ownerColumns, family_id, '
      'COALESCE(rotated_at >= now() - @grace:interval, false) AS in_grace '
      'FROM $table WHERE token_hash = @h FOR UPDATE',
    ),
    parameters: {'h': tokenHash, 'grace': kRefreshReuseGrace},
  );
  if (seen.isEmpty) return refreshInvalid;
  final row = seen.first.toColumnMap();

  // 3 — Inside the grace: a concurrent or retried legitimate use. A sibling in
  // the same family; nothing revoked, the parent not rotated a second time.
  if (row['in_grace'] as bool) return refreshGrace(await issueChild(row));

  // 4 — Past the grace: reuse. Revoke the whole family (stolen-token
  // containment, BACKEND.md §3.1).
  //
  // **Repeated until it deletes nothing.** One DELETE sees the family as of
  // its own snapshot. An exchange that locked a row of this family before the
  // DELETE reached it — a grace sibling (step 3) or a plain rotation (step 1)
  // — makes the DELETE wait, then commits its child, which that snapshot does
  // not contain: the child would outlive the revoke. Under READ COMMITTED each
  // statement takes a fresh snapshot, so the next DELETE sees it. An exchange
  // arriving after a row is deleted blocks on that row until this commits,
  // then finds it gone and mints nothing. Without contention: two statements.
  // A further pass happens only because another exchange COMMITTED a child of
  // this family meanwhile, so the loop ends once none is in flight.
  int deleted;
  do {
    deleted = (await session.execute(
      Sql.named('DELETE FROM $table WHERE family_id = @f'),
      parameters: {'f': row['family_id']},
    )).affectedRows;
  } while (deleted > 0);
  return refreshReused;
}
