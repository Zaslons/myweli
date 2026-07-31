import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/booking_horizons.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A14d — the bookable window, as the CONSUMER experiences it through the mock.
///
/// **Why this file is against the mock and not a pure function.** Every mobile
/// widget and unit test runs on `MockAppointmentService`, which recomputes the
/// whole slot engine client-side. If the mock does not mirror the API, a gate
/// written here passes while the server refuses the very same booking — the
/// worst kind of green. So these assert the mock, and each one names the line
/// of `slot_service.dart` it mirrors.
///
/// The mock had two gaps A14d had to close, both proven red before the fix:
///   1. **no horizon check at all** — only past days were rejected, so a day
///      400 days out returned a full slot list;
///   2. the minimum notice applied **only when the requested day WAS today**,
///      so a notice longer than a day was entirely unenforced — a 48-hour
///      salon still offered tomorrow.
/// Strips comments so a commented-out `horizon:` cannot satisfy the wiring pin
/// below — the lesson `salon_time_pin_test.dart` records after a prose mention
/// of an idiom turned a self-check permanently red.
String _stripDartComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp('//[^\n]*'), '');

void main() {
  const providerId = 'provider2';

  /// The seeded salon's zone — every bound below is a SALON day, never the
  /// device's.
  String? tzOf() => MockData.providers
      .firstWhere((p) => p.id == providerId)
      .timezone;

  /// Sets the window through the PRO service, which is the real wire: it
  /// persists into `MockData.providers`, where the consumer slot computation
  /// reads it. Restores on teardown — `MockData.providers` is global mutable
  /// state shared with every other test in the run.
  Future<void> setWindow({int? horizonDays, int? noticeMinutes}) async {
    final i = MockData.providers.indexWhere((p) => p.id == providerId);
    final before = MockData.providers[i].availability;
    addTearDown(
      () => MockData.providers[i] = MockData.providers[i].copyWith(
        availability: before,
      ),
    );
    await MockProService().updateAvailability(
      providerId,
      before.copyWith(
        bookingHorizonDays: horizonDays ?? before.bookingHorizonDays,
        minimumNoticeMinutes: noticeMinutes ?? before.minimumNoticeMinutes,
      ),
    );
  }

  /// A salon calendar day [days] out, via field arithmetic rather than
  /// `add(Duration(days:))` — the latter adds fixed 24-hour blocks and drifts
  /// across a DST boundary.
  DateTime dayAhead(int days) {
    final t = salonToday(tz: tzOf());
    return DateTime(t.year, t.month, t.day + days);
  }

  Future<List<DateTime>> slotsOn(DateTime day) async {
    SharedPreferences.setMockInitialValues({});
    final res = await MockAppointmentService().getAvailableTimeSlots(
      providerId: providerId,
      date: day,
      durationMinutes: 30,
    );
    return res.data ?? const [];
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('A14d — the far end', () {
    test('a day beyond the salon horizon offers nothing', () async {
      await setWindow(horizonDays: 30);

      // The control. Without it the assertion below passes for a salon that is
      // simply never open, which would certify nothing.
      var inside = <DateTime>[];
      for (var i = 1; i <= 7 && inside.isEmpty; i++) {
        inside = await slotsOn(dayAhead(20 + i));
      }
      expect(
        inside,
        isNotEmpty,
        reason: 'some open day inside a 30-day horizon must offer slots',
      );

      expect(await slotsOn(dayAhead(40)), isEmpty);
    });

    test('the last bookable day is INCLUSIVE, the next is not', () async {
      // `slot_service.dart` refuses when the requested day start is AFTER
      // today + horizon, so today + horizon itself is still bookable. An
      // off-by-one here and the app hides a day the server would accept.
      await setWindow(horizonDays: 45);
      final boundary = dayAhead(45);
      final past = dayAhead(46);

      final onBoundary = await slotsOn(boundary);
      final beyond = await slotsOn(past);

      expect(beyond, isEmpty, reason: 'one day past the horizon');
      // The boundary day may legitimately be a closed weekday; assert only
      // that it is NOT refused for being beyond the horizon, by comparing it
      // with the same day under a horizon that certainly contains it.
      await setWindow(horizonDays: 90);
      final sameDayWideOpen = await slotsOn(boundary);
      expect(
        onBoundary.length,
        sameDayWideOpen.length,
        reason:
            'today + horizonDays is inside the window: it must offer exactly '
            'what it offers under a wider one',
      );
    });

    test('the default horizon reaches a year', () async {
      expect(await slotsOn(dayAhead(400)), isEmpty, reason: 'past 365');
    });
  });

  group('A14d — the near end', () {
    test('a notice longer than a day reaches into FUTURE days', () async {
      // The assertion the old structure could not express. The rule was « for
      // today, only offer starts >= 1h from now », set to null on every other
      // day — so a 48-hour salon could not exclude tomorrow, because the
      // branch that would do it did not exist.
      await setWindow(noticeMinutes: 48 * 60);

      expect(
        await slotsOn(dayAhead(1)),
        isEmpty,
        reason: 'tomorrow is inside a 48-hour notice',
      );

      var later = <DateTime>[];
      for (var i = 3; i <= 9 && later.isEmpty; i++) {
        later = await slotsOn(dayAhead(i));
      }
      expect(later, isNotEmpty, reason: 'past the notice, days open again');
    });

    test('the default 60-minute notice behaves exactly as it did', () async {
      // Deliberately GREEN from birth. It is not a gate — it is the safety
      // argument for the restructure: at the default, one absolute instant
      // must produce what the today-only branch produced, or A14d silently
      // changed every salon's calendar on the day it shipped.
      final now = DateTime.now().toUtc();
      for (final s in await slotsOn(dayAhead(0))) {
        expect(
          s.isBefore(now.add(const Duration(minutes: 59))),
          isFalse,
          reason: 'every start offered today is at least an hour out: $s',
        );
      }
      expect(kDefaultMinimumNoticeMinutes, 60);
    });
  });

  group('A14d — the pro presets cannot express an unbookable salon', () {
    test('no preset pair puts the notice past the horizon', () {
      // The server refuses that combination as `invalid_input`
      // (`isBookableWindow`), so a preset list that could produce it would
      // offer the salon a tap that fails. Pinned so editing either list cannot
      // introduce it silently.
      for (final days in BookingWindowPresets.horizons) {
        for (final minutes in BookingWindowPresets.notices) {
          expect(
            minutes <= days * 24 * 60,
            isTrue,
            reason: 'a $minutes-minute notice inside a $days-day horizon',
          );
        }
      }
    });

    test('every preset is inside the contract bounds', () {
      for (final days in BookingWindowPresets.horizons) {
        expect(days, inInclusiveRange(1, 730));
      }
      for (final minutes in BookingWindowPresets.notices) {
        expect(minutes, inInclusiveRange(0, 10080));
      }
    });
  });

  // ---- A14d — the wiring, which is the whole mobile half ------------------
  //
  // `SlotPicker.horizon` has existed since A14c with a docstring reading
  // « A14d makes this per-salon », and NEITHER call site passed it. It has a
  // default, so the widget compiles, every widget test stays green, and the
  // feature ships as a parameter nobody feeds — the salon sets a window and
  // the app ignores it.
  //
  // No behavioural test can catch that: a `SlotPicker` test constructs the
  // widget itself, and a host test would have to drive a full booking funnel
  // to a slot list to notice. So this reads the SOURCE, which is the only
  // place the omission is visible.
  group('A14d — both consumer call sites feed the salon its own window', () {
    const sites = [
      'lib/screens/booking/booking_hub_screen.dart',
      'lib/screens/appointments/reschedule_screen.dart',
    ];

    test('every SlotPicker call site passes horizon AND minimumNotice', () {
      for (final path in sites) {
        final src = _stripDartComments(File(path).readAsStringSync());
        expect(
          src.contains('SlotPicker('),
          isTrue,
          reason: '$path no longer constructs a SlotPicker — if the call site '
              'moved, move this pin with it rather than deleting it',
        );
        expect(
          src.contains('horizon:'),
          isTrue,
          reason:
              '$path constructs a SlotPicker without `horizon:`, so it takes '
              'the 365-day default and silently ignores what the salon set',
        );
        expect(
          src.contains('minimumNotice:'),
          isTrue,
          reason: '$path ignores the salon minimum notice',
        );
      }
    });

    test('the pin can fail', () {
      // Row 67: six helpers once shipped unable to fail. A pin that only ever
      // reads real files proves nothing about its own predicate.
      const withoutIt = 'SlotPicker(providerId: p, selectedDate: d)';
      expect(_stripDartComments(withoutIt).contains('horizon:'), isFalse);
      // …and a COMMENTED-OUT one must not satisfy it either.
      const commented = 'SlotPicker(\n  // horizon: kBookingHorizon,\n)';
      expect(_stripDartComments(commented).contains('horizon:'), isFalse);
    });
  });
}
