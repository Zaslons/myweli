import 'package:flutter/foundation.dart';

import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_figures.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/provider.dart';
import '../services/interfaces/favorites_service_interface.dart';

class FavoritesProvider extends ChangeNotifier {
  final FavoritesServiceInterface _favoritesService =
      serviceLocator.favoritesService;

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

    _isLoading = true;
    _error = null;
    _currentUserId = userId;
    notifyListeners();

    try {
      final response = await _favoritesService.getFavoriteProviders(userId);
      if (response.success && response.data != null) {
        _favoriteProviders = response.data!;
        _favoriteProviderIds = [for (final p in response.data!) p.id];
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des favoris';
        _favoriteProviderIds = [];
        _favoriteProviders = [];
      }
    } catch (e) {
      _error = kGenericErrorMessage;
      _favoriteProviderIds = [];
      _favoriteProviders = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggle favorite status for a provider
  Future<bool> toggleFavorite(String userId, SalonId providerId) async {
    if (userId.isEmpty) {
      _error = 'Utilisateur non connecté';
      notifyListeners();
      return false;
    }

    // Ensure favorites are loaded
    if (_currentUserId != userId || _favoriteProviderIds.isEmpty) {
      await loadFavorites(userId);
    }

    final isCurrentlyFavorite = _favoriteProviderIds.contains(providerId);

    _isLoading = true;
    notifyListeners();

    try {
      final ApiResponse<bool> response;
      if (isCurrentlyFavorite) {
        response = await _favoritesService.removeFavorite(userId, providerId);
      } else {
        response = await _favoritesService.addFavorite(userId, providerId);
      }

      if (response.success) {
        // Update local state
        if (isCurrentlyFavorite) {
          _favoriteProviderIds.remove(providerId);
        } else {
          if (!_favoriteProviderIds.contains(providerId)) {
            _favoriteProviderIds.add(providerId);
          }
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Erreur lors de la modification des favoris';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = kGenericErrorMessage;
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  /// Clear favorites (e.g., on logout)
  void clearFavorites() {
    _favoriteProviderIds = [];
    _favoriteProviders = [];
    _currentUserId = null;
    _error = null;
    notifyListeners();
  }
}
