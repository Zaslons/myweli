import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/provider.dart';

/// The salon's editable public profile in the pro app
/// (docs/design/pro-salon-lifecycle.md L2 — the app twin of web 7.3e-i):
/// loads the listing, saves the allowlisted fields + the map pin.
class ProSalonProfileProvider extends ChangeNotifier {
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
    final res = await serviceLocator.providerService.getProviderById(
      providerId,
    );
    _isLoading = false;
    if (res.success && res.data != null) {
      _provider = res.data;
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
}
