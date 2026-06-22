import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

void main() {
  late MockProService service;

  setUp(() => service = MockProService());

  test('createService carries price range + duration variants', () async {
    final res = await service.createService('provider1', {
      'name': 'Tresses',
      'description': 'selon la longueur',
      'price': 15000,
      'priceMax': 25000,
      'durationMinutes': 120,
      'durationVariants': {'court': 120, 'moyen': 180, 'long': 240},
    });

    expect(res.success, isTrue);
    expect(res.data!.price, 15000);
    expect(res.data!.priceMax, 25000);
    expect(res.data!.durationVariants.moyen, 180);
    expect(res.data!.providerId, 'provider1');
  });

  test('updateService with no max / no variants yields a plain service',
      () async {
    final res = await service.updateService('service1', {
      'name': 'Coupe Homme',
      'description': '',
      'price': 5000,
      'priceMax': null,
      'durationMinutes': 30,
      'durationVariants': <String, dynamic>{},
      'providerId': 'provider1',
    });

    expect(res.success, isTrue);
    expect(res.data!.priceMax, isNull);
    expect(res.data!.durationVariants.isEmpty, isTrue);
  });
}
