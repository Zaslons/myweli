import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mock booking engine reads an open window as a RANGE (A14 device run).
///
/// **The same defect the device run found on the server, in the app's own
/// engine.** `slot_service.dart` enumerated each `weeklySchedule` entry's
/// `startTime` and discarded its `endTime`; `mock_appointment_service.dart`
/// did exactly the same thing, and for exactly the same reason nobody noticed:
/// `MockData._generateTimeSlots` emits one entry per 30-minute step, so the
/// only schedule this engine had ever been asked about was the one shape that
/// makes the bug invisible.
///
/// It is reachable in mock mode by the same route as on the server — the pro's
/// day editor writes one `TimeSlot` per range the owner picks, so « 09:00 –
/// 18:00 » is one entry and « 09:00 – 12:00 » + « 14:00 – 18:00 » is two. The
/// adversarial review of the device-run write-up caught that the server fix
/// left this half standing, which would have made « closed » true of one
/// surface and false of the product.
void main() {
  const providerId = 'provider1';

  /// Replaces [providerId]'s weekly template for [weekday] and restores the
  /// SHARED fixture afterwards — `MockData.providers` is a `static final`
  /// global, so a test that writes it without restoring reddens unrelated ones.
  ///
  /// **The break for that weekday is cleared too, and that is not tidiness.**
  /// The seeded salon closes 13:00–14:00, so an expectation written as a plain
  /// half-hour grid is short by two entries — which is exactly how the first
  /// draft of this file failed, at `[8] is <840> instead of <780>`. Breaks are
  /// a separate rule with its own tests (`availability_breaks_test.dart`); this
  /// file is about how an OPEN WINDOW is read, and mixing the two would let a
  /// break regression masquerade as a schedule one.
  void setDay(int weekday, List<TimeSlot> slots) {
    final i = MockData.providers.indexWhere((p) => p.id == providerId);
    final before = MockData.providers[i];
    addTearDown(() => MockData.providers[i] = before);
    final schedule = Map<int, List<TimeSlot>>.from(
      before.availability.weeklySchedule,
    );
    schedule[weekday] = slots;
    final breaks = Map<int, List<TimeSlot>>.from(before.availability.breaks)
      ..remove(weekday);
    MockData.providers[i] = before.copyWith(
      availability: before.availability.copyWith(
        weeklySchedule: schedule,
        breaks: breaks,
      ),
    );
  }

  TimeSlot range(int startHour, int endHour) => TimeSlot(
    startTime: DateTime(2000, 1, 1, startHour),
    endTime: DateTime(2000, 1, 1, endHour),
    isAvailable: true,
  );

  /// A day far enough out that the booking window's near end cannot trim it,
  /// and never a Sunday — the seeded salon is closed then.
  DateTime openDay() {
    var d = DateTime.now().add(const Duration(days: 14));
    while (d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  Future<List<DateTime>> slotsFor(DateTime day, List<String> serviceIds) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final res = await MockAppointmentService().getAvailableTimeSlots(
      providerId: providerId,
      date: day,
      serviceIds: serviceIds,
    );
    return res.data!;
  }

  group('one open window is a range, not a single bookable minute', () {
    test('« 09:00 – 18:00 » is eighteen starts, not one', () async {
      final day = openDay();
      setDay(day.weekday - 1, [range(9, 18)]);

      // `service1` is 30 minutes, so every one of the eighteen half-hour
      // starts between 09:00 and 18:00 fits before close.
      final got = await slotsFor(day, const ['service1']);

      expect(
        got.map((d) => d.hour * 60 + d.minute).toList(),
        [for (var m = 9 * 60; m < 18 * 60; m += 30) m],
        reason:
            'nine open hours are eighteen half-hour starts; reading only '
            'startTime yields exactly one, at 09:00',
      );
    });

    test('a SPLIT day — the everyday shape — is not two starts', () async {
      // Better than the all-day case at showing the size of the loss, and it
      // is what a real salon with a lunch closure enters: two ranges in the
      // day editor. Before the fix this offered 09:00 and 14:00 and nothing
      // else, for seven open hours.
      final day = openDay();
      setDay(day.weekday - 1, [range(9, 12), range(14, 18)]);

      final got = await slotsFor(day, const ['service1']);

      expect(got.map((d) => d.hour * 60 + d.minute).toList(), [
        for (var m = 9 * 60; m < 12 * 60; m += 30) m,
        for (var m = 14 * 60; m < 18 * 60; m += 30) m,
      ]);
    });

    test('one-step entries still yield exactly their own starts', () async {
      // The guard against over-fixing, and the reason `MockData`'s meaning is
      // untouched: `_generateTimeSlots('provider1', 9, 18)` emits eighteen
      // one-step entries, and each must keep contributing exactly ONE start
      // rather than opening a window to the next one. Two NON-CONTIGUOUS
      // half-hour entries say that in the way a contiguous run cannot: if the
      // rule over-fired, 09:30…13:30 would appear between them.
      final day = openDay();
      setDay(day.weekday - 1, [
        TimeSlot(
          startTime: DateTime(2000, 1, 1, 9),
          endTime: DateTime(2000, 1, 1, 9, 30),
          isAvailable: true,
        ),
        TimeSlot(
          startTime: DateTime(2000, 1, 1, 14),
          endTime: DateTime(2000, 1, 1, 14, 30),
          isAvailable: true,
        ),
      ]);

      final got = await slotsFor(day, const ['service1']);

      expect(got.map((d) => d.hour * 60 + d.minute).toList(), [
        9 * 60,
        14 * 60,
      ]);
    });
  });
}
