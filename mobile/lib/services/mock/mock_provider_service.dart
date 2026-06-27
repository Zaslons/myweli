import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/provider.dart';
import '../interfaces/provider_service_interface.dart';
import 'mock_data.dart';

class MockProviderService implements ProviderServiceInterface {
  @override
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    var providers = List<Provider>.from(MockData.providers);

    // Filter by category
    if (category != null && category.isNotEmpty) {
      providers = providers.where((p) => p.category == category).toList();
    }

    // Filter by commune
    if (commune != null && commune.isNotEmpty) {
      providers = providers.where((p) => p.commune == commune).toList();
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

    // Filter: available today (FR-DISC-007). Cheap proxy for the slot engine —
    // open on today's weekday and not blocked today.
    if (availableToday) {
      providers = providers.where(_openToday).toList();
    }

    // Sort (FR-DISC-007). relevance → keep the seed order.
    switch (sort) {
      case ProviderSort.rating:
        providers.sort((a, b) => b.rating.compareTo(a.rating));
      case ProviderSort.price:
        providers.sort((a, b) => _minPrice(a).compareTo(_minPrice(b)));
      case ProviderSort.relevance:
        break;
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

  /// Cheap "open today" proxy for the mock: open on today's weekday (0=Mon) and
  /// not blocked today. (The API uses the real slot engine.)
  bool _openToday(Provider p) {
    final now = DateTime.now();
    final blocked = p.availability.blockedDates.any(
      (d) => d.year == now.year && d.month == now.month && d.day == now.day,
    );
    if (blocked) return false;
    final slots = p.availability.weeklySchedule[now.weekday - 1] ?? const [];
    return slots.any((s) => s.isAvailable);
  }

  /// Lowest active service price; `infinity` when none (sorts such salons last).
  double _minPrice(Provider p) {
    final prices = p.services.where((s) => s.active).map((s) => s.price);
    return prices.isEmpty
        ? double.infinity
        : prices.reduce((a, b) => a < b ? a : b);
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
