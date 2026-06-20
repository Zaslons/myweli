import '../../models/provider.dart';
import '../../models/api_response.dart';
import '../../core/constants/app_constants.dart';
import '../interfaces/provider_service_interface.dart';
import 'mock_data.dart';

class MockProviderService implements ProviderServiceInterface {
  @override
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    int page = 1,
    int limit = 20,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    var providers = List<Provider>.from(MockData.providers);

    // Filter by category
    if (category != null && category.isNotEmpty) {
      providers = providers.where((p) => p.category == category).toList();
    }

    // Filter by search query
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      providers = providers.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.description.toLowerCase().contains(query) ||
            p.address.toLowerCase().contains(query);
      }).toList();
    }

    // Pagination
    final start = (page - 1) * limit;
    final end = start + limit;
    final paginatedProviders = providers.length > start
        ? providers.sublist(
            start,
            end > providers.length ? providers.length : end,
          )
        : <Provider>[];

    return ApiResponse.success(paginatedProviders);
  }

  @override
  Future<ApiResponse<Provider>> getProviderById(String id) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final provider = MockData.providers.firstWhere((p) => p.id == id);
      final providerReviews = MockData.reviews
          .where((r) => r.providerId == id)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ApiResponse.success(provider.copyWith(reviews: providerReviews));
    } catch (e) {
      return ApiResponse.error('Provider non trouvé');
    }
  }

  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() async {
    await Future.delayed(AppConstants.mockDelay);

    // Return top 3 rated providers
    final featured = List<Provider>.from(MockData.providers)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    
    return ApiResponse.success(featured.take(3).toList());
  }

  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    // For mock, just return all providers
    // In real app, would calculate distance and sort
    return ApiResponse.success(MockData.providers);
  }
}



