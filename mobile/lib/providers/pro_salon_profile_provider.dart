import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/provider.dart';

/// The salon's editable public profile in the pro app
/// (docs/design/pro-salon-lifecycle.md L2 — the app twin of web 7.3e-i):
/// loads the listing, saves the allowlisted fields + the map pin.
class ProSalonProfileProvider extends ChangeNotifier implements SalonScoped {
  Provider? _provider;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  Provider? get provider => _provider;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load(String providerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    // **By account, not by public id.** This used to call
    // `providerService.getProviderById` — the unauthenticated public read —
    // for the salon the caller is already signed into. `GET /me/provider`
    // returns the identical document resolved from the token, so there was
    // nothing to gain by asking anonymously and a draft salon to lose the day
    // the public route closes (T51; salon-state-and-refusals.md Decision C).
    // The write half of this class was always right: `save()` below goes
    // through `proService`.
    final res = await serviceLocator.proService.getMyProvider();
    _isLoading = false;
    if (res.success && res.data != null) {
      _provider = res.data!.salon;
    } else {
      _provider = null;
      _error = res.error ?? 'Chargement impossible';
    }
    notifyListeners();
  }

  /// Save the allowlisted changes; refreshes [provider] on success.
  Future<bool> save(String providerId, Map<String, dynamic> changes) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    final res = await serviceLocator.proService.updateSalonProfile(
      providerId,
      changes,
    );
    _isSaving = false;
    if (res.success && res.data != null) {
      _provider = res.data;
    } else {
      _error = res.error ?? 'Enregistrement impossible';
    }
    notifyListeners();
    return res.success;
  }

  bool _isUploadingLogo = false;
  bool get isUploadingLogo => _isUploadingLogo;
  String? _logoError;
  String? get logoError => _logoError;

  /// Upload [sourcePath] and save it as the salon's logo — immediately, the
  /// avatar pattern: the PATCH carries ONLY `logoUrl`, so it cannot fight
  /// the rest of the form, which stays staged until « Enregistrer ».
  /// Design: docs/design/salon-logo.md §2.
  Future<bool> uploadLogo(String providerId, String sourcePath) async {
    _isUploadingLogo = true;
    _logoError = null;
    notifyListeners();
    final up = await serviceLocator.logoImageUploadService.uploadImage(
      source: sourcePath,
    );
    if (!up.success || up.data == null) {
      _isUploadingLogo = false;
      _logoError = 'Échec de l’envoi. Réessayez.';
      notifyListeners();
      return false;
    }
    final ok = await save(providerId, {'logoUrl': up.data});
    _isUploadingLogo = false;
    if (!ok) _logoError = 'Échec de l’envoi. Réessayez.';
    notifyListeners();
    return ok;
  }

  /// Clears the logo — the empty string is the contract's delete
  /// (salon-logo.md §3, the `/me` `phone` semantics).
  Future<bool> removeLogo(String providerId) =>
      save(providerId, {'logoUrl': ''});

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _provider = null;
    _isLoading = false;
    _isSaving = false;
    _error = null;
    notifyListeners();
  }
}
