import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/services/api/api_pro_service.dart';
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

/// An ApiProService backed by a provider session (token + refresh token).
ApiProService _service(MockClient client, {String? refresh = 'r1'}) {
  final store = InMemorySessionStore();
  store.save(jsonEncode({
    'token': 'tok',
    'refreshToken': refresh,
    'provider': {'id': 'p1'},
  }));
  return ApiProService(
    client: client,
    baseUrl: 'http://x',
    providerSessionStore: store,
  );
}

void main() {
  test('getProviderAppointments GETs /appointments with bearer + status',
      () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/appointments');
      expect(req.url.queryParameters['status'], 'pending');
      expect(
        req.headers['Authorization'] ?? req.headers['authorization'],
        'Bearer tok',
      );
      return http.Response(
        jsonEncode({
          'items': [_apptJson()],
          'total': 1
        }),
        200,
      );
    });

    final res = await _service(client).getProviderAppointments(
      'provider1',
      status: AppointmentStatus.pending,
    );

    expect(res.success, isTrue);
    expect(res.data!.single.id, 'a1');
  });

  test('accept / reject / complete / no-show hit their endpoints → true',
      () async {
    final paths = <String>[];
    MockClient client() => MockClient((req) async {
          paths.add(req.url.path);
          return http.Response(jsonEncode(_apptJson(status: 'confirmed')), 200);
        });

    expect((await _service(client()).acceptAppointment('a1')).success, isTrue);
    expect(
      (await _service(client()).rejectAppointment('a1', 'busy')).success,
      isTrue,
    );
    expect(
      (await _service(client()).markAppointmentComplete('a1')).success,
      isTrue,
    );
    expect((await _service(client()).markNoShow('a1')).success, isTrue);

    expect(paths, [
      '/appointments/a1/accept',
      '/appointments/a1/reject',
      '/appointments/a1/complete',
      '/appointments/a1/no-show',
    ]);
  });

  test('a cross-salon transition surfaces forbidden', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'forbidden'}), 403),
    );

    final res = await _service(client).acceptAppointment('a1');

    expect(res.success, isFalse);
    expect(res.code, 'forbidden');
  });

  test(
      'a 401 triggers provider silent refresh (/auth/provider/refresh) + retry',
      () async {
    var refreshed = false;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/provider/refresh') {
        refreshed = true;
        return http.Response(
          jsonEncode({
            'accessToken': 'tok2',
            'refreshToken': 'r2',
            'expiresAt': DateTime(2030).toIso8601String(),
          }),
          200,
        );
      }
      final auth = req.headers['Authorization'] ?? req.headers['authorization'];
      if (auth == 'Bearer tok2') {
        return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
      }
      return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
    });

    final res = await _service(client).getProviderAppointments('provider1');

    expect(res.success, isTrue);
    expect(refreshed, isTrue);
  });

  test('with no provider session, calls fail fast without any HTTP', () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final service = ApiProService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: InMemorySessionStore(),
    );

    expect((await service.acceptAppointment('a1')).success, isFalse);
    expect((await service.getProviderAppointments('p')).success, isFalse);
  });

  test('an unbacked method (dashboard) delegates to the mock, no HTTP',
      () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final service = ApiProService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: InMemorySessionStore(),
    );

    final res = await service.getDashboardStats('provider1');

    expect(res.success, isTrue); // came from the embedded MockProService
  });
}
