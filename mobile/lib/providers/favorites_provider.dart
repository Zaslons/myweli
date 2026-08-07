import 'package:flutter/foundation.dart';

import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/provider.dart';
import '../services/interfaces/favorites_service_interface.dart';

class FavoritesProvider extends ChangeNotifier {
  final FavoritesServiceInterface _favoritesService =
      serviceLocator.favoritesService;

  List<String> _favoriteProviderIds = [];
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

  /// Load favorites for a user
  Future<void> loadFavorites(String userId) async {
    if (_currentUserId == userId && _favoriteProviderIds.isNotEmpty) {
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
      _error = e.toString();
      _favoriteProviderIds = [];
      _favoriteProviders = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggle favorite status for a provider
  Future<bool> toggleFavorite(String userId, String providerId) async {
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
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if a provider is favorited
  bool isFavorite(String providerId) {
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

  /// Clear favorites (e.g., on logout)
  void clearFavorites() {
    _favoriteProviderIds = [];
    _favoriteProviders = [];
    _currentUserId = null;
    _error = null;
    notifyListeners();
  }
}
