import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';

double _minPrice(Provider p) {
  final prices = p.services.where((s) => s.active).map((s) => s.price);
  return prices.isEmpty
      ? double.infinity
      : prices.reduce((a, b) => a < b ? a : b);
}

void main() {
  // The sort and « Disponible aujourd’hui » moved off `ProviderProvider`
  // onto the salon list's own search (docs/design/consumer-search.md §2.7,
  // decision 236): salon_search_controller_test.dart holds that they reach
  // the server, last the session, and never reach the home or the map.

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
        today.map((p) => p.id).toSet().difference(all.map((p) => p.id).toSet()),
        isEmpty,
      );
    });
  });
}
