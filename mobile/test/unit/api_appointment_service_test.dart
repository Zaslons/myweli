import 'dart:convert';
import 'dart:typed_data';

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

Future<ApiAppointmentService> _authed(
  MockClient client, {
  ImageCompressor? compressor,
}) async {
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
    compressor: compressor,
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

  test('uploadDepositScreenshot signs purpose=deposit, uploads → returns key',
      () async {
    var signed = false;
    var uploaded = false;
    final client = MockClient((req) async {
      if (req.url.path == '/uploads/sign') {
        signed = true;
        expect((jsonDecode(req.body) as Map)['purpose'], 'deposit');
        return http.Response(
          jsonEncode({
            'uploadUrl': 'http://storage/deposit-bkt',
            'fields': {'key': 'deposit/u1/x.jpg'},
            'key': 'deposit/u1/x.jpg',
          }),
          200,
        );
      }
      // The presigned multipart upload straight to storage.
      uploaded = true;
      expect(req.url.toString(), 'http://storage/deposit-bkt');
      return http.Response('', 204);
    });
    final service = await _authed(
      client,
      compressor: (_) async => Uint8List.fromList([1, 2, 3]),
    );

    final res = await service.uploadDepositScreenshot(source: 'shot.jpg');

    expect(signed, isTrue);
    expect(uploaded, isTrue);
    expect(res.success, isTrue);
    expect(res.data, 'deposit/u1/x.jpg'); // only the private key, no public URL
  });

  test('submitDeposit POSTs the key → returns the updated appointment',
      () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/appointments/a1/deposit');
      expect(
        (jsonDecode(req.body) as Map)['screenshotKey'],
        'deposit/u1/x.jpg',
      );
      final j = _apptJson();
      j['depositScreenshotUrl'] = 'deposit/u1/x.jpg';
      return http.Response(jsonEncode(j), 200);
    });
    final service = await _authed(client);

    final res = await service.submitDeposit(
      appointmentId: 'a1',
      screenshotKey: 'deposit/u1/x.jpg',
    );

    expect(res.success, isTrue);
    expect(res.data!.depositScreenshotUrl, 'deposit/u1/x.jpg');
  });

  test('depositScreenshotUrl GETs the signed view URL', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/appointments/a1/deposit-screenshot');
      return http.Response(jsonEncode({'url': 'https://signed/x'}), 200);
    });
    final service = await _authed(client);

    final res = await service.depositScreenshotUrl(appointmentId: 'a1');

    expect(res.success, isTrue);
    expect(res.data, 'https://signed/x');
  });
}
