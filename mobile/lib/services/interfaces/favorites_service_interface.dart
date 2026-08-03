import '../../models/api_response.dart';
import '../../models/provider.dart';

abstract class FavoritesServiceInterface {
  /// Get list of favorite provider IDs for a user
  Future<ApiResponse<List<String>>> getFavoriteProviderIds(String userId);

  /// The favourite SALONS, hydrated server-side (`GET /me/favorites`).
  ///
  /// **Not an intersection with the discovery list.** The list excludes salons
  /// that are `draft` or `suspended`, so a favourite whose salon stopped
  /// simply vanished from the screen — which reads as « my favourite was
  /// deleted » rather than « that salon stopped taking appointments ». The
  /// server hydrates this one without a status filter, because a favourite is
  /// a relationship the caller already has (Decision C), and each entry
  /// carries its `status` so the row can be MARKED instead of lost.
  Future<ApiResponse<List<Provider>>> getFavoriteProviders(String userId);

  /// Add a provider to favorites
  Future<ApiResponse<bool>> addFavorite(String userId, String providerId);

  /// Remove a provider from favorites
  Future<ApiResponse<bool>> removeFavorite(String userId, String providerId);

  /// Check if a provider is favorited
  Future<ApiResponse<bool>> isFavorite(String userId, String providerId);
}
