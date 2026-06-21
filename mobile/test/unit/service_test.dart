import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/service.dart';

void main() {
  test('round-trips through JSON with a price range', () {
    const service = Service(
      id: 's1',
      name: 'Tissage',
      description: 'Pose de tissage',
      price: 15000,
      priceMax: 25000,
      durationMinutes: 120,
      providerId: 'p1',
    );

    final back = Service.fromJson(service.toJson());

    expect(back, service);
    expect(back.priceMax, 25000);
  });

  test('round-trips without a price range (priceMax null)', () {
    const service = Service(
      id: 's2',
      name: 'Coupe Homme',
      description: 'Coupe',
      price: 5000,
      durationMinutes: 30,
      providerId: 'p1',
    );

    final back = Service.fromJson(service.toJson());

    expect(back, service);
    expect(back.priceMax, isNull);
  });
}
