import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';

class _CapturingService implements ProviderServiceInterface {
  ProviderSort? lastSort;
  bool? lastAvailableToday;

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
    lastSort = sort;
    lastAvailableToday = availableToday;
    return ApiResponse.success(const []);
  }

  @override
  Future<ApiResponse<Provider>> getProviderById(String id) =>
      throw UnimplementedError();
  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() =>
      throw UnimplementedError();
  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) =>
      throw UnimplementedError();
}

double _minPrice(Provider p) {
  final prices = p.services.where((s) => s.active).map((s) => s.price);
  return prices.isEmpty
      ? double.infinity
      : prices.reduce((a, b) => a < b ? a : b);
}

void main() {
  group('ProviderProvider forwards sort/availableToday', () {
    late _CapturingService service;
    setUp(() => serviceLocator.providerService = service = _CapturingService());

    test('setSort + setAvailableToday re-query with the new values', () async {
      final p = ProviderProvider();
      await p.setSort(ProviderSort.price);
      expect(p.sort, ProviderSort.price);
      expect(service.lastSort, ProviderSort.price);

      await p.setAvailableToday(true);
      expect(p.availableToday, isTrue);
      expect(service.lastAvailableToday, isTrue);
      expect(service.lastSort, ProviderSort.price); // sticky
    });
  });

  group('MockProviderService sort/filter', () {
    final svc = MockProviderService();

    test('sort=rating → rating desc', () async {
      final list = (await svc.getProviders(sort: ProviderSort.rating)).data!;
      for (var i = 1; i < list.length; i++) {
        expect(list[i - 1].rating >= list[i].rating, isTrue);
      }
    });

    test('sort=price → min active price asc', () async {
      final list = (await svc.getProviders(sort: ProviderSort.price)).data!;
      for (var i = 1; i < list.length; i++) {
        expect(_minPrice(list[i - 1]) <= _minPrice(list[i]), isTrue);
      }
    });

    test('availableToday returns a subset', () async {
      final all = (await svc.getProviders()).data!;
      final today = (await svc.getProviders(availableToday: true)).data!;
      expect(today.length, lessThanOrEqualTo(all.length));
      expect(
          today.map((p) => p.id).toSet().difference(
                all.map((p) => p.id).toSet(),
              ),
          isEmpty);
    });
  });
}
