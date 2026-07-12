import 'package:flutter/foundation.dart';

/// Per-salon state contract (R6 multi-salons): every ChangeNotifier that
/// caches data for ONE salon implements this so a « Mes salons » switch can
/// clear the fleet in one sweep — a switch happens WITHOUT unmounting the
/// shell, so stale cross-salon data would otherwise linger.
abstract class SalonScoped {
  /// Drop everything loaded for the previous salon (back to the initial
  /// not-yet-loaded state) and notify. Screens re-fetch on entry/rebuild.
  void resetForSalonSwitch();
}

/// The switch coordinator: providers register at construction (main_pro
/// wires them once for the app's lifetime); `ProAuthProvider.switchSalon`
/// calls [resetAll] after the new membership lands.
class ProSalonScope {
  ProSalonScope._();

  static final List<WeakReference<SalonScoped>> _scoped = [];

  /// Register [provider] and return it (a passthrough for MultiProvider
  /// `create:` wiring). Weak: test-created providers never leak.
  static T track<T extends SalonScoped>(T provider) {
    _scoped.add(WeakReference(provider));
    return provider;
  }

  static void resetAll() {
    for (final ref in _scoped) {
      ref.target?.resetForSalonSwitch();
    }
    _scoped.removeWhere((ref) => ref.target == null);
  }

  @visibleForTesting
  static void clear() => _scoped.clear();
}
