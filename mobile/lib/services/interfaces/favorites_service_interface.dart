import '../../models/api_response.dart';

abstract class FavoritesServiceInterface {
  /// Get list of favorite provider IDs for a user
  Future<ApiResponse<List<String>>> getFavoriteProviderIds(String userId);

  /// Add a provider to favorites
  Future<ApiResponse<bool>> addFavorite(String userId, String providerId);

  /// Remove a provider from favorites
  Future<ApiResponse<bool>> removeFavorite(String userId, String providerId);

  /// Check if a provider is favorited
  Future<ApiResponse<bool>> isFavorite(String userId, String providerId);
}
