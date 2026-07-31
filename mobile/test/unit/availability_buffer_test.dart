import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/booking_horizons.dart';
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
      ).toJson()..remove('bufferMinutes');
      expect(Availability.fromJson(json).bufferMinutes, 0);
    });
  });

  // ---- A14d — the bookable window ----------------------------------------
  //
  // `toJson` is a HAND-BUILT literal, not a spread: a field added to the class
  // but not to that map is silently erased on every write. The pro app PUTs the
  // whole Availability object, so the salon would lose its own window the
  // moment anyone opened Disponibilités — the exact mirror of the server-side
  // allow-list trap A14d's backend half documents.
  //
  // `expect(back, availability)` is what catches it: Equatable compares `props`,
  // so a field added to `props` and forgotten in EITHER direction fails here.
  group('Availability — the bookable window (A14d)', () {
    test('round-trips through JSON', () {
      final availability = Availability(
        providerId: 'p1',
        weeklySchedule: const {},
        blockedDates: const [],
        bookingHorizonDays: 30,
        minimumNoticeMinutes: 120,
      );
      final back = Availability.fromJson(availability.toJson());
      expect(back, availability);
      expect(back.bookingHorizonDays, 30);
      expect(back.minimumNoticeMinutes, 120);
    });

    test('a pre-A14d payload reads the defaults rather than throwing', () {
      // A client on the new build against a server that has not migrated —
      // `bufferMinutes` set the tolerant idiom (`as num?` + `??`) and these
      // follow it. A hard cast here would crash the whole pro screen.
      final json = Availability(
        providerId: 'p1',
        weeklySchedule: const {},
        blockedDates: const [],
      ).toJson()
        ..remove('bookingHorizonDays')
        ..remove('minimumNoticeMinutes');
      final back = Availability.fromJson(json);
      expect(back.bookingHorizonDays, kDefaultBookingHorizonDays);
      expect(back.minimumNoticeMinutes, kDefaultMinimumNoticeMinutes);
    });

    test('the defaults match the app constant they replace', () {
      // If these ever diverge the picker offers a reach the server refuses.
      expect(
        Duration(days: kDefaultBookingHorizonDays),
        kBookingHorizon,
        reason: 'A14d changed no salon behaviour on the day it shipped',
      );
    });
  });

  group('buffer affects slot availability', () {
    const providerId = 'provider2';
    const artistId = 'artist3';
    const serviceIds = ['service6']; // Lissage, artist3 only

    void setBuffer(int minutes) {
      final i = MockData.providers.indexWhere((p) => p.id == providerId);
      MockData.providers[i] = MockData.providers[i].copyWith(
        availability: MockData.providers[i].availability.copyWith(
          bufferMinutes: minutes,
        ),
      );
    }

    test('a 60-min buffer removes a slot adjacent to a booking', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      // Search the next 3 weeks for a day that demonstrates the property,
      // instead of assuming any single `now`-relative day will — the slot
      // layout (and whether a back-to-back slot exists after the booking)
      // varies by date, which used to make this flaky. Each probe starts from a
      // clean prefs store so bookings don't accumulate across iterations.
      for (var i = 1; i <= 21; i++) {
        final d = DateTime.now().add(Duration(days: i));
        final day = DateTime(d.year, d.month, d.day);

        SharedPreferences.setMockInitialValues({});
        final service = MockAppointmentService();

        Future<List<DateTime>> slots() async =>
            (await service.getAvailableTimeSlots(
              providerId: providerId,
              date: day,
              serviceIds: serviceIds,
              artistId: artistId,
            )).data!;

        setBuffer(0);
        final base = await slots();
        if (base.length < 3) continue;

        // Book the earliest slot, then compare buffer 0 vs 60 on the same day.
        await service.bookAppointment(
          providerId: providerId,
          serviceIds: serviceIds,
          appointmentDateTime: base.first,
          artistId: artistId,
        );
        setBuffer(0);
        final withoutBuffer = await slots();
        setBuffer(60);
        final withBuffer = await slots();
        setBuffer(0); // restore the shared mock state

        // The buffer only ever removes slots, never adds them.
        expect(withBuffer.every(withoutBuffer.contains), isTrue);
        if (withBuffer.length < withoutBuffer.length) {
          return; // a 60-min buffer dropped an adjacent slot — property shown
        }
      }
      fail('no day in the next 3 weeks showed the buffer removing a slot');
    });
  });
}
