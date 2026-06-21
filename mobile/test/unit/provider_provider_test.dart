import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
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

  test('loadProviders surfaces the error and empties the list on failure',
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
  });

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
}
