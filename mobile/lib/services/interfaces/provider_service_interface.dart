import '../../models/api_response.dart';
import '../../models/provider.dart';

/// Discovery sort options (FR-DISC-007). `relevance` = featured + rating (the
/// default); `name` is the wire value sent to `GET /providers?sort=`.
enum ProviderSort {
  relevance('relevance', 'Pertinence'),
  rating('rating', 'Mieux notés'),
  price('price', 'Prix croissant');

  const ProviderSort(this.query, this.label);
  final String query;
  final String label;
}

abstract class ProviderServiceInterface {
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  });
  Future<ApiResponse<Provider>> getProviderById(String id);
  Future<ApiResponse<List<Provider>>> getFeaturedProviders();
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  });
}
