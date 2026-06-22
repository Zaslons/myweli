import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/breaks.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimeSlot _ts(int startHour, int endHour) => TimeSlot(
      startTime: DateTime(2000, 1, 1, startHour),
      endTime: DateTime(2000, 1, 1, endHour),
      isAvailable: true,
    );

void main() {
  group('overlapsBreak', () {
    final tue = DateTime(2026, 6, 23); // a Tuesday
    final breaks = {
      tue.weekday - 1: [_ts(13, 14)]
    };

    test('true when the window runs into the break', () {
      expect(
        overlapsBreak(
            breaks, DateTime(2026, 6, 23, 13), DateTime(2026, 6, 23, 13, 30)),
        isTrue,
      );
    });

    test('false when it only touches the break edge', () {
      expect(
        overlapsBreak(
            breaks, DateTime(2026, 6, 23, 12, 30), DateTime(2026, 6, 23, 13)),
        isFalse,
      );
      expect(
        overlapsBreak(
            breaks, DateTime(2026, 6, 23, 14), DateTime(2026, 6, 23, 14, 30)),
        isFalse,
      );
    });

    test('false on a different weekday / with no breaks', () {
      final wed = tue.add(const Duration(days: 1));
      expect(
        overlapsBreak(breaks, DateTime(wed.year, wed.month, wed.day, 13),
            DateTime(wed.year, wed.month, wed.day, 13, 30)),
        isFalse,
      );
      expect(
        overlapsBreak(
            const {}, DateTime(2026, 6, 23, 13), DateTime(2026, 6, 23, 13, 30)),
        isFalse,
      );
    });
  });

  test('Availability round-trips breaks through JSON (+ empty default)', () {
    final availability = Availability(
      providerId: 'p1',
      weeklySchedule: const {},
      blockedDates: const [],
      breaks: {
        1: [_ts(13, 14)]
      },
    );
    final back = Availability.fromJson(availability.toJson());
    expect(back, availability);
    expect(back.breaks[1]!.first.startTime.hour, 13);

    final json = availability.toJson()..remove('breaks');
    expect(Availability.fromJson(json).breaks, isEmpty);
  });

  test('slot engine offers no slot during the lunch break', () async {
    // provider1 is seeded with a 13:00–14:00 break Tue–Sat.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final service = MockAppointmentService();

    DateTime? day;
    List<DateTime> slots = const [];
    for (var i = 1; i <= 14; i++) {
      final d = DateTime.now().add(Duration(days: i));
      final res = await service.getAvailableTimeSlots(
        providerId: 'provider1',
        date: d,
        serviceIds: const ['service1'], // 30 min
      );
      if ((res.data?.isNotEmpty ?? false)) {
        day = d;
        slots = res.data!;
        break;
      }
    }

    expect(day, isNotNull);
    // The break blocks any 30-min slot that would run from 13:00 or 13:30.
    expect(slots.any((s) => s.hour == 13), isFalse);
    // ...but the day is otherwise open.
    expect(slots, isNotEmpty);
  });
}
