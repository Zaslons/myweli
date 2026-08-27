import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/screens/provider/appointments/pro_manual_booking_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// The manual-booking PHONE boundary (plan « fix/manual-booking-phone »).
///
/// Every earlier test fed a pre-formed E.164 string to the provider, so the
/// actual defect lived one layer up and was invisible: the screen's field was
/// a self-contradiction — a « +225 … » hint over a digits-only formatter,
/// judged by a 10-local-digits rule, sent raw to a server that requires `+`.
/// A phoned manual booking could NEVER succeed. These tests type into the
/// real widget and assert what the SERVICE receives.
void main() {
  late _MockProService service;

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    service = _MockProService();
    serviceLocator.proService = service;
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
  });

  Appointment created() => Appointment(
    id: 'm1',
    userId: 'manual',
    providerId: 'provider1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2027, 1, 15, 14, 30),
    status: AppointmentStatus.confirmed,
    totalPrice: 15000,
    createdAt: DateTime(2026),
  );

  setUp(() {
    reset(service);
    when(() => service.getProviderServices(any())).thenAnswer(
      (_) async => ApiResponse.success([
        Service.fromJson({
          'id': 's1',
          'name': 'Tresses',
          'description': '',
          'price': 15000,
          'durationMinutes': 120,
          'providerId': 'provider1',
          'active': true,
        }),
      ]),
    );
    when(
      () => service.createManualBooking(
        providerId: any(named: 'providerId'),
        serviceIds: any(named: 'serviceIds'),
        appointmentDateTime: any(named: 'appointmentDateTime'),
        clientName: any(named: 'clientName'),
        clientPhone: any(named: 'clientPhone'),
        notes: any(named: 'notes'),
        artistId: any(named: 'artistId'),
        sendSmsInvite: any(named: 'sendSmsInvite'),
      ),
    ).thenAnswer((_) async => ApiResponse.success(created()));
  });

  Future<void> pump(WidgetTester tester, {String? initialClientPhone}) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProServiceProvider()),
          ChangeNotifierProvider(create: (_) => ProAppointmentProvider()),
        ],
        // The grid-cell entry (a fixed future instant), so the date/time
        // pickers stay out of the way of what this file is about.
        home: ProManualBookingScreen(
          initialDateTime: DateTime(2027, 1, 15, 14, 30),
          initialClientPhone: initialClientPhone,
        ),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  Finder phoneInput() => find.descendant(
    of: find.byType(IntlPhoneField),
    matching: find.byType(TextFormField),
  );

  Future<void> submit(WidgetTester tester) async {
    // The body is a ListView, which CULLS off-screen children — the button
    // does not exist in the tree until scrolled to (ensureVisible cannot).
    final btn = find.text('Créer le rendez-vous');
    // scrollable pinned to the ListView: every EditableText carries its own
    // Scrollable, so the default single-scrollable lookup throws here.
    await tester.scrollUntilVisible(
      btn,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(btn);
    await settleMocks(tester);
  }

  String? capturedPhone() =>
      verify(
            () => service.createManualBooking(
              providerId: any(named: 'providerId'),
              serviceIds: any(named: 'serviceIds'),
              appointmentDateTime: any(named: 'appointmentDateTime'),
              clientName: any(named: 'clientName'),
              clientPhone: captureAny(named: 'clientPhone'),
              notes: any(named: 'notes'),
              artistId: any(named: 'artistId'),
              sendSmsInvite: any(named: 'sendSmsInvite'),
            ),
          ).captured.single
          as String?;

  testWidgets('a locally-typed number reaches the service as E.164', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Tresses'));
    await tester.pump();

    // What a receptionist types: the national ten digits. The field owns the
    // +225 — the old formatter made the `+` physically untypable.
    await tester.enterText(phoneInput(), '0708091011');
    await tester.pump();
    await submit(tester);

    expect(capturedPhone(), '+2250708091011');
    expect(find.text('Rendez-vous créé'), findsOneWidget);
  });

  testWidgets('the client-card prefill (stored E.164) renders and submits '
      'unchanged', (tester) async {
    // The old local-10-digits rule rejected the app's OWN stored numbers:
    // +225… strips to 13 digits ≠ 10, so rebooking a client from their card
    // failed client-side.
    await pump(tester, initialClientPhone: '+2250708091011');

    // The FIELD must show the number, not merely the state carry it: a
    // dropped initialValue with the state still seeded submits a number the
    // receptionist cannot see — the payload assertion alone missed exactly
    // that mutant.
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(IntlPhoneField),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text.replaceAll(' ', ''), '0708091011');

    await tester.tap(find.text('Tresses'));
    await tester.pump();
    await submit(tester);

    expect(capturedPhone(), '+2250708091011');
  });

  testWidgets('an impossible number is refused AT THE FIELD — nothing sent', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Tresses'));
    await tester.pump();

    await tester.enterText(phoneInput(), '12');
    await tester.pump();
    await submit(tester);

    expect(
      find.text('Saisissez un numéro de téléphone valide.'),
      findsOneWidget,
    );
    verifyNever(
      () => service.createManualBooking(
        providerId: any(named: 'providerId'),
        serviceIds: any(named: 'serviceIds'),
        appointmentDateTime: any(named: 'appointmentDateTime'),
        clientName: any(named: 'clientName'),
        clientPhone: any(named: 'clientPhone'),
        notes: any(named: 'notes'),
        artistId: any(named: 'artistId'),
        sendSmsInvite: any(named: 'sendSmsInvite'),
      ),
    );
  });

  testWidgets('walk-in stays phoneless — the checkbox bypasses the field', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Tresses'));
    await tester.pump();
    final walkIn = find.text('Client sans numéro (walk-in)');
    await tester.ensureVisible(walkIn);
    await tester.tap(walkIn);
    await tester.pump();
    await submit(tester);

    expect(capturedPhone(), isNull);
  });
}
