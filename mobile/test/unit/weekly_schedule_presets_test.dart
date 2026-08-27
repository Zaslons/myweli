import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/booking_horizons.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/screens/provider/availability/availability_screen.dart';

/// The « Horaires » models + the honest-selection matcher
/// (docs/design/availability-presets.md §8).
///
/// The invariants mirror `BookingWindowPresets`' docstring contract: editing
/// the list must not be able to silently offer a schedule the server — or
/// common sense — refuses. The web mirror (`SCHEDULE_PRESETS`) is pinned
/// against THIS file from the web suite (`availability-parity.test.ts`), so
/// the labels asserted here are the labels both surfaces show.
void main() {
  group('WeeklySchedulePresets invariants', () {
    test('no preset may produce end ≤ start', () {
      for (final p in WeeklySchedulePresets.all) {
        expect(
          p.endHour > p.startHour,
          isTrue,
          reason: '${p.label}: ${p.startHour}h–${p.endHour}h',
        );
      }
    });

    test('days are a non-empty subset of 0..6', () {
      for (final p in WeeklySchedulePresets.all) {
        expect(p.days, isNotEmpty, reason: p.label);
        expect(
          p.days.every((d) => d >= 0 && d <= 6),
          isTrue,
          reason: '${p.label}: ${p.days}',
        );
      }
    });

    test('labels are unique and use the en dash + middot idiom', () {
      final labels = WeeklySchedulePresets.all.map((p) => p.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final label in labels) {
        expect(
          label,
          contains('·'),
          reason: 'the A14d chip idiom (horizonLabel) uses the middot',
        );
        expect(
          label,
          isNot(contains(' - ')),
          reason: 'day ranges use the en dash « – », never ASCII « - »',
        );
      }
    });
  });

  group('weeklyScheduleMatchesPreset — honest selection', () {
    TimeSlot slot(int startHour, int endHour) => TimeSlot(
      startTime: DateTime.utc(2026, 1, 1, startHour),
      endTime: DateTime.utc(2026, 1, 1, endHour),
      isAvailable: true,
    );

    Map<int, List<TimeSlot>> weekOf(WeeklySchedulePreset p) => {
      for (var d = 0; d < 7; d++)
        d: p.days.contains(d) ? [slot(p.startHour, p.endHour)] : [],
    };

    test('each model matches its own week and no other', () {
      for (final p in WeeklySchedulePresets.all) {
        final week = weekOf(p);
        expect(weeklyScheduleMatchesPreset(week, p), isTrue, reason: p.label);
        for (final other in WeeklySchedulePresets.all) {
          if (identical(other, p)) continue;
          expect(
            weeklyScheduleMatchesPreset(week, other),
            isFalse,
            reason: '${p.label} lit up ${other.label}',
          );
        }
      }
    });

    test('any manual edit unlights the chip', () {
      final p = WeeklySchedulePresets.all.first; // Mar–Sam · 9h–18h
      // A different closing hour.
      final edited = weekOf(p)..[1] = [slot(p.startHour, p.endHour + 1)];
      expect(weeklyScheduleMatchesPreset(edited, p), isFalse);
      // A day outside the model opened.
      final sunday = weekOf(p)..[6] = [slot(10, 12)];
      expect(weeklyScheduleMatchesPreset(sunday, p), isFalse);
      // A second range on a model day.
      final split = weekOf(p)
        ..[2] = [slot(p.startHour, 12), slot(14, p.endHour)];
      expect(weeklyScheduleMatchesPreset(split, p), isFalse);
      // A model day closed.
      final closed = weekOf(p)..[5] = [];
      expect(weeklyScheduleMatchesPreset(closed, p), isFalse);
    });

    test('an empty week matches nothing', () {
      for (final p in WeeklySchedulePresets.all) {
        expect(weeklyScheduleMatchesPreset(const {}, p), isFalse);
      }
    });
  });
}
