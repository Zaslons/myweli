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
import 'package:myweli/widgets/common/app_button.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockAppointments extends Mock implements AppointmentServiceInterface {}

/// The appointment detail, complete (docs/design/appointment-detail-complete.md
/// §2, decisions 194–203): every section shown only with something to show,
/// each way to reach the salon only when it works, one primary per state, and
/// only what MyWeli knows.
void main() {
  final appointments = _MockAppointments();
  final now = DateTime.utc(2026, 11, 23, 12);

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.appointmentService = appointments;
    serviceLocator.localityService = MockLocalityService();
  });

  setUp(() => AppClock.freeze(now));
  tearDown(AppClock.restore);

  Appointment appt({
    AppointmentStatus status = AppointmentStatus.confirmed,
    Duration from = const Duration(days: 2),
    String? providerStatus,
    String? phone = '+2250711223344',
    String? whatsapp = '+2250711223355',
    double? lat = 5.3599,
    double? lng = -3.9871,
    String? address = 'Rue des Jardins',
    String? commune = 'Cocody',
    String? city = 'Abidjan',
    String? photo = 'asset:assets/images/providers/barber_shop_pro_photo.png',
    List<String> serviceNames = const ['Tresses', 'Soin du visage'],
    int? durationMinutes = 90,
    double deposit = 0,
    String? proof,
    String? notes,
  }) => Appointment(
    id: 'a1',
    userId: 'u1',
    providerId: const SalonId('p1'),
    serviceIds: const ['s1', 's2'],
    artistId: 'a1',
    appointmentDate: DateTime.utc(2026, 11, 23, 9).add(from),
    durationMinutes: durationMinutes,
    status: status,
    totalPrice: 20000,
    depositAmount: deposit,
    balanceDue: 20000 - deposit,
    depositScreenshotUrl: proof,
    notes: notes,
    createdAt: DateTime.utc(2026),
    providerName: 'Beauté Divine',
    providerStatus: providerStatus,
    providerPhone: phone,
    providerWhatsapp: whatsapp,
    providerAddress: address,
    providerCountryCode: 'CI',
    providerTimezone: 'Africa/Abidjan',
    providerLatitude: lat,
    providerLongitude: lng,
    providerCommune: commune,
    providerCity: city,
    providerPhotoUrl: photo,
    serviceNames: serviceNames,
    artistName: 'Awa',
  );

  Future<void> pump(
    WidgetTester tester,
    Appointment a, {
    TransitionBuilder? builder,
  }) async {
    when(
      () => appointments.getAppointmentById('a1'),
    ).thenAnswer((_) async => ApiResponse.success(a));
    // A fresh tree for each booking. Pumping the same host again would keep
    // the provider and the screen's state — and the FIRST booking — so a loop
    // over states would check only its first one.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        home: const AppointmentDetailScreen(appointmentId: 'a1'),
        builder: builder,
      ),
    );
    await tester.pump();
    await tester.pump();
    // The locality tree loads behind a mock latency: let it land, so no timer
    // outlives the test (appointment_detail_stopped_test does the same).
    await tester.pump(const Duration(seconds: 5));
  }

  Finder button(String text) => find.widgetWithText(AppButton, text);

  testWidgets('the title is « Rendez-vous »', (tester) async {
    await pump(tester, appt());
    expect(find.text('Rendez-vous'), findsOneWidget);
    expect(find.text('Détails'), findsNothing);
  });

  group('the header (§2.3)', () {
    testWidgets('the name is a level-1 heading; the chip and its sentence', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, appt(status: AppointmentStatus.pending));
      expect(
        tester
            .getSemantics(find.text('Beauté Divine'))
            .getSemanticsData()
            .headingLevel,
        1,
      );
      expect(find.text('En attente'), findsOneWidget);
      expect(
        find.text('Le salon doit encore confirmer ce rendez-vous.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a past booking nobody confirmed says so, in its words', (
      tester,
    ) async {
      await pump(
        tester,
        appt(status: AppointmentStatus.pending, from: const Duration(days: -2)),
      );
      expect(find.text('Non confirmé'), findsOneWidget);
      expect(
        find.text('Le salon n’a pas confirmé ce rendez-vous avant son heure.'),
        findsOneWidget,
      );
    });

    testWidgets('a confirmed booking has no sentence', (tester) async {
      await pump(tester, appt());
      expect(find.textContaining('Le salon doit'), findsNothing);
      expect(find.textContaining('Le salon n’a pas'), findsNothing);
    });
  });

  group('the sections (§2.2)', () {
    testWidgets('each title is announced as a level-2 heading', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, appt(notes: 'Cheveux fragiles'));
      for (final title in [
        'Le rendez-vous',
        'Prestations',
        'Le salon',
        'Paiement',
        'Notes',
      ]) {
        expect(
          tester.getSemantics(find.text(title)).getSemanticsData().headingLevel,
          2,
          reason: title,
        );
      }
      handle.dispose();
    });

    testWidgets('the start and the end, in the salon’s time', (tester) async {
      await pump(tester, appt());
      expect(find.text('09:00 – 10:30'), findsOneWidget);
      expect(find.text('mercredi 25 novembre 2026'), findsOneWidget);
    });

    testWidgets('no duration: the start alone', (tester) async {
      await pump(tester, appt(durationMinutes: null));
      expect(find.text('09:00'), findsOneWidget);
      expect(find.textContaining('–'), findsNothing);
    });

    testWidgets('one line per service', (tester) async {
      await pump(tester, appt());
      expect(find.text('Tresses'), findsOneWidget);
      expect(find.text('Soin du visage'), findsOneWidget);
      expect(find.text('Tresses, Soin du visage'), findsNothing);
    });

    testWidgets('a section with nothing to show is left out', (tester) async {
      await pump(
        tester,
        appt(
          serviceNames: const [],
          phone: null,
          whatsapp: null,
          lat: null,
          lng: null,
          address: null,
          commune: null,
          city: null,
          providerStatus: 'suspended',
        ),
      );
      expect(find.text('Prestations'), findsNothing);
      expect(find.text('Notes'), findsNothing);
      // No address, no position, no number, and no page to open: no section.
      expect(find.text('Le salon'), findsNothing);
      // The rest are always there.
      expect(find.text('Le rendez-vous'), findsOneWidget);
      expect(find.text('Paiement'), findsOneWidget);
    });
  });

  group('« Le salon » (§2.6)', () {
    testWidgets('the address, then « commune, ville »', (tester) async {
      await pump(tester, appt());
      expect(find.text('Rue des Jardins'), findsOneWidget);
      expect(find.text('Cocody, Abidjan'), findsOneWidget);
    });

    testWidgets('every way to reach it, when each works', (tester) async {
      await pump(tester, appt());
      for (final b in ['Itinéraire', 'Appeler', 'WhatsApp', 'Voir le salon']) {
        expect(button(b), findsOneWidget, reason: b);
      }
    });

    testWidgets('« Itinéraire » needs a position', (tester) async {
      await pump(tester, appt(lat: null, lng: null));
      expect(button('Itinéraire'), findsNothing);
      expect(find.text('Rue des Jardins'), findsOneWidget);
    });

    testWidgets('no number, no « Appeler » or « WhatsApp » to fail after the '
        'tap', (tester) async {
      await pump(tester, appt(phone: null, whatsapp: ''));
      expect(button('Appeler'), findsNothing);
      expect(button('WhatsApp'), findsNothing);
    });

    testWidgets('a stopped salon keeps the way there, not its page', (
      tester,
    ) async {
      await pump(tester, appt(providerStatus: 'suspended', photo: null));
      expect(button('Itinéraire'), findsOneWidget);
      expect(button('Appeler'), findsOneWidget);
      expect(button('Voir le salon'), findsNothing);
      expect(button('Reporter'), findsNothing);
      expect(button('Annuler le rendez-vous'), findsOneWidget);
    });
  });

  group('« Paiement » (§2.7)', () {
    testWidgets('a deposit to send, while the booking is ahead', (
      tester,
    ) async {
      await pump(
        tester,
        appt(status: AppointmentStatus.pending, deposit: 5000),
      );
      expect(find.text('Acompte à envoyer'), findsOneWidget);
      expect(button('Envoyer l’acompte'), findsOneWidget);
      expect(find.text('Solde à régler au salon'), findsOneWidget);
    });

    testWidgets('no « Envoyer l’acompte » once the time has passed', (
      tester,
    ) async {
      await pump(
        tester,
        appt(
          status: AppointmentStatus.pending,
          from: const Duration(days: -2),
          deposit: 5000,
        ),
      );
      expect(button('Envoyer l’acompte'), findsNothing);
      expect(find.text('Aucun justificatif envoyé'), findsOneWidget);
    });

    testWidgets('a confirmed booking never says « Acompte confirmé »', (
      tester,
    ) async {
      await pump(tester, appt(deposit: 5000));
      expect(find.text('Acompte confirmé'), findsNothing);
      expect(find.text('Acompte'), findsOneWidget);
    });

    testWidgets('no balance on a cancelled booking', (tester) async {
      await pump(
        tester,
        appt(
          status: AppointmentStatus.cancelled,
          deposit: 5000,
          proof: 'deposit/u1/p.jpg',
        ),
      );
      expect(find.text('Solde à régler au salon'), findsNothing);
      expect(
        find.text(
          'Voyez directement avec le salon : MyWeli ne détient aucun '
          'acompte.',
        ),
        findsOneWidget,
      );
      expect(button('Voir ma capture'), findsOneWidget);
    });
  });

  group('the actions (§2.8)', () {
    int primaries(WidgetTester tester) => tester
        .widgetList<AppButton>(find.byType(AppButton))
        .where((b) => b.type == AppButtonType.primary)
        .length;

    testWidgets('« Réserver à nouveau » after a past « Confirmé »', (
      tester,
    ) async {
      await pump(tester, appt(from: const Duration(days: -2)));
      expect(button('Réserver à nouveau'), findsOneWidget);
    });

    testWidgets('never on an upcoming booking, nor at a stopped salon', (
      tester,
    ) async {
      await pump(tester, appt());
      expect(button('Réserver à nouveau'), findsNothing);
      await pump(
        tester,
        appt(
          status: AppointmentStatus.completed,
          from: const Duration(days: -2),
          providerStatus: 'suspended',
          photo: null,
        ),
      );
      expect(
        find.text('Ce salon ne prend plus de rendez-vous sur MyWeli.'),
        findsOneWidget,
        reason: 'the stopped booking is the one drawn',
      );
      expect(button('Réserver à nouveau'), findsNothing);
    });

    testWidgets('one primary per state', (tester) async {
      final states = <Appointment>[
        appt(),
        appt(status: AppointmentStatus.pending, deposit: 5000),
        appt(
          status: AppointmentStatus.completed,
          from: const Duration(days: -2),
        ),
        appt(
          status: AppointmentStatus.cancelled,
          from: const Duration(days: -1),
        ),
        appt(status: AppointmentStatus.noShow, from: const Duration(days: -1)),
      ];
      for (final a in states) {
        await pump(tester, a);
        // Proof the state drawn is this one, not the previous.
        expect(
          find.text(a.status == AppointmentStatus.noShow ? 'Absent' : 'Total'),
          findsWidgets,
        );
        expect(primaries(tester), lessThanOrEqualTo(1), reason: '$a');
      }
      // The deposit to send is the one primary: « Reporter » steps back.
      await pump(
        tester,
        appt(status: AppointmentStatus.pending, deposit: 5000),
      );
      expect(
        tester.widget<AppButton>(button('Reporter')).type,
        AppButtonType.secondary,
      );
    });
  });

  testWidgets('200 % text at 320 dp: nothing overflows', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      appt(
        status: AppointmentStatus.pending,
        deposit: 5000,
        notes: 'Cheveux fragiles, prévoir un soin.',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Le rendez-vous'), findsOneWidget);
  });
}
