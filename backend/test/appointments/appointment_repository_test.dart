import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:test/test.dart';

import 'appointment_repository_contract.dart';

/// The in-memory twin under the same contract as Postgres
/// (`db/postgres_repositories_test.dart`). docs/design/appointment-currency-stamp.md §8.2.
void main() {
  group('InMemoryAppointmentRepository — the twin contract', () {
    appointmentRepositoryContract(repo: InMemoryAppointmentRepository.new);
  });

  // docs/design/appointment-twin-update.md §5.3, §8.5 (decision 215): the
  // in-memory twin of the Postgres guest-phone UPDATE
  // (`postgres_clients_repository.dart`): `provider_id = @pid AND
  // user_id = 'manual' AND client_phone = @old`, and nothing else.
  group('InMemoryAppointmentRepository.moveGuestPhone', () {
    const oldPhone = '+2250700000101';
    const newPhone = '+2250700000202';

    Map<String, dynamic> booking(
      String id, {
      String providerId = 'provider1',
      String userId = 'manual',
      String? clientPhone = oldPhone,
    }) => {
      'id': id,
      'currency': 'XOF',
      'userId': userId,
      'providerId': providerId,
      'serviceIds': ['s1'],
      'artistId': null,
      'appointmentDate': DateTime.utc(2030, 6, 25, 9).toIso8601String(),
      'durationMinutes': 30,
      'status': 'completed',
      'totalPrice': 10000,
      'depositAmount': 0,
      'balanceDue': 10000,
      'cancellationWindowHours': 24,
      'clientName': 'Tante Marie',
      'clientPhone': clientPhone,
      'notes': null,
      'depositScreenshotUrl': null,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    };

    test("moves the salon's own guest bookings carrying the old number, and "
        'nothing else', () async {
      final r = InMemoryAppointmentRepository();
      await r.create(booking('mine1'));
      await r.create(booking('mine2'));
      await r.create(booking('other_salon', providerId: 'provider2'));
      await r.create(booking('client_own', userId: 'user_consumer'));
      await r.create(booking('other_phone', clientPhone: '+2250700000999'));

      final moved = r.moveGuestPhone(
        providerId: 'provider1',
        from: oldPhone,
        to: newPhone,
      );

      Future<Object?> phone(String id) async =>
          (await r.byId(id))!['clientPhone'];
      expect(
        await phone('mine1'),
        newPhone,
        reason: "the salon's guest booking did not move",
      );
      expect(await phone('mine2'), newPhone);
      expect(
        await phone('other_salon'),
        oldPhone,
        reason: "another salon's booking moved",
      );
      expect(
        await phone('client_own'),
        oldPhone,
        reason: "a client's own booking moved",
      );
      expect(
        await phone('other_phone'),
        '+2250700000999',
        reason: 'a booking with another number moved',
      );
      expect(moved, 2, reason: 'the count of moved bookings');
    });
  });
}
