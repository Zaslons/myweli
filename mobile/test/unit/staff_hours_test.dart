import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/staff_hours.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimeSlot _ts(int startHour, int endHour) => TimeSlot(
      startTime: DateTime(2000, 1, 1, startHour),
      endTime: DateTime(2000, 1, 1, endHour),
      isAvailable: true,
    );

Artist _artist(Map<int, List<TimeSlot>> hours) => Artist(
      id: 'a',
      name: 'a',
      providerId: 'p',
      workingHours: hours,
    );

void main() {
  group('Artist.workingHours model', () {
    test('round-trips through JSON', () {
      final artist = _artist({
        1: [_ts(10, 17)],
        2: [_ts(10, 17)],
      });
      final back = Artist.fromJson(artist.toJson());
      expect(back, artist);
      expect(back.workingHours[1]!.first.startTime.hour, 10);
    });

    test('defaults to empty (follows salon)', () {
      const artist = Artist(id: 'a', name: 'a', providerId: 'p');
      expect(artist.workingHours, isEmpty);
      final json = artist.toJson()..remove('workingHours');
      expect(Artist.fromJson(json).workingHours, isEmpty);
    });
  });

  group('artistWorksDuring', () {
    final tue = DateTime(2026, 6, 23); // a Tuesday
    final dayIdx = tue.weekday - 1;
    final artist = _artist({
      dayIdx: [_ts(10, 17)]
    });

    test('inherits salon hours when no working hours set', () {
      expect(
        artistWorksDuring(_artist(const {}), DateTime(2026, 6, 23, 8),
            DateTime(2026, 6, 23, 9)),
        isTrue,
      );
    });

    test('true when the window is within the day range', () {
      expect(
        artistWorksDuring(
            artist, DateTime(2026, 6, 23, 10), DateTime(2026, 6, 23, 11)),
        isTrue,
      );
    });

    test('false before opening or after closing', () {
      expect(
        artistWorksDuring(
            artist, DateTime(2026, 6, 23, 9), DateTime(2026, 6, 23, 10)),
        isFalse,
      );
      expect(
        artistWorksDuring(artist, DateTime(2026, 6, 23, 16, 30),
            DateTime(2026, 6, 23, 17, 30)),
        isFalse,
      );
    });

    test('false on a day with no range (day off)', () {
      final off = tue.add(const Duration(days: 1)); // different weekday
      expect(
        artistWorksDuring(artist, DateTime(off.year, off.month, off.day, 11),
            DateTime(off.year, off.month, off.day, 12)),
        isFalse,
      );
    });
  });

  group('slot engine respects per-staff hours', () {
    // artist5 (provider2) is seeded part-time Tue–Sat 10:00–17:00; artist3 has
    // no custom hours (follows salon).
    const providerId = 'provider2';
    const serviceIds = ['service4']; // Tissage — artist3 & artist5 can do it

    test('a part-time member only offers slots within their hours', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final service = MockAppointmentService();

      Future<List<DateTime>> slots(DateTime d, String artistId) async =>
          (await service.getAvailableTimeSlots(
            providerId: providerId,
            date: d,
            serviceIds: serviceIds,
            artistId: artistId,
          ))
              .data!;

      // Find a day where the full-hours artist has an early (<10:00) slot and
      // the part-time artist also works (so the difference is observable).
      DateTime? day;
      for (var i = 1; i <= 14; i++) {
        final d = DateTime.now().add(Duration(days: i));
        final full = await slots(d, 'artist3');
        final part = await slots(d, 'artist5');
        if (full.any((s) => s.hour < 10) && part.isNotEmpty) {
          day = DateTime(d.year, d.month, d.day);
          break;
        }
      }
      expect(day, isNotNull,
          reason: 'expected a day with early salon slots and artist5 working');

      final artist5Slots = await slots(day!, 'artist5');
      // Part-timer never offered before 10:00...
      expect(artist5Slots.every((s) => s.hour >= 10), isTrue);
      // ...while the full-hours artist is.
      final artist3Slots = await slots(day, 'artist3');
      expect(artist3Slots.any((s) => s.hour < 10), isTrue);
    });
  });
}
