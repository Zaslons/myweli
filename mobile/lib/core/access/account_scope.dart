import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

/// Account-scoped state contract (B9.13 — docs/design/consumer-account-scope.md):
/// every consumer store that holds data of the SIGNED-IN ACCOUNT implements
/// this, so a change of account clears the fleet in one sweep.
///
/// The stores are created once, above `MaterialApp.router` (`main.dart`), and
/// live for the whole app — so nothing else would ever forget account A when
/// account B signs in on the same phone. The twin of `SalonScoped`
/// (pro_salon_scope.dart), one level up.
abstract class AccountScoped {
  /// Forget everything of the previous account — back to the not-yet-asked
  /// state — and notify.
  ///
  /// It also moves the store's account number: a read or a write sent before
  /// this call writes nothing when it answers after it (§2.3) — not its data,
  /// not its error, not `isLoading`, which may be the next account's.
  void resetForAccountChange();
}

/// The coordinator: the stores register at construction (`main.dart` wires
/// them once for the app's lifetime); `AuthProvider` calls [resetAll]
/// whenever the signed-in account changes — and nothing else does.
class AccountScope {
  AccountScope._();

  static final List<WeakReference<AccountScoped>> _scoped = [];

  /// Register [store] and return it (a passthrough for MultiProvider
  /// `create:` wiring). Weak: test-created stores never leak.
  static T track<T extends AccountScoped>(T store) {
    _scoped.add(WeakReference(store));
    return store;
  }

  /// Reset every tracked store.
  ///
  /// **A store that throws is logged and skipped, never propagated.** A way
  /// out of an account that stopped at the third store would leave the ones
  /// after it to the previous account — and an exception escaping into
  /// `AuthProvider.logout` would report a sign-out that happened as failed.
  static void resetAll() {
    // A copy: a store reacting to its reset must not change the list walked.
    for (final ref in List.of(_scoped)) {
      final store = ref.target;
      if (store == null) continue;
      try {
        store.resetForAccountChange();
      } catch (error, stackTrace) {
        AppLogger.error(
          'AccountScope.resetAll: ${store.runtimeType} threw',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    _scoped.removeWhere((ref) => ref.target == null);
  }

  @visibleForTesting
  static bool isTracked(Object store) =>
      _scoped.any((ref) => identical(ref.target, store));

  @visibleForTesting
  static void clear() => _scoped.clear();
}
