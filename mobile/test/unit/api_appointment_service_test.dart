import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/session.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/services/api/api_appointment_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Map<String, dynamic> _apptJson({String status = 'pending'}) => {
      'id': 'a1',
      'userId': 'u1',
      'providerId': 'provider1',
      'serviceIds': ['service1'],
      'appointmentDate': DateTime.utc(2026, 6, 25, 9).toIso8601String(),
      'status': status,
      'totalPrice': 15000,
      'depositAmount': 0,
      'balanceDue': 15000,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    };

Future<ApiAppointmentService> _authed(MockClient client) async {
  final store = InMemorySessionStore();
  await store.save(jsonEncode(
    Session(
      token: 'tok',
      user: User(
        id: 'u1',
        phoneNumber: '+2250700000000',
        createdAt: DateTime.utc(2026),
      ),
    ).toJson(),
  ));
  return ApiAppointmentService(
    client: client,
    baseUrl: 'http://x',
    sessionStore: store,
  );
}

void main() {
  test('getAvailableTimeSlots hits the public /availability + parses slots',
      () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/availability');
      expect(req.url.queryParameters['providerId'], 'provider1');
      expect(req.url.queryParameters['date'], '2026-06-25');
      return http.Response(
        jsonEncode({
          'providerId': 'provider1',
          'date': '2026-06-25',
          'slots': [
            DateTime.utc(2026, 6, 25, 9).toIso8601String(),
            DateTime.utc(2026, 6, 25, 9, 30).toIso8601String(),
          ],
        }),
        200,
      );
    });
    final service = ApiAppointmentService(client: client, baseUrl: 'http://x');

    final res = await service.getAvailableTimeSlots(
      providerId: 'provider1',
      date: DateTime(2026, 6, 25),
      serviceIds: ['service1'],
    );

    expect(res.success, isTrue);
    expect(res.data!.length, 2);
  });

  test('bookAppointment posts with the bearer token → pending appointment',
      () async {
    String? auth;
    final client = MockClient((req) async {
      expect(req.url.path, '/appointments');
      auth = req.headers['Authorization'] ?? req.headers['authorization'];
      return http.Response(jsonEncode(_apptJson()), 201);
    });
    final service = await _authed(client);

    final res = await service.bookAppointment(
      providerId: 'provider1',
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2026, 6, 25, 9),
    );

    expect(res.success, isTrue);
    expect(res.data!.status, AppointmentStatus.pending);
    expect(auth, 'Bearer tok');
  });

  test('bookAppointment surfaces slot_unavailable as a clear message',
      () async {
    final client = MockClient(
      (req) async =>
          http.Response(jsonEncode({'error': 'slot_unavailable'}), 409),
    );
    final service = await _authed(client);

    final res = await service.bookAppointment(
      providerId: 'provider1',
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2026, 6, 25, 9),
    );

    expect(res.success, isFalse);
    expect(res.code, 'slot_unavailable');
    expect(res.error, contains('plus disponible'));
  });

  test('booking without a session is rejected (no network call)', () async {
    final client =
        MockClient((req) async => throw Exception('should not call'));
    final service = ApiAppointmentService(client: client, baseUrl: 'http://x');

    final res = await service.bookAppointment(
      providerId: 'provider1',
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2026, 6, 25, 9),
    );

    expect(res.success, isFalse);
  });

  test('getUserAppointments parses the paged envelope', () async {
    final client = MockClient(
      (req) async => http.Response(
          jsonEncode({
            'items': [_apptJson()],
            'total': 1
          }),
          200),
    );
    final service = await _authed(client);

    final res = await service.getUserAppointments();

    expect(res.success, isTrue);
    expect(res.data!.single.id, 'a1');
  });

  test('cancel + reschedule hit their endpoints', () async {
    final cancelClient = MockClient((req) async {
      expect(req.url.path, '/appointments/a1/cancel');
      return http.Response(jsonEncode(_apptJson(status: 'cancelled')), 200);
    });
    expect(
        (await (await _authed(cancelClient)).cancelAppointment('a1')).success,
        isTrue);

    final rescheduleClient = MockClient((req) async {
      expect(req.url.path, '/appointments/a1/reschedule');
      return http.Response(jsonEncode(_apptJson()), 200);
    });
    final res = await (await _authed(rescheduleClient)).rescheduleAppointment(
      id: 'a1',
      newDateTime: DateTime.utc(2026, 6, 26, 10),
    );
    expect(res.success, isTrue);
  });

  test('a 401 mid-booking triggers a silent refresh + retry', () async {
    final store = InMemorySessionStore();
    await store.save(jsonEncode(
      Session(
        token: 'old',
        refreshToken: 'r1',
        user: User(
          id: 'u1',
          phoneNumber: '+2250700000000',
          createdAt: DateTime.utc(2026),
        ),
      ).toJson(),
    ));
    var refreshed = false;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/refresh') {
        refreshed = true;
        return http.Response(
          jsonEncode({
            'accessToken': 'new',
            'refreshToken': 'r2',
            'expiresAt': DateTime(2030).toIso8601String(),
          }),
          200,
        );
      }
      // The first booking attempt uses the stale token → 401; retry succeeds.
      final auth = req.headers['Authorization'] ?? req.headers['authorization'];
      if (auth == 'Bearer new') {
        return http.Response(jsonEncode(_apptJson()), 201);
      }
      return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
    });
    final service = ApiAppointmentService(
      client: client,
      baseUrl: 'http://x',
      sessionStore: store,
    );

    final res = await service.bookAppointment(
      providerId: 'provider1',
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2026, 6, 25, 9),
    );

    expect(res.success, isTrue);
    expect(refreshed, isTrue);
    expect((jsonDecode((await store.read())!) as Map)['token'], 'new');
  });
}
