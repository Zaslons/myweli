import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Availability.bufferMinutes', () {
    test('round-trips through JSON', () {
      final availability = Availability(
        providerId: 'p1',
        weeklySchedule: const {},
        blockedDates: const [],
        bufferMinutes: 15,
      );
      final back = Availability.fromJson(availability.toJson());
      expect(back, availability);
      expect(back.bufferMinutes, 15);
    });

    test('defaults to 0 when absent', () {
      final json = Availability(
        providerId: 'p1',
        weeklySchedule: const {},
        blockedDates: const [],
      ).toJson()
        ..remove('bufferMinutes');
      expect(Availability.fromJson(json).bufferMinutes, 0);
    });
  });

  group('buffer affects slot availability', () {
    const providerId = 'provider2';
    const artistId = 'artist3';
    const serviceIds = ['service6']; // Lissage, artist3 only

    void setBuffer(int minutes) {
      final i = MockData.providers.indexWhere((p) => p.id == providerId);
      MockData.providers[i] = MockData.providers[i].copyWith(
        availability:
            MockData.providers[i].availability.copyWith(bufferMinutes: minutes),
      );
    }

    test('a buffer removes the slots adjacent to an existing booking',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      setBuffer(0);
      final service = MockAppointmentService();

      // Find a future day that has a few slots for this artist/service.
      DateTime? day;
      for (var i = 1; i <= 14; i++) {
        final d = DateTime.now().add(Duration(days: i));
        final res = await service.getAvailableTimeSlots(
          providerId: providerId,
          date: d,
          serviceIds: serviceIds,
          artistId: artistId,
        );
        if ((res.data?.length ?? 0) >= 3) {
          day = DateTime(d.year, d.month, d.day);
          break;
        }
      }
      expect(day, isNotNull, reason: 'expected an open day with slots');

      // Book the earliest slot.
      final firstSlots = (await service.getAvailableTimeSlots(
        providerId: providerId,
        date: day!,
        serviceIds: serviceIds,
        artistId: artistId,
      ))
          .data!;
      await service.bookAppointment(
        providerId: providerId,
        serviceIds: serviceIds,
        appointmentDateTime: firstSlots.first,
        artistId: artistId,
      );

      Future<List<DateTime>> slots() async =>
          (await service.getAvailableTimeSlots(
            providerId: providerId,
            date: day!,
            serviceIds: serviceIds,
            artistId: artistId,
          ))
              .data!;

      setBuffer(0);
      final withoutBuffer = await slots();
      setBuffer(60);
      final withBuffer = await slots();

      // The buffer only ever removes slots, never adds them...
      expect(withBuffer.every(withoutBuffer.contains), isTrue);
      // ...and it removes at least one slot next to the booking.
      expect(withBuffer.length, lessThan(withoutBuffer.length));

      setBuffer(0); // restore
    });
  });
}
