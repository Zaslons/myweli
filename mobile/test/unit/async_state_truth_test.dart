import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/notification_preferences.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/interfaces/pro_clients_service_interface.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/interfaces/pro_team_service_interface.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Appointments extends Mock implements AppointmentServiceInterface {}

class _Salons extends Mock implements ProviderServiceInterface {}

class _Pro extends Mock implements ProServiceInterface {}

class _Clients extends Mock implements ProClientsServiceInterface {}

class _Team extends Mock implements ProTeamServiceInterface {}

class _Notifications extends Mock implements NotificationServiceInterface {}

/// docs/design/hygiene-batch9.md §14 (B9.8) — what moving every screen onto
/// `AppAsyncView` found: a view can only say the truth its provider holds.
/// A selection that outlived its screen, a load and a write sharing one
/// `error`, two reads sharing one `isLoading`, defaults shown as answers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Appointments appointments;
  late _Salons salons;
  late _Pro pro;
  late _Clients clients;
  late _Team team;
  late _Notifications notifications;

  setUpAll(() {
    appointments = _Appointments();
    salons = _Salons();
    pro = _Pro();
    clients = _Clients();
    team = _Team();
    notifications = _Notifications();
    serviceLocator.appointmentService = appointments;
    serviceLocator.providerService = salons;
    serviceLocator.proService = pro;
    serviceLocator.proClientsService = clients;
    serviceLocator.proTeamService = team;
    serviceLocator.notificationService = notifications;
    registerFallbackValue(ProviderSort.relevance);
  });

  setUp(() {
    reset(appointments);
    reset(salons);
    reset(pro);
    reset(clients);
    reset(team);
    reset(notifications);
    SharedPreferences.setMockInitialValues({});
  });

  Appointment booking(String id) => Appointment(
    id: id,
    userId: 'u1',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2030, 6, 24, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 20000,
    createdAt: DateTime(2024),
    providerName: 'Salon $id',
  );

  group('a booking opened is that booking', () {
    test('the way to B drops A: B\'s screen never holds A', () async {
      when(
        () => appointments.getAppointmentById('a'),
      ).thenAnswer((_) async => ApiResponse.success(booking('a')));
      final b = Completer<ApiResponse<Appointment>>();
      when(
        () => appointments.getAppointmentById('b'),
      ).thenAnswer((_) => b.future);

      final p = AppointmentProvider();
      await p.loadAppointmentById('a');
      expect(p.selectedAppointment?.id, 'a');

      unawaited(p.loadAppointmentById('b'));
      expect(p.selectedAppointment, isNull, reason: 'A, while B is out');

      b.complete(ApiResponse.success(booking('b')));
      await pumpEventQueue();
      expect(p.selectedAppointment?.id, 'b');
    });

    test('a late answer for A, after B was asked, is nobody\'s', () async {
      final a = Completer<ApiResponse<Appointment>>();
      when(
        () => appointments.getAppointmentById('a'),
      ).thenAnswer((_) => a.future);
      when(
        () => appointments.getAppointmentById('b'),
      ).thenAnswer((_) async => ApiResponse.success(booking('b')));

      final p = AppointmentProvider();
      unawaited(p.loadAppointmentById('a'));
      await p.loadAppointmentById('b');
      a.complete(ApiResponse.success(booking('a')));
      await pumpEventQueue();

      expect(p.selectedAppointment?.id, 'b');
    });

    test(
      'the list\'s error is the list\'s: a refused cancel is not it',
      () async {
        when(
          () => appointments.getUserAppointments(status: any(named: 'status')),
        ).thenAnswer((_) async => ApiResponse.success([booking('a')]));
        when(
          () => appointments.cancelAppointment(any()),
        ).thenAnswer((_) async => ApiResponse.error('Annulation refusée.'));

        final p = AppointmentProvider();
        await p.loadAppointments();
        await p.cancelAppointment('a');

        expect(p.error, 'Annulation refusée.');
        expect(p.listError, isNull);
      },
    );

    test('a failed list read is the list\'s error, in its own words', () async {
      when(
        () => appointments.getUserAppointments(status: any(named: 'status')),
      ).thenAnswer((_) async => ApiResponse.error(kNoConnectionMessage));

      final p = AppointmentProvider();
      await p.loadAppointments();

      expect(p.listError, kNoConnectionMessage);
    });
  });

  group('the salon list has its own read', () {
    test('the carousel landing first does not end the list\'s wait', () async {
      final list = Completer<ApiResponse<List<Provider>>>();
      when(
        () => salons.getProviders(
          category: any(named: 'category'),
          searchQuery: any(named: 'searchQuery'),
          commune: any(named: 'commune'),
          sort: any(named: 'sort'),
          availableToday: any(named: 'availableToday'),
        ),
      ).thenAnswer((_) => list.future);
      when(
        () => salons.getFeaturedProviders(),
      ).thenAnswer((_) async => ApiResponse.success(MockData.providers));

      final p = ProviderProvider();
      unawaited(p.loadProviders());
      await p.loadFeaturedProviders();

      expect(p.isLoading, isFalse, reason: 'the shared flag, as before');
      expect(
        p.listLoading,
        isTrue,
        reason: 'turned off with it, « Aucun salon trouvé » showed here',
      );
      list.complete(ApiResponse.success(MockData.providers));
      await pumpEventQueue();
      expect(p.listLoading, isFalse);
    });

    test('a salon page\'s failed read is not the list\'s error', () async {
      when(() => salons.getProviderById(any())).thenAnswer(
        (_) async => ApiResponse.error(kNoConnectionMessage, code: 'network'),
      );

      final p = ProviderProvider();
      await p.loadProviderById(SalonId('p1'));

      expect(p.error, kNoConnectionMessage);
      expect(p.listError, isNull);
    });
  });

  test('preferences are not shown before the server said them', () async {
    final read = Completer<ApiResponse<NotificationPreferences>>();
    when(() => notifications.getPreferences()).thenAnswer((_) => read.future);

    final p = NotificationPreferencesProvider();
    expect(p.loadedPrefs, isNull, reason: 'the defaults are not an answer');
    unawaited(p.load());
    read.complete(
      ApiResponse.success(const NotificationPreferences(marketing: true)),
    );
    await pumpEventQueue();
    expect(p.loadedPrefs?.marketing, isTrue);
  });

  test(
    'a refused « Ajouter un client » leaves the list\'s read alone',
    () async {
      when(
        () => clients.listClients(
          any(),
          query: any(named: 'query'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse.success(
          const SalonClientsPage(items: [], page: 1, total: 0),
        ),
      );
      when(
        () => clients.addClient(
          any(),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => ApiResponse.error(kGenericErrorMessage));

      final p = ProClientsProvider();
      await p.load(SalonId('p1'));
      await p.addClient(SalonId('p1'), name: 'Awa', phone: '+2250700000000');

      expect(p.error, kGenericErrorMessage);
      expect(
        p.loadError,
        isNull,
        reason: 'the list screen read `error`: the list became an error page',
      );
    },
  );

  test('a refused delete is not the catalogue\'s load error', () async {
    when(() => pro.getProviderServices(SalonId('p1'))).thenAnswer(
      (_) async => ApiResponse.success(<Service>[
        MockData.providers.first.services.first,
      ]),
    );
    when(
      () => pro.deleteService(any()),
    ).thenAnswer((_) async => ApiResponse.error('Suppression refusée.'));

    final p = ProServiceProvider();
    await p.loadServices(SalonId('p1'));
    await p.deleteService(MockData.providers.first.services.first.id);

    expect(p.error, 'Suppression refusée.');
    expect(p.loadError, isNull);
  });

  test('« Mes invitations » knows its read failed', () async {
    when(() => team.getMyInvitations()).thenAnswer(
      (_) async =>
          ApiResponse<List<TeamInvitation>>.error(kNoConnectionMessage),
    );

    final p = ProTeamProvider();
    await p.loadMyInvitations();

    expect(p.myInvitations, isEmpty);
    expect(
      p.invitationsError,
      kNoConnectionMessage,
      reason: 'it said « Aucune invitation en attente »',
    );
  });
}
