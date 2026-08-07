import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/booking_duration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/screens/appointments/reschedule_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/booking/slot_picker.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';

class _MockAppointmentService extends Mock
    implements AppointmentServiceInterface {}

/// Consumer reschedule (A14c §19.2) — the flow that replaces
/// `date_time_selection_screen`.
///
/// **The screen it replaces had no test of any kind**, and shipped a live
/// defect the whole time: it was pushed without `durationMinutes`, so the
/// target recomputed the booking's length from the salon's *current* catalogue
/// and a freshly-defaulted hair-length variant. A three-hour braid could be
/// offered thirty-minute slots.
void main() {
  late _MockAppointmentService appointments;
  late models.Provider salon;

  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    appointments = _MockAppointmentService();
    serviceLocator.appointmentService = appointments;
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
  });

  tearDownAll(AppClock.restore);

  setUp(() {
    freezeClock(kFixedNow);
    reset(appointments);
    // The real fixture, not a hand-built one: the screen must work against the
    // shape the app actually receives.
    salon = MockData.providers.first;
  });

  /// The booking as the SERVER hands it over — enriched.
  ///
  /// The screen used to be given the whole salon object because
  /// `durationMinutes` could be null on a consumer payload. The server
  /// backfills it from the catalogue that priced the booking now (Decision C),
  /// so this helper does what `withProviderFacts` does: resolve the ids
  /// against the same fixture and stamp the result.
  Appointment bookingOf(models.Provider p, {required List<String> serviceIds}) {
    final chosen = p.services.where((s) => serviceIds.contains(s.id)).toList();
    return Appointment(
      id: 'a1',
      userId: 'u1',
      providerId: p.id,
      serviceIds: serviceIds,
      appointmentDate: kFixedNow.add(const Duration(days: 2, hours: 4)),
      status: AppointmentStatus.confirmed,
      totalPrice: 20000,
      depositAmount: 6000,
      balanceDue: 14000,
      createdAt: kFixedNow,
      providerTimezone: p.timezone,
      providerName: p.name,
      providerCountryCode: p.countryCode,
      serviceNames: [for (final s in chosen) s.name],
      durationMinutes: chosen.isEmpty
          ? null
          : totalBookingDuration(chosen, null),
      providerBookingHorizonDays: p.availability.bookingHorizonDays,
      providerMinimumNoticeMinutes: p.availability.minimumNoticeMinutes,
    );
  }

  Future<void> pump(WidgetTester tester, Appointment a) async {
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: RescheduleScreen(appointment: a),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  testWidgets('it says WHAT is being moved, and when it currently is', (
    tester,
  ) async {
    when(
      () => appointments.getAvailableTimeSlots(
        providerId: any(named: 'providerId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        artistId: any(named: 'artistId'),
        durationMinutes: any(named: 'durationMinutes'),
      ),
    ).thenAnswer((_) async => ApiResponse.success(const []));

    final service = salon.services.first;
    await pump(tester, bookingOf(salon, serviceIds: [service.id]));

    // The screen this replaces was a bare picker with no answer to "which
    // booking is this?" — the salon load that makes the duration correct pays
    // for this context at no extra cost.
    expect(find.text(salon.name), findsOneWidget);
    expect(find.textContaining(service.name), findsWidgets);
    expect(find.textContaining('Actuellement :'), findsOneWidget);
  });

  testWidgets('the slot query carries the BOOKING\'s duration, not a default', (
    tester,
  ) async {
    int? asked;
    when(
      () => appointments.getAvailableTimeSlots(
        providerId: any(named: 'providerId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        artistId: any(named: 'artistId'),
        durationMinutes: any(named: 'durationMinutes'),
      ),
    ).thenAnswer((inv) async {
      asked = inv.namedArguments[#durationMinutes] as int?;
      return ApiResponse.success(const []);
    });

    // Pick the salon's LONGEST service, so a wrong answer cannot coincide with
    // the 30-minute default by luck.
    final longest = salon.services.reduce(
      (a, b) => a.durationMinutes >= b.durationMinutes ? a : b,
    );
    final expected = totalBookingDuration([longest], null);

    await pump(tester, bookingOf(salon, serviceIds: [longest.id]));

    expect(
      asked,
      expected,
      reason:
          'the live defect this screen closes: the old flow passed no duration '
          'at all, so a $expected-minute booking was offered slots spaced for '
          '$kDefaultSlotDuration. Resolved from the SALON\'s catalogue, because '
          'Appointment.durationMinutes is a provider-enriched field that can be '
          'null on a consumer payload.',
    );
    expect(
      expected,
      isNot(kDefaultSlotDuration),
      reason:
          'the fixture must not make this assertion vacuous — if the longest '
          'service happened to be 30 minutes the test would pass either way',
    );
  });

  testWidgets('choosing is not submitting', (tester) async {
    final slot = kFixedNow.add(const Duration(days: 2, hours: 6));
    when(
      () => appointments.getAvailableTimeSlots(
        providerId: any(named: 'providerId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        artistId: any(named: 'artistId'),
        durationMinutes: any(named: 'durationMinutes'),
      ),
    ).thenAnswer((_) async => ApiResponse.success([slot]));

    await pump(tester, bookingOf(salon, serviceIds: [salon.services.first.id]));

    // **The flow this replaces popped the instant a time was tapped.** Moving a
    // booking is consequential; the button states what will happen and is inert
    // until there is something to state.
    expect(find.text('Choisissez un créneau'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).first);
    await settleMocks(tester);

    expect(find.text('Choisissez un créneau'), findsNothing);
    expect(find.textContaining('Reporter à'), findsOneWidget);
  });
}
