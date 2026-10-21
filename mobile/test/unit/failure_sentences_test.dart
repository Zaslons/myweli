import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/pro_availability_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/services/api/api_appointment_service.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';

/// docs/design/app-failure-messages.md §2–§3 on the real paths:
/// - a provider whose service throws (a captive portal's HTML in a 200 makes
///   `_decode` throw `FormatException`; JSON of the wrong shape, a `TypeError`)
///   shows « Une erreur est survenue. Réessayez. » — never the exception's
///   English text;
/// - the services the screens call directly answer `unreadable` instead of
///   throwing;
/// - « nothing answered » carries the code `network` from the REAL service —
///   « Accueil » decided « Pas de connexion » on that code and the real
///   `ApiProService.getDashboardStats` never sent it (#665's tests used a fake
///   that did).

class _ThrowingAppointments extends MockAppointmentService {
  @override
  Future<ApiResponse<List<Appointment>>> getUserAppointments({
    AppointmentStatus? status,
  }) async => throw TypeError();
}

class _ThrowingTeam extends MockProTeamService {
  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
    String? idempotencyKey,
  }) async => throw const FormatException('Unexpected character', '<html>');
}

/// The REAL Pro service, over [client] — the availability save that gets a
/// captive portal's page, and the dashboard that gets nothing at all.
late MockClient _proClient;

Future<InMemorySessionStore> _proSession() async {
  final store = InMemorySessionStore();
  await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    serviceLocator.appointmentService = _ThrowingAppointments();
    serviceLocator.proTeamService = _ThrowingTeam();
    serviceLocator.proService = ApiProService(
      client: MockClient((req) async {
        final streamed = await _proClient.send(req);
        return http.Response.fromStream(streamed);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await _proSession(),
    );
  });

  group('a provider never shows an exception’s text', () {
    test(
      'a load whose parse throws a TypeError → the generic sentence',
      () async {
        final p = AppointmentProvider();
        await p.loadAppointments();
        expect(p.error, kGenericErrorMessage);
      },
    );

    test(
      'an invitation whose answer is unreadable → the generic sentence',
      () async {
        final p = ProTeamProvider();
        await p.invite(email: 'mgr@salon.ci', role: TeamRole.manager);
        expect(p.inviteError, kGenericErrorMessage);
      },
    );

    test(
      'the availability save that gets a captive portal’s HTML in a 200 → the generic sentence',
      () async {
        _proClient = MockClient(
          (_) async => http.Response(
            '<html><body>Connectez-vous au Wi-Fi</body></html>',
            200,
          ),
        );
        final p = ProAvailabilityProvider();
        final ok = await p.updateAvailability(
          'provider1',
          const Availability(
            providerId: 'provider1',
            weeklySchedule: {},
            blockedDates: [],
          ),
        );
        expect(ok, isFalse);
        expect(p.error, kGenericErrorMessage);
        expect(p.error, isNot(contains('FormatException')));
      },
    );
  });

  test(
    '« Accueil » with nothing answering, through the REAL service: « Pas de connexion. Réessayez. »',
    () async {
      _proClient = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final p = ProDashboardProvider();
      await p.loadDashboardStats('provider1');
      expect(p.errorIsOffline, isTrue);
    },
  );

  group('the services a screen calls directly answer instead of throwing', () {
    test('the deposit screenshot url, an HTML 200 → unreadable', () async {
      final store = InMemorySessionStore();
      await store.save(
        jsonEncode({
          'token': 'tok',
          'user': {
            'id': 'u1',
            'phoneNumber': '+2250700000000',
            'createdAt': DateTime.utc(2026).toIso8601String(),
          },
        }),
      );
      final svc = ApiAppointmentService(
        client: MockClient((_) async => http.Response('<html>', 200)),
        baseUrl: 'http://x',
        sessionStore: store,
      );
      final r = await svc.depositScreenshotUrl(appointmentId: 'a1');
      expect(r.success, isFalse);
      expect(r.code, 'unreadable');
      expect(r.error, kGenericErrorMessage);
    });

    test('the salon (getMyProvider), an HTML 200 → unreadable', () async {
      _proClient = MockClient((_) async => http.Response('<html>', 200));
      final r = await serviceLocator.proService.getMyProvider();
      expect(r.code, 'unreadable');
      expect(r.error, kGenericErrorMessage);
    });
  });
}
