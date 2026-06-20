import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../interfaces/favorites_service_interface.dart';

class MockFavoritesService implements FavoritesServiceInterface {
  static const String _favoritesKeyPrefix = 'favorites_';

  String _getKey(String userId) => '$_favoritesKeyPrefix$userId';

  @override
  Future<ApiResponse<List<String>>> getFavoriteProviderIds(
      String userId) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(userId);
      final favoritesJson = prefs.getString(key);

      if (favoritesJson == null || favoritesJson.isEmpty) {
        return ApiResponse.success([]);
      }

      final List<dynamic> favoritesList = json.decode(favoritesJson);
      final List<String> providerIds =
          favoritesList.map((id) => id.toString()).toList();

      return ApiResponse.success(providerIds);
    } catch (e) {
      return ApiResponse.error(
          'Erreur lors du chargement des favoris: ${e.toString()}');
    }
  }

  @override
  Future<ApiResponse<bool>> addFavorite(
      String userId, String providerId) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(userId);
      final favoritesJson = prefs.getString(key);

      List<String> favorites;
      if (favoritesJson == null || favoritesJson.isEmpty) {
        favorites = [];
      } else {
        final List<dynamic> favoritesList = json.decode(favoritesJson);
        favorites = favoritesList.map((id) => id.toString()).toList();
      }

      // Add if not already present
      if (!favorites.contains(providerId)) {
        favorites.add(providerId);
        await prefs.setString(key, json.encode(favorites));
        return ApiResponse.success(true, message: 'Ajouté aux favoris');
      }

      return ApiResponse.success(true, message: 'Déjà dans les favoris');
    } catch (e) {
      return ApiResponse.error(
          'Erreur lors de l\'ajout aux favoris: ${e.toString()}');
    }
  }

  @override
  Future<ApiResponse<bool>> removeFavorite(
      String userId, String providerId) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(userId);
      final favoritesJson = prefs.getString(key);

      if (favoritesJson == null || favoritesJson.isEmpty) {
        return ApiResponse.success(false, message: 'Aucun favori trouvé');
      }

      final List<dynamic> favoritesList = json.decode(favoritesJson);
      final List<String> favorites =
          favoritesList.map((id) => id.toString()).toList();

      if (favorites.remove(providerId)) {
        await prefs.setString(key, json.encode(favorites));
        return ApiResponse.success(true, message: 'Retiré des favoris');
      }

      return ApiResponse.success(false, message: 'Non trouvé dans les favoris');
    } catch (e) {
      return ApiResponse.error(
          'Erreur lors de la suppression des favoris: ${e.toString()}');
    }
  }

  @override
  Future<ApiResponse<bool>> isFavorite(String userId, String providerId) async {
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(userId);
      final favoritesJson = prefs.getString(key);

      if (favoritesJson == null || favoritesJson.isEmpty) {
        return ApiResponse.success(false);
      }

      final List<dynamic> favoritesList = json.decode(favoritesJson);
      final List<String> favorites =
          favoritesList.map((id) => id.toString()).toList();

      return ApiResponse.success(favorites.contains(providerId));
    } catch (e) {
      return ApiResponse.error(
          'Erreur lors de la vérification: ${e.toString()}');
    }
  }
}
