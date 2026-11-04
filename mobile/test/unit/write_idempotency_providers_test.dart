import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';

/// docs/design/write-idempotency.md §4 — the providers hold ONE key per
/// submission: the same while the person retries the same form (the server
/// may already have done it), a new one when the form changed, and a new one
/// after a success. The services do the silent re-ask
/// (`write_idempotency_test.dart`); this is the key they are given.

/// What every fake answers: success, or the lost answer.
bool fail = true;
final keys = <String?>[];

ApiResponse<T> _answer<T>(T value) => fail
    ? ApiResponse.error('Pas de connexion. Réessayez.', code: 'network')
    : ApiResponse.success(value);

Appointment _appt(String id) => Appointment(
  id: id,
  userId: 'u1',
  providerId: SalonId('provider1'),
  serviceIds: const ['service1'],
  appointmentDate: DateTime.utc(2026, 10, 22, 10),
  status: AppointmentStatus.pending,
  totalPrice: 15000,
  durationMinutes: 60,
  createdAt: DateTime.utc(2026, 10, 21),
);

class _Appointments extends MockAppointmentService {
  @override
  Future<ApiResponse<Appointment>> bookAppointment({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? artistId,
    String? notes,
    double depositAmount = 0,
    String? depositScreenshotUrl,
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return _answer(_appt('a${keys.length}'));
  }
}

class _Pro extends MockProService {
  @override
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    String? artistId,
    bool sendSmsInvite = false,
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return _answer(_appt('m${keys.length}'));
  }
}

class _Clients extends MockProClientsService {
  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body, {
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return _answer(
      SalonClientNote(
        id: 'n${keys.length}',
        authorName: 'Moi',
        body: body,
        createdAt: DateTime.utc(2026, 10, 21),
      ),
    );
  }
}

class _Team extends MockProTeamService {
  @override
  Future<ApiResponse<TeamMember>> inviteMember({
    required String email,
    required TeamRole role,
    String? artistId,
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return _answer(
      TeamMember(
        id: 'mem${keys.length}',
        providerId: SalonId('provider1'),
        email: email,
        role: role,
        status: TeamMemberStatus.invited,
        invitedAt: DateTime.utc(2026, 10, 21),
      ),
    );
  }
}

final _key = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    serviceLocator.appointmentService = _Appointments();
    serviceLocator.proService = _Pro();
    serviceLocator.proClientsService = _Clients();
    serviceLocator.proTeamService = _Team();
  });

  setUp(() {
    fail = true;
    keys.clear();
    ProSalonScope.clear();
  });

  /// Two failed tries of the same form, one of a changed form, then the same
  /// form succeeding and being sent once more.
  Future<void> exercise({
    required Future<void> Function() same,
    required Future<void> Function() changed,
  }) async {
    await same();
    await same();
    expect(keys[0], matches(_key));
    expect(keys[1], keys[0], reason: '« Réessayer »: the same key');
    await changed();
    expect(keys[2], isNot(keys[0]), reason: 'another form: a new key');
    fail = false;
    await same();
    expect(keys[3], isNot(keys[2]));
    await same();
    expect(keys[4], isNot(keys[3]), reason: 'after a success: a new key');
  }

  test('the client’s booking', () async {
    final p = AppointmentProvider();
    Future<void> book(String? notes) => p.bookAppointment(
      providerId: SalonId('provider1'),
      serviceIds: const ['service1'],
      appointmentDateTime: DateTime.utc(2026, 10, 22, 10),
      notes: notes,
    );
    await exercise(same: () => book(null), changed: () => book('Cheveux'));
  });

  test('the salon’s booking for a client', () async {
    final p = ProAppointmentProvider();
    Future<void> create(String name) => p.createManualBooking(
      providerId: SalonId('provider1'),
      serviceIds: const ['service1'],
      appointmentDateTime: DateTime.utc(2026, 10, 22, 10),
      clientName: name,
    );
    await exercise(same: () => create('Awa'), changed: () => create('Ama'));
  });

  test('a note', () async {
    final p = ProClientsProvider();
    await exercise(
      same: () => p.addNote(SalonId('provider1'), 'c1', 'Allergie'),
      changed: () => p.addNote(SalonId('provider1'), 'c1', 'Allergie au henné'),
    );
  });

  test('an invitation', () async {
    final p = ProTeamProvider();
    await exercise(
      same: () => p.invite(email: 'awa@salon.ci', role: TeamRole.manager),
      changed: () => p.invite(email: 'ama@salon.ci', role: TeamRole.manager),
    );
  });
}
