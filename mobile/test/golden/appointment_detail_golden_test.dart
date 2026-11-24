import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/screens/appointments/appointment_detail_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';

class _MockAppointments extends Mock implements AppointmentServiceInterface {}

/// The appointment detail, complete (docs/design/appointment-detail-complete.md,
/// decisions 194–203) — the audit's gap 23 named it among the screens with no
/// picture at all. Three states, each at the floor (360) and at 200 % text:
/// the screen a client opens on the day, the one after the salon never
/// answered, and a finished visit at a salon that has since stopped.
void main() {
  group('goldens', () {
    final appointments = _MockAppointments();
    final now = DateTime.utc(2026, 11, 23, 12);

    setUpAll(() async {
      await loadRealFonts();
      await initializeDateFormatting('fr_FR', null);
      serviceLocator.appointmentService = appointments;
      serviceLocator.localityService = MockLocalityService();
    });

    setUp(() => AppClock.freeze(now));
    tearDown(AppClock.restore);

    Appointment appt({
      required AppointmentStatus status,
      required Duration from,
      String? providerStatus,
      String? photo = 'asset:assets/images/providers/barber_shop_pro_photo.png',
      double deposit = 0,
      String? proof,
    }) => Appointment(
      id: 'a1',
      userId: 'u1',
      providerId: const SalonId('p1'),
      serviceIds: const ['s1', 's2'],
      artistId: 'a1',
      appointmentDate: DateTime.utc(2026, 11, 23, 9).add(from),
      durationMinutes: 150,
      status: status,
      totalPrice: 25000,
      depositAmount: deposit,
      balanceDue: 25000 - deposit,
      depositScreenshotUrl: proof,
      depositMobileMoneyOperator: 'wave',
      depositMobileMoneyNumber: '+2250700000000',
      createdAt: DateTime.utc(2026),
      providerName: 'Beauté Divine',
      providerStatus: providerStatus,
      providerPhone: '+2250711223344',
      providerWhatsapp: '+2250711223355',
      providerAddress: 'Rue des Jardins, Deux Plateaux',
      providerCountryCode: 'CI',
      providerTimezone: 'Africa/Abidjan',
      providerCurrency: 'XOF',
      providerLatitude: 5.3599,
      providerLongitude: -3.9871,
      providerCommune: 'Cocody',
      providerCity: 'Abidjan',
      providerPhotoUrl: photo,
      serviceNames: const ['Tresses', 'Soin du visage'],
      artistName: 'Awa',
      notes: 'Cheveux fragiles, prévoir un soin.',
    );

    Future<void> shoot(
      WidgetTester tester,
      Appointment a,
      String name, {
      double scale = 1,
    }) async {
      when(
        () => appointments.getAppointmentById('a1'),
      ).thenAnswer((_) async => ApiResponse.success(a));
      goldenSurface(tester, size: Size(360, scale > 1 ? 3400 : 1700));
      if (scale > 1) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(create: (_) => LocalityProvider()),
          ],
          child: goldenApp(
            home: const AppointmentDetailScreen(appointmentId: 'a1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // The locality tree lands behind a mock latency; the picture waits.
      await tester.pump(const Duration(seconds: 5));
      // The cover decodes off real time, which a fake-clock pump does not
      // give: without this the frame is drawn empty.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(
        find.text('Le rendez-vous'),
        findsOneWidget,
        reason: 'the booking must be drawn, not the loader or an error',
      );
      await expectGolden(tester, name);
    }

    for (final scale in [1.0, 2.0]) {
      final suffix = scale > 1 ? '_w360_x2' : '_w360';

      testWidgets('upcoming, pending, a deposit to send — x$scale', (
        tester,
      ) async {
        await shoot(
          tester,
          appt(
            status: AppointmentStatus.pending,
            from: const Duration(days: 2),
            deposit: 5000,
          ),
          'appointment_detail_upcoming$suffix',
          scale: scale,
        );
      });

      testWidgets('past, never confirmed, a proof sent — x$scale', (
        tester,
      ) async {
        await shoot(
          tester,
          appt(
            status: AppointmentStatus.pending,
            from: const Duration(days: -2),
            deposit: 5000,
            proof: 'deposit/u1/proof.jpg',
          ),
          'appointment_detail_unconfirmed$suffix',
          scale: scale,
        );
      });

      testWidgets('completed, at a salon that stopped — x$scale', (
        tester,
      ) async {
        await shoot(
          tester,
          // The server sends no photo for a stopped salon (decision 194).
          appt(
            status: AppointmentStatus.completed,
            from: const Duration(days: -10),
            providerStatus: 'suspended',
            photo: null,
          ),
          'appointment_detail_completed_stopped$suffix',
          scale: scale,
        );
      });
    }
  }, skip: kGoldensSkip);
}
