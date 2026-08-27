import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/constants/booking_horizons.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_availability_provider.dart';
import 'package:myweli/screens/provider/availability/availability_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// The « Horaires » models + « Copier sur les autres jours », end to end
/// (docs/design/availability-presets.md §8) — the harness is
/// `availability_blocked_dates_test.dart`'s, and for the same reason: what
/// matters is what the SERVICE receives, not what a helper returns.
void main() {
  late _MockProService service;

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    service = _MockProService();
    serviceLocator.proService = service;
    registerFallbackValue(
      const Availability(providerId: 'p', weeklySchedule: {}, blockedDates: []),
    );
  });

  setUp(() => reset(service));

  /// A slot at the salon's wall clock — the seeded salon is Africa/Abidjan,
  /// the default zone, so `tz: null` matches what the screen writes.
  TimeSlot slotAt(int startHour, int endHour) {
    final t = salonToday();
    DateTime at(int h) => salonDateTime(t.year, t.month, t.day, hour: h);
    return TimeSlot(
      startTime: at(startHour),
      endTime: at(endHour),
      isAvailable: true,
    );
  }

  Future<void> pumpWith(
    WidgetTester tester,
    Map<int, List<TimeSlot>> schedule,
  ) async {
    final auth = await signInPro(tester);
    when(() => service.getProviderAvailability(any())).thenAnswer(
      (_) async => ApiResponse.success(
        Availability(
          providerId: 'provider1',
          weeklySchedule: schedule,
          blockedDates: const [],
        ),
      ),
    );
    when(() => service.updateAvailability(any(), any())).thenAnswer(
      (i) async =>
          ApiResponse.success(i.positionalArguments[1] as Availability),
    );

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProAvailabilityProvider()),
        ],
        home: const AvailabilityScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  /// The models sit under three cards — scrolled to, never tapped blind.
  Future<void> scrollToChips(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Modèles'), 300);
    await tester.pump();
  }

  Availability capturedWrite() =>
      verify(
            () => service.updateAvailability('provider1', captureAny()),
          ).captured.single
          as Availability;

  TimeOfDay tod(DateTime t) => TimeOfDay.fromDateTime(t);

  testWidgets('the créneaux line and the three model chips render', (
    tester,
  ) async {
    await pumpWith(tester, const {});
    await scrollToChips(tester);
    expect(find.text(kCreneauxCopy), findsOneWidget);
    for (final p in WeeklySchedulePresets.all) {
      expect(find.text(p.label), findsOneWidget);
    }
  });

  testWidgets('an empty week applies a model directly — the WHOLE week in one '
      'write, off days written EMPTY', (tester) async {
    await pumpWith(tester, const {});
    await scrollToChips(tester);

    await tester.tap(find.text('Mar–Sam · 9h–18h'));
    await settleMocks(tester);
    // Nothing to lose → no dialog to cry wolf.
    expect(find.text('Appliquer ce modèle ?'), findsNothing);

    final sent = capturedWrite();
    for (final day in [1, 2, 3, 4, 5]) {
      final slots = sent.weeklySchedule[day]!;
      expect(slots, hasLength(1), reason: 'day $day');
      expect(tod(slots.single.startTime), const TimeOfDay(hour: 9, minute: 0));
      expect(tod(slots.single.endTime), const TimeOfDay(hour: 18, minute: 0));
    }
    for (final day in [0, 6]) {
      expect(
        sent.weeklySchedule[day],
        isEmpty,
        reason:
            'a model is the whole week — day $day left unwritten would keep '
            'stale hours under a lit chip',
      );
    }
    // The mock echoes the write back, so the chip now tells the truth.
    await scrollToChips(tester);
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Mar–Sam · 9h–18h'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('configured hours pass a confirm — and cancel writes nothing', (
    tester,
  ) async {
    await pumpWith(tester, {
      0: [slotAt(10, 12)],
    });
    await scrollToChips(tester);

    await tester.tap(find.text('Lun–Sam · 8h–17h'));
    await settleMocks(tester);
    expect(find.text('Appliquer ce modèle ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await settleMocks(tester);
    verifyNever(() => service.updateAvailability(any(), any()));

    await tester.tap(find.text('Lun–Sam · 8h–17h'));
    await settleMocks(tester);
    await tester.tap(find.text('Appliquer'));
    await settleMocks(tester);

    final sent = capturedWrite();
    expect(sent.weeklySchedule[0], hasLength(1));
    expect(
      tod(sent.weeklySchedule[0]!.single.startTime),
      const TimeOfDay(hour: 8, minute: 0),
    );
    expect(sent.weeklySchedule[6], isEmpty);
  });

  testWidgets('« Copier sur les autres jours » writes the EDITED day — '
      'multi-range included — onto all seven, in ONE write', (tester) async {
    await pumpWith(tester, {
      0: [slotAt(9, 12), slotAt(14, 18)],
    });

    // Into Lundi's editor. `widgetWithText(ListTile, …)` because the Pauses
    // editor above the day cards also prints every day name — the day CARDS
    // are the only ListTiles carrying one.
    final lundi = find.widgetWithText(ListTile, 'Lundi');
    await tester.scrollUntilVisible(lundi, 300);
    await tester.tap(
      find.descendant(of: lundi, matching: find.byTooltip('Modifier')),
    );
    await settleMocks(tester);

    final copy = find.text('Copier sur les autres jours');
    // `ensureVisible`, not `scrollUntilVisible`: the pushed route keeps the
    // availability screen mounted underneath, so `find.byType(Scrollable)`
    // resolves two scrollables and the default-scrollable variant throws.
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await settleMocks(tester);
    expect(find.text('Copier sur les autres jours ?'), findsOneWidget);
    await tester.tap(find.text('Copier'));
    await settleMocks(tester);

    final sent = capturedWrite();
    for (var day = 0; day < 7; day++) {
      final slots = sent.weeklySchedule[day]!;
      expect(slots, hasLength(2), reason: 'day $day takes BOTH ranges');
      expect(tod(slots.first.startTime), const TimeOfDay(hour: 9, minute: 0));
      expect(tod(slots.last.endTime), const TimeOfDay(hour: 18, minute: 0));
    }
    // Saved → snackbar → popped back to the availability screen.
    expect(find.text('Horaires copiés sur tous les jours'), findsOneWidget);
    expect(find.text('Horaires de travail'), findsOneWidget);
  });

  testWidgets('a CLOSED day does not offer itself as the model', (
    tester,
  ) async {
    await pumpWith(tester, const {});
    final mardi = find.widgetWithText(ListTile, 'Mardi');
    await tester.scrollUntilVisible(mardi, 300);
    await tester.tap(
      find.descendant(of: mardi, matching: find.byTooltip('Modifier')),
    );
    await settleMocks(tester);
    expect(find.text('Aucun créneau horaire'), findsOneWidget);
    expect(
      find.text('Copier sur les autres jours'),
      findsNothing,
      reason: 'copying « fermé » onto the whole week is a trap, not a feature',
    );
  });
}
