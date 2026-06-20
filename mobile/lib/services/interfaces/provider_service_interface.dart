import '../../models/provider.dart';
import '../../models/api_response.dart';

abstract class ProviderServiceInterface {
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
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



