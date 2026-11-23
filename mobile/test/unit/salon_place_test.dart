import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/salon_place.dart';
import 'package:myweli/models/appointment.dart';

/// « Le salon »'s address lines and the card's place line
/// (appointment-detail-complete.md §2.6, §2.9).
void main() {
  Appointment appt({String? address, String? commune, String? city}) =>
      Appointment(
        id: 'a',
        userId: 'u1',
        providerId: const SalonId('p1'),
        serviceIds: const ['s1'],
        appointmentDate: DateTime.utc(2026, 12, 1, 9),
        status: AppointmentStatus.confirmed,
        totalPrice: 20000,
        createdAt: DateTime.utc(2026),
        providerAddress: address,
        providerCommune: commune,
        providerCity: city,
      );

  test('« commune, ville », and only with a commune', () {
    expect(communeLine('Cocody', 'Abidjan'), 'Cocody, Abidjan');
    expect(communeLine('Cocody', null), 'Cocody');
    expect(communeLine(null, 'Abidjan'), isNull);
    expect(communeLine('  ', 'Abidjan'), isNull);
  });

  test('the address, then « commune, ville » under it', () {
    expect(
      salonAddressLines(
        appt(address: 'Rue des Jardins', commune: 'Cocody', city: 'Abidjan'),
      ),
      ['Rue des Jardins', 'Cocody, Abidjan'],
    );
  });

  test('the commune is not repeated when the address names it — any case, '
      'any accent', () {
    for (final address in [
      'Rue des Jardins, Cocody',
      'Rue des Jardins, COCODY',
      'Rue des Jardins, Cocôdy',
    ]) {
      expect(
        salonAddressLines(
          appt(address: address, commune: 'Cocody', city: 'Abidjan'),
        ),
        [address],
        reason: address,
      );
    }
    // The control: another commune in the address does not hide this one.
    expect(
      salonAddressLines(
        appt(address: 'Rue 12, Marcory', commune: 'Cocody', city: 'Abidjan'),
      ),
      ['Rue 12, Marcory', 'Cocody, Abidjan'],
    );
  });

  test('no address: the commune line alone; neither: nothing', () {
    expect(salonAddressLines(appt(commune: 'Cocody', city: 'Abidjan')), [
      'Cocody, Abidjan',
    ]);
    expect(salonAddressLines(appt(city: 'Abidjan')), isEmpty);
    expect(salonAddressLines(appt()), isEmpty);
  });

  test('the card: commune, else city, else address', () {
    expect(
      cardPlaceLine(appt(address: 'Rue 12', commune: 'Cocody', city: 'Abj')),
      'Cocody, Abj',
    );
    expect(cardPlaceLine(appt(address: 'Rue 12', city: 'Abidjan')), 'Abidjan');
    expect(cardPlaceLine(appt(address: 'Rue 12')), 'Rue 12');
    expect(cardPlaceLine(appt()), isNull);
  });
}
