/// The kept answers of the creating POSTs (docs/design/write-idempotency.md
/// §3): a write whose answer was lost on the way back is asked again with the
/// same `Idempotency-Key`, and the server REPLAYS what it answered instead of
/// creating a second booking, note or invitation — or answering 409 to the
/// person's own booking.
///
/// The in-memory twin is here; the Postgres one is
/// `db/postgres_idempotency_store.dart` (table `idempotency_keys`, migration
/// `0040`). Both run `test/idempotency/idempotency_contract.dart`.
library;

/// How long an answer is kept, and replayed. A lost answer is asked again
/// within seconds (the clients re-ask at once); a day covers a phone that
/// went offline mid-booking and retries the same screen the next morning.
const Duration kIdempotencyWindow = Duration(hours: 24);

/// How long a claim may stay « in progress » before it is taken to be
/// abandoned — the instance died between the claim and the answer.
///
/// Cloud Run kills a request after 300 s, so no request can still be running
/// past this: a claim older than it will never be completed, and keeping it
/// would answer `request_in_progress` to every retry for a whole day.
/// Reclaiming it costs at most what the server did before keys existed.
const Duration kIdempotencyAbandonedAfter = Duration(minutes: 5);

/// What [IdempotencyStore.claim] found.
sealed class IdempotencyClaim {
  const IdempotencyClaim();
}

/// The key is now this request's: run the write, then [IdempotencyStore.
/// complete] or [IdempotencyStore.release].
final class ClaimReserved extends IdempotencyClaim {
  const ClaimReserved();
}

/// The write was done for this key: answer [status] and [body] again.
final class ClaimReplay extends IdempotencyClaim {
  const ClaimReplay({required this.status, required this.body});
  final int status;
  final String body;
}

/// The same request is still running (sent twice at once).
final class ClaimInProgress extends IdempotencyClaim {
  const ClaimInProgress();
}

/// The key was used for ANOTHER body — a client bug, never a retry.
final class ClaimMismatch extends IdempotencyClaim {
  const ClaimMismatch();
}

/// One row per (account, route, key). The account is the session's `sub` and
/// the route the exact path with its ids: two accounts can never replay each
/// other's answers, whatever key they send.
abstract interface class IdempotencyStore {
  /// Reserves the key, or says what is already there. A row past
  /// [kIdempotencyWindow], or an in-progress one past
  /// [kIdempotencyAbandonedAfter], counts as absent.
  Future<IdempotencyClaim> claim({
    required String accountId,
    required String route,
    required String key,
    required String fingerprint,
  });

  /// Keeps the answer of a write that succeeded.
  Future<void> complete({
    required String accountId,
    required String route,
    required String key,
    required int status,
    required String body,
  });

  /// Frees the key of a write that was refused or failed: a new try starts
  /// afresh. A completed key is never released.
  Future<void> release({
    required String accountId,
    required String route,
    required String key,
  });

  /// Deletes every row older than [olderThan]; returns how many went.
  Future<int> prune(Duration olderThan);

  /// The account's erasure (L1): its kept answers go with it.
  Future<void> deleteForAccount(String accountId);
}

class _Entry {
  _Entry(this.fingerprint, this.createdAt);
  final String fingerprint;
  final DateTime createdAt;
  int? status;
  String? body;
}

/// Dev and CI. Per process — on a `maxScale: 4` service it would replay only
/// on the instance that answered first, which is why production is Postgres.
class InMemoryIdempotencyStore implements IdempotencyStore {
  InMemoryIdempotencyStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _rows = <String, _Entry>{};

  static String _id(String accountId, String route, String key) =>
      '$accountId\u0000$route\u0000$key';

  @override
  Future<IdempotencyClaim> claim({
    required String accountId,
    required String route,
    required String key,
    required String fingerprint,
  }) async {
    final id = _id(accountId, route, key);
    final now = _now();
    final row = _rows[id];
    final age = row == null ? null : now.difference(row.createdAt);
    final absent =
        row == null ||
        age! >= kIdempotencyWindow ||
        (row.status == null && age >= kIdempotencyAbandonedAfter);
    if (absent) {
      _rows[id] = _Entry(fingerprint, now);
      return const ClaimReserved();
    }
    if (row.fingerprint != fingerprint) return const ClaimMismatch();
    final status = row.status;
    if (status == null) return const ClaimInProgress();
    return ClaimReplay(status: status, body: row.body!);
  }

  @override
  Future<void> complete({
    required String accountId,
    required String route,
    required String key,
    required int status,
    required String body,
  }) async {
    final row = _rows[_id(accountId, route, key)];
    if (row == null || row.status != null) return;
    row
      ..status = status
      ..body = body;
  }

  @override
  Future<void> release({
    required String accountId,
    required String route,
    required String key,
  }) async {
    final id = _id(accountId, route, key);
    if (_rows[id]?.status == null) _rows.remove(id);
  }

  @override
  Future<int> prune(Duration olderThan) async {
    final cutoff = _now().subtract(olderThan);
    final before = _rows.length;
    _rows.removeWhere((_, r) => r.createdAt.isBefore(cutoff));
    return before - _rows.length;
  }

  @override
  Future<void> deleteForAccount(String accountId) async {
    _rows.removeWhere((id, _) => id.startsWith('$accountId\u0000'));
  }
}
