import 'package:flutter/foundation.dart';
import '../models/provider.dart';
import '../models/api_response.dart';
import '../core/di/dependency_injection.dart';
import '../services/interfaces/favorites_service_interface.dart';

class FavoritesProvider extends ChangeNotifier {
  final FavoritesServiceInterface _favoritesService = serviceLocator.favoritesService;

  List<String> _favoriteProviderIds = [];
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;

  List<String> get favoriteProviderIds => _favoriteProviderIds;
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
      final response = await _favoritesService.getFavoriteProviderIds(userId);
      if (response.success && response.data != null) {
        _favoriteProviderIds = response.data!;
        _error = null;
      } else {
        _error = response.error ?? 'Erreur lors du chargement des favoris';
        _favoriteProviderIds = [];
      }
    } catch (e) {
      _error = e.toString();
      _favoriteProviderIds = [];
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

  /// Get full provider objects from list of all providers
  List<Provider> getFavoriteProviders(List<Provider> allProviders) {
    return allProviders.where((provider) => _favoriteProviderIds.contains(provider.id)).toList();
  }

  /// Clear favorites (e.g., on logout)
  void clearFavorites() {
    _favoriteProviderIds = [];
    _currentUserId = null;
    _error = null;
    notifyListeners();
  }
}
