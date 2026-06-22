import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/booking_duration.dart';
import 'package:myweli/models/service.dart';

Service _svc(
  String id, {
  int duration = 30,
  DurationVariants variants = const DurationVariants(),
}) =>
    Service(
      id: id,
      name: id,
      description: '',
      price: 1000,
      durationMinutes: duration,
      durationVariants: variants,
      providerId: 'p1',
    );

void main() {
  const tissage = DurationVariants(court: 120, moyen: 180, long: 240);

  group('serviceDurationFor', () {
    test('uses the variant minutes for the chosen length', () {
      expect(serviceDurationFor(_svc('s', variants: tissage), 'long'), 240);
      expect(serviceDurationFor(_svc('s', variants: tissage), 'moyen'), 180);
    });

    test('falls back to base when no length / no variants', () {
      expect(serviceDurationFor(_svc('s', duration: 45), null), 45);
      expect(serviceDurationFor(_svc('s', duration: 45), 'long'), 45);
      expect(
        serviceDurationFor(_svc('s', duration: 45, variants: tissage), null),
        45,
      );
    });

    test('falls back to base when that bucket is absent', () {
      const partial = DurationVariants(court: 60); // no moyen/long
      expect(
        serviceDurationFor(_svc('s', duration: 45, variants: partial), 'long'),
        45,
      );
    });
  });

  test('totalBookingDuration sums variant + plain services', () {
    final services = [
      _svc('tissage', duration: 120, variants: tissage),
      _svc('coupe', duration: 30),
    ];
    // long tissage (240) + coupe (30)
    expect(totalBookingDuration(services, 'long'), 270);
    // no length → base tissage (120) + coupe (30)
    expect(totalBookingDuration(services, null), 150);
  });

  test('bookingHasVariants detects any variant service', () {
    expect(bookingHasVariants([_svc('a'), _svc('b')]), isFalse);
    expect(
        bookingHasVariants([_svc('a'), _svc('b', variants: tissage)]), isTrue);
  });

  test('availableLengthVariants returns the ordered union', () {
    final services = [
      _svc('a', variants: const DurationVariants(court: 60)),
      _svc('b', variants: const DurationVariants(long: 200, court: 90)),
    ];
    expect(availableLengthVariants(services), ['court', 'long']);
  });

  group('defaultLengthVariant', () {
    test('prefers moyen', () {
      expect(defaultLengthVariant([_svc('a', variants: tissage)]), 'moyen');
    });
    test('else first available', () {
      expect(
        defaultLengthVariant(
            [_svc('a', variants: const DurationVariants(long: 200))]),
        'long',
      );
    });
    test('null when no variant services', () {
      expect(defaultLengthVariant([_svc('a')]), isNull);
    });
  });

  test('lengthVariantLabel maps keys to French labels', () {
    expect(lengthVariantLabel('court'), 'Court');
    expect(lengthVariantLabel('moyen'), 'Moyen');
    expect(lengthVariantLabel('long'), 'Long');
  });
}
