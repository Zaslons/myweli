import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

void main() {
  late MockProService service;

  setUp(() => service = MockProService());

  test('createService carries price range + duration variants', () async {
    final res = await service.createService(SalonId('provider1'), {
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

  test(
    'updateService with no max / no variants yields a plain service',
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
    },
  );

  // docs/design/pro-journal-shows-new-booking.md §3 — the server's `201`
  // carries the booking's length, and « Ma journée » draws the new card's end
  // from it before any reload. The mock returned none, so the card would have
  // ended 30 minutes after its start whatever was booked.
  test('createManualBooking answers with the length of what was booked — '
      'the sum of its services', () async {
    final res = await service.createManualBooking(
      providerId: SalonId('provider1'),
      serviceIds: const ['service1', 'service3'], // 30 + 45 minutes
      appointmentDateTime: DateTime.utc(2027, 1, 15, 14, 30),
      clientName: 'Yao K.',
    );

    expect(res.success, isTrue);
    expect(res.data!.durationMinutes, 75);
    expect(res.data!.totalPrice, 12000);
    expect(res.data!.status.name, 'confirmed');
  });

  test('…and with 30 minutes when the services come to nothing, like the '
      'server', () async {
    final res = await service.createManualBooking(
      providerId: SalonId('provider1'),
      serviceIds: const ['unknown'],
      appointmentDateTime: DateTime.utc(2027, 1, 15, 16),
    );
    expect(res.data!.durationMinutes, 30);
  });
}
