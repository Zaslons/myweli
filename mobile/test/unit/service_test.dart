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

  test('round-trips with duration variants', () {
    const service = Service(
      id: 's3',
      name: 'Tissage',
      description: 'Pose de tissage',
      price: 15000,
      priceMax: 25000,
      durationMinutes: 120,
      durationVariants: DurationVariants(court: 120, moyen: 180, long: 240),
      providerId: 'p1',
    );

    final back = Service.fromJson(service.toJson());

    expect(back, service);
    expect(back.durationVariants.court, 120);
    expect(back.durationVariants.long, 240);
    expect(back.durationVariants.isNotEmpty, isTrue);
  });

  test('defaults to empty duration variants when absent / partial', () {
    const service = Service(
      id: 's4',
      name: 'Coupe',
      description: '',
      price: 5000,
      durationMinutes: 30,
      providerId: 'p1',
    );
    expect(service.durationVariants.isEmpty, isTrue);

    // A JSON payload with no durationVariants key still parses.
    final json = service.toJson()..remove('durationVariants');
    expect(Service.fromJson(json).durationVariants.isEmpty, isTrue);

    // Partial variants only serialise the present buckets.
    const partial = DurationVariants(moyen: 90);
    expect(partial.toJson(), {'moyen': 90});
    expect(partial.isNotEmpty, isTrue);
  });
}
