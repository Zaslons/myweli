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

  test('the card: the booking’s « commune, ville », else the list’s city, '
      'else the list’s address', () {
    expect(
      cardPlaceLine(
        appt(address: 'Rue 12', commune: 'Cocody', city: 'Abj'),
        listedCity: 'Marcory',
      ),
      'Cocody, Abj',
    );
    // No commune on the booking: the list's city — not the booking's street
    // address, which an older server already sends (§2.9).
    expect(
      cardPlaceLine(
        appt(address: 'Rue 12', city: 'Abj'),
        listedCity: 'Abidjan',
      ),
      'Abidjan',
    );
    expect(
      cardPlaceLine(appt(address: 'Rue 12'), listedAddress: 'Rue 9'),
      'Rue 9',
    );
    expect(cardPlaceLine(appt(address: 'Rue 12')), isNull);
  });

  Appointment placed({double? lat, double? lng, String? photo, String? st}) =>
      appt().copyWith(
        providerLatitude: lat,
        providerLongitude: lng,
        providerPhotoUrl: photo,
        providerStatus: st,
      );

  test('the card’s position: the booking’s pair before the list’s', () {
    expect(
      cardPosition(placed(lat: 5.3, lng: -3.9), listedLat: 1, listedLng: 1),
      (lat: 5.3, lng: -3.9),
    );
    // Half a pair on the booking is none: the list's then.
    expect(cardPosition(placed(lat: 5.3), listedLat: 1, listedLng: 2), (
      lat: 1.0,
      lng: 2.0,
    ));
    expect(cardPosition(placed(), listedLat: 1), isNull);
  });

  test('the card’s photo: the booking’s, then the list’s only while live', () {
    expect(cardPhoto(placed(photo: 'own'), listedPhoto: 'listed'), 'own');
    expect(cardPhoto(placed(), listedPhoto: 'listed'), 'listed');
    expect(cardPhoto(placed(photo: ''), listedPhoto: 'listed'), 'listed');
    // A stopped salon: the server sends no photo, and a list loaded before it
    // stopped must not bring the cover back (decision 194).
    for (final st in ['draft', 'suspended', 'archived']) {
      expect(cardPhoto(placed(st: st), listedPhoto: 'listed'), isNull);
    }
  });
}
