import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/widgets/booking/slot_picker.dart';
import 'package:provider/provider.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/surface.dart';

class _MockAppointmentService extends Mock
    implements AppointmentServiceInterface {}

/// What `SlotPicker` guarantees (A14c §19).
///
/// **The two implementations it replaces disagreed, and only one was right.**
/// The booking hub had an in-flight request guard; `date_time_selection_screen`
/// had none and `setState`d whatever came back. Neither had an error state —
/// both rendered « Aucun créneau disponible » for a dead network. This file
/// pins all three.
void main() {
  late _MockAppointmentService service;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    service = _MockAppointmentService();
    serviceLocator.appointmentService = service;
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
  });

  setUp(() => reset(service));

  void answerWith(Future<ApiResponse<List<DateTime>>> Function(Invocation) f) =>
      when(
        () => service.getAvailableTimeSlots(
          providerId: any(named: 'providerId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          artistId: any(named: 'artistId'),
          durationMinutes: any(named: 'durationMinutes'),
        ),
      ).thenAnswer(f);

  Future<void> pump(
    WidgetTester tester, {
    DateTime? date,
    Object? refreshSignal,
    double scale = 1,
  }) async {
    pinSurface(tester, size: kFloorPhone, scale: scale);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          // The hint's country label resolves through a `Selector` inside the
          // picker, so the tree needs the locality provider — the same real
          // dependency the booking hub's layout subject gained.
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SlotPicker(
              providerId: 'provider1',
              selectedDate: date ?? DateTime(2026, 3, 11),
              refreshSignal: refreshSignal,
              onDateChanged: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  group('the fourth state — « we could not ask » is not « nothing is free »', () {
    testWidgets('a failure says so, and offers a retry', (tester) async {
      answerWith((_) async => ApiResponse<List<DateTime>>.error('Hors ligne'));
      await pump(tester);

      expect(find.text('Hors ligne'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(
        find.text('Aucun créneau disponible'),
        findsNothing,
        reason:
            'the whole point: a dead network must not tell the user the salon '
            'is full. Both screens this replaces said exactly that.',
      );
    });

    testWidgets('a genuinely empty day says THAT, with no retry', (
      tester,
    ) async {
      answerWith((_) async => ApiResponse<List<DateTime>>.success(const []));
      await pump(tester);

      expect(find.text('Aucun créneau disponible'), findsOneWidget);
      expect(
        find.text('Réessayer'),
        findsNothing,
        reason:
            'the other direction — a full Saturday is not a failure, and '
            'offering a retry would imply the app got it wrong',
      );
    });

    testWidgets('the error state survives 200% text', (tester) async {
      answerWith((_) async => ApiResponse<List<DateTime>>.error('Hors ligne'));
      await pump(tester, scale: 2);

      // The first draft put the sentence and « Réessayer » on one `Row` with an
      // `Expanded` — the §13.3 shape that clips. The action sits under the
      // sentence now, and both grow.
      expectNoVerticalClip(tester, context: 'the slot picker error at 2×');
      expect(tester.takeException(), isNull);
    });
  });

  group('the in-flight guard', () {
    testWidgets('a stale response never paints over a newer one', (
      tester,
    ) async {
      // Request 1 is slow and answers 09:00. Request 2 is fast and answers
      // 15:00. Without the token the slow one lands last and wins.
      var call = 0;
      answerWith((_) async {
        call++;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return ApiResponse.success([DateTime.utc(2026, 3, 11, 9)]);
        }
        return ApiResponse.success([DateTime.utc(2026, 3, 12, 15)]);
      });

      // **The overlap has to be real, and the first draft of this test did not
      // create one.** It called `pump()` (which settles 1200ms) before changing
      // the day, so request 1 had already landed — the guard was never
      // exercised and the test passed with it deleted. Proven by mutation.
      //
      // So: pump ONE frame to let the post-frame `_load` fire, then swap the
      // date while request 1 is still in the air.
      final provider = AppointmentProvider();
      Widget tree(DateTime date) => wrapApp(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SlotPicker(
              providerId: 'provider1',
              selectedDate: date,
              onDateChanged: (_) {},
              onSlotSelected: (_) {},
            ),
          ),
        ),
      );

      pinSurface(tester, size: kFloorPhone);
      await tester.pumpWidget(tree(DateTime(2026, 3, 11)));
      await tester.pump(); // the post-frame callback → request 1 starts
      expect(call, 1, reason: 'request 1 must be in flight, not finished');

      await tester.pumpWidget(tree(DateTime(2026, 3, 12)));
      await tester.pump(); // didUpdateWidget → request 2 starts
      expect(call, 2, reason: 'both requests overlap — that is the point');

      await settleMocks(tester, rounds: 6);

      expect(
        find.text('15:00'),
        findsOneWidget,
        reason: 'the newest request wins',
      );
      expect(
        find.text('09:00'),
        findsNothing,
        reason:
            'the slow FIRST response must be dropped. `date_time_selection_'
            'screen` had no guard at all, so rapid day taps could paint one '
            'day\'s slots under another day\'s heading.',
      );
    });
  });

  group('refreshSignal', () {
    testWidgets('bumping it re-asks with identical inputs', (tester) async {
      var calls = 0;
      answerWith((_) async {
        calls++;
        return ApiResponse.success(const []);
      });

      await pump(tester, refreshSignal: 1);
      expect(calls, 1);

      await pump(tester, refreshSignal: 2);
      await settleMocks(tester, rounds: 3);

      expect(
        calls,
        greaterThan(1),
        reason:
            'the hub re-loaded whenever the « Date et heure » card was '
            'reopened, because slots go stale while a user decides. A '
            'didUpdateWidget watching only the query inputs would see no '
            'change and silently drop that refresh.',
      );
    });
  });
}
