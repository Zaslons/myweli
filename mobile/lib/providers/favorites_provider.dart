import 'package:flutter/foundation.dart';

import '../core/access/account_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/provider.dart';
import '../services/interfaces/favorites_service_interface.dart';

class FavoritesProvider extends ChangeNotifier implements AccountScoped {
  final FavoritesServiceInterface _favoritesService =
      serviceLocator.favoritesService;

  /// Whose favourites these are — see [resetForAccountChange]. A read or a
  /// heart sent before the account changed writes nothing when it answers
  /// after (docs/design/consumer-account-scope.md §2.3).
  int _account = 0;

  List<SalonId> _favoriteProviderIds = [];
  List<Provider> _favoriteProviders = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;

  List<String> get favoriteProviderIds => _favoriteProviderIds;

  /// The favourite salons as the SERVER hydrated them — including any that
  /// stopped taking appointments, which the discovery list excludes.
  List<Provider> get favoriteProviders => _favoriteProviders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load favorites for a user.
  ///
  /// [force] reads even when this user's list is already in memory — the data
  /// export needs the account as it is now, not as it was when the session
  /// first read it (docs/design/consumer-export-completeness.md §1 point 7).
  /// It also resets [error], which the early return below leaves as it was.
  Future<void> loadFavorites(String userId, {bool force = false}) async {
    if (!force && _currentUserId == userId && _favoriteProviderIds.isNotEmpty) {
      // Already loaded for this user
      return;
    }

    final account = _account;
    _isLoading = true;
    _error = null;
    _currentUserId = userId;
    notifyListeners();

    ApiResponse<List<Provider>>? response;
    try {
      response = await _favoritesService.getFavoriteProviders(userId);
    } catch (e) {
      response = null;
    }
    if (account != _account) return;
    final loaded = response?.data;
    if (response != null && response.success && loaded != null) {
      _favoriteProviders = loaded;
      _favoriteProviderIds = [for (final p in loaded) p.id];
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors du chargement des favoris';
      _favoriteProviderIds = [];
      _favoriteProviders = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Toggle favorite status for a provider
  Future<bool> toggleFavorite(String userId, SalonId providerId) async {
    if (userId.isEmpty) {
      _error = 'Utilisateur non connecté';
      notifyListeners();
      return false;
    }

    final account = _account;
    // Ensure favorites are loaded
    if (_currentUserId != userId || _favoriteProviderIds.isEmpty) {
      await loadFavorites(userId);
    }
    if (account != _account) return false;

    final isCurrentlyFavorite = _favoriteProviderIds.contains(providerId);

    _isLoading = true;
    notifyListeners();

    ApiResponse<bool>? response;
    try {
      if (isCurrentlyFavorite) {
        response = await _favoritesService.removeFavorite(userId, providerId);
      } else {
        response = await _favoritesService.addFavorite(userId, providerId);
      }
    } catch (e) {
      response = null;
    }
    final done = response != null && response.success;
    // Done on the previous account's favourites — not on the next one's.
    if (account != _account) return done;
    if (done) {
      if (isCurrentlyFavorite) {
        _favoriteProviderIds.remove(providerId);
      } else if (!_favoriteProviderIds.contains(providerId)) {
        _favoriteProviderIds.add(providerId);
      }
      _error = null;
    } else {
      _error = response == null
          ? kGenericErrorMessage
          : response.error ?? 'Erreur lors de la modification des favoris';
    }
    _isLoading = false;
    notifyListeners();
    return done;
  }

  /// Check if a provider is favorited
  bool isFavorite(SalonId providerId) {
    return _favoriteProviderIds.contains(providerId);
  }

  /// The favourite salons.
  ///
  /// **[allProviders] is a fallback, not the source.** This used to intersect
  /// the ids with the discovery list, which excludes salons that are `draft`
  /// or `suspended` — so a favourite whose salon stopped simply disappeared,
  /// and the screen said « Aucun favori » to someone who had one. The server
  /// hydrates the list now (Decision C); the intersection remains only for a
  /// caller that loaded ids without documents.
  List<Provider> getFavoriteProviders(List<Provider> allProviders) {
    if (_favoriteProviders.isNotEmpty) return _favoriteProviders;
    return allProviders
        .where((provider) => _favoriteProviderIds.contains(provider.id))
        .toList();
  }

  /// A salon's rating and review count just changed — a review of it was
  /// published (docs/design/amounts-that-fit.md §5 « Reviews »): carry them
  /// onto its hydrated copy, if it is a favourite.
  ///
  /// These copies are loaded once per user per session ([loadFavorites]
  /// returns early afterwards, and the home's pull-to-refresh does not reload
  /// them), so without this the « Mes favoris » cards kept the old figures —
  /// « Nouveau », for a salon's first review — until the app restarted.
  ///
  /// The signature is `SalonFiguresSink`'s (provider_provider.dart): the
  /// review sheet hands this method to `ProviderProvider.submitReview`.
  void patchSalonFigures(
    SalonId providerId, {
    required double rating,
    required int reviewCount,
  }) {
    final patched = withSalonFigures(
      _favoriteProviders,
      providerId,
      rating: rating,
      reviewCount: reviewCount,
    );
    if (identical(patched, _favoriteProviders)) return;
    _favoriteProviders = patched;
    notifyListeners();
  }

  /// The account changed (B9.13). It replaces `clearFavorites`, which the
  /// profile screen called by hand — before the sign-out, so a sign-out that
  /// failed emptied the hearts of an account still signed in.
  @override
  void resetForAccountChange() {
    _account++;
    _favoriteProviderIds = [];
    _favoriteProviders = [];
    _currentUserId = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
