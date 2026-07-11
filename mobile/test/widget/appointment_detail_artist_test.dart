import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/screens/appointments/appointment_detail_screen.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:provider/provider.dart';

class _MockAppointments extends Mock implements AppointmentServiceInterface {}

class _MockProviders extends Mock implements ProviderServiceInterface {}

/// Parity 1.8 (app half): the consumer detail shows the chosen spécialiste,
/// resolved from the salon's public team.
void main() {
  final appointments = _MockAppointments();
  final providers = _MockProviders();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    serviceLocator.appointmentService = appointments;
    serviceLocator.providerService = providers;
  });

  Appointment appt({String? artistId}) => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime.now().add(const Duration(days: 2)),
        status: AppointmentStatus.confirmed,
        totalPrice: 10000,
        artistId: artistId,
        createdAt: DateTime.now(),
      );

  Widget host() => ChangeNotifierProvider(
        create: (_) => AppointmentProvider(),
        child: const MaterialApp(
          home: AppointmentDetailScreen(appointmentId: 'a1'),
        ),
      );

  testWidgets('shows « Spécialiste » resolved from the salon team',
      (tester) async {
    when(() => appointments.getAppointmentById('a1'))
        .thenAnswer((_) async => ApiResponse.success(appt(artistId: 'ar1')));
    when(() => providers.getProviderById('p1')).thenAnswer(
      (_) async => ApiResponse.success(
        const models.Provider(
          id: 'p1',
          name: 'Beauté Divine',
          description: '',
          address: 'Cocody',
          imageUrls: [],
          rating: 4.8,
          reviewCount: 2,
          services: [],
          availability: Availability(
            providerId: 'p1',
            weeklySchedule: {},
            blockedDates: [],
          ),
          phoneNumber: '+22500',
          category: 'salon',
          artists: [Artist(id: 'ar1', name: 'Awa Diabaté', providerId: 'p1')],
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.text('Spécialiste'), findsOneWidget);
    expect(find.text('Awa Diabaté'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no artist on the booking → no row', (tester) async {
    when(() => appointments.getAppointmentById('a1'))
        .thenAnswer((_) async => ApiResponse.success(appt()));

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.text('Spécialiste'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
