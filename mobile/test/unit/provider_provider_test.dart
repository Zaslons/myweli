import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockProviderService extends Mock implements ProviderServiceInterface {}

class _FakeProvider extends Fake implements Provider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockProviderService service;

  setUpAll(() {
    service = _MockProviderService();
    // The service locator exposes `late final` fields; assigning the mock once
    // per test isolate is enough — each test re-stubs this same instance.
    serviceLocator.providerService = service;
  });

  setUp(() {
    reset(service);
    SharedPreferences.setMockInitialValues({});
  });

  void stubProviders(List<Provider> result) {
    when(
      () => service.getProviders(
        category: any(named: 'category'),
        searchQuery: any(named: 'searchQuery'),
        commune: any(named: 'commune'),
      ),
    ).thenAnswer((_) async => ApiResponse<List<Provider>>.success(result));
  }

  test('loadProviders stores results and clears loading on success', () async {
    stubProviders(<Provider>[_FakeProvider()]);

    final provider = ProviderProvider();
    await provider.loadProviders();

    expect(provider.providers, hasLength(1));
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
  });

  test(
    'loadProviders surfaces the error and empties the list on failure',
    () async {
      when(
        () => service.getProviders(
          category: any(named: 'category'),
          searchQuery: any(named: 'searchQuery'),
          commune: any(named: 'commune'),
        ),
      ).thenAnswer((_) async => ApiResponse<List<Provider>>.error('boom'));

      final provider = ProviderProvider();
      await provider.loadProviders();

      expect(provider.providers, isEmpty);
      expect(provider.error, 'boom');
      expect(provider.isLoading, isFalse);
    },
  );

  test('setCommune updates state and filters the list by commune', () async {
    stubProviders(<Provider>[_FakeProvider()]);

    final provider = ProviderProvider();
    await provider.setCommune('Cocody');

    expect(provider.selectedCommune, 'Cocody');
    verify(
      () => service.getProviders(
        category: any(named: 'category'),
        searchQuery: any(named: 'searchQuery'),
        commune: 'Cocody',
      ),
    ).called(1);
  });

  test('setCommune(null) clears the commune filter', () async {
    stubProviders(<Provider>[_FakeProvider()]);

    final provider = ProviderProvider();
    await provider.setCommune('Cocody');
    await provider.setCommune(null);

    expect(provider.selectedCommune, isNull);
  });

  /// docs/design/salon-rating-new-and-visits-card.md §2.2 — a salon's first
  /// reviewer used to see « Nouveau » and « Pas encore d’avis. » right above
  /// their own review: the local add appended the review and left the
  /// aggregate at 0.
  group('addReviewLocally moves the aggregate with the review', () {
    Review review(int stars) => Review(
      id: 'r$stars',
      providerId: 'provider1',
      userId: 'user1',
      userName: 'Awa K.',
      rating: stars,
      text: 'Très bien',
      serviceName: 'Brushing',
      createdAt: DateTime(2026, 10, 13),
    );

    test('the first review of a new salon', () {
      final p = ProviderProvider()
        ..showPreloaded(
          MockData.providers
              .firstWhere((x) => x.id == 'provider1')
              .copyWith(rating: 0, reviewCount: 0, reviews: const []),
        );
      p.addReviewLocally(review(4));
      expect(p.selectedProvider!.reviewCount, 1);
      expect(p.selectedProvider!.rating, 4.0);
      expect(p.selectedProvider!.reviews, hasLength(1));
    });

    test('a later review averages in, rounded to one decimal', () {
      final p = ProviderProvider()
        ..showPreloaded(
          MockData.providers
              .firstWhere((x) => x.id == 'provider1')
              .copyWith(rating: 4.5, reviewCount: 2, reviews: const []),
        );
      p.addReviewLocally(review(5));
      expect(p.selectedProvider!.reviewCount, 3);
      expect(p.selectedProvider!.rating, 4.7); // (4.5×2 + 5) / 3 = 4.666…
    });

    test('another salon’s review changes nothing', () {
      final p = ProviderProvider()
        ..showPreloaded(
          MockData.providers.firstWhere((x) => x.id == 'provider2'),
        );
      final before = p.selectedProvider;
      p.addReviewLocally(review(5));
      expect(p.selectedProvider, same(before));
    });
  });
}
