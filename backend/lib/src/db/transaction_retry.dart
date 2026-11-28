import 'package:postgres/postgres.dart'
    show ServerException, UniqueViolationException;

/// Runs [run] — one whole transaction, every effect inside it — again when
/// Postgres aborted it for a reason a re-run resolves. Shared by the two
/// sign-in stores (B16.3 for the client accounts, B16.4 for MyWeli Pro):
/// - `40P01`, a deadlock: two transactions locked the same rows in opposite
///   orders (a code's row, then an account; an account, then a code's row).
///   Postgres aborts one of them; re-run, it queues behind the other.
/// - with [raced], a `23505`: the transaction read no holder of an address or
///   a sub, then wrote one, while another committed it first (a concurrent
///   sign-in or sign-up). Re-run, its checks see the winner.
///
/// Each run is rolled back whole, a code's consumption included, so a re-run
/// is the first run against newer data. Three runs at most, then the error.
/// docs/design/account-email-change.md §8.4 · docs/design/auth-store-twins.md
/// §5.1–§5.2.
Future<T> retriedTransaction<T>(
  Future<T> Function() run, {
  bool raced = false,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await run();
    } on ServerException catch (e) {
      final again =
          e.code == '40P01' || (raced && e is UniqueViolationException);
      if (!again || attempt >= 3) rethrow;
    }
  }
}
