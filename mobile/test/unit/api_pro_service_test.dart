import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

Map<String, dynamic> _svcJson({bool active = false}) => {
      'id': 'svc1',
      'name': 'Coupe',
      'description': '',
      'price': 5000,
      'priceMax': null,
      'durationMinutes': 30,
      'durationVariants': <String, dynamic>{},
      'providerId': 'provider1',
      'artistIds': <String>[],
      'active': active,
    };

Map<String, dynamic> _availJson() => {
      'providerId': 'provider1',
      'weeklySchedule': <String, dynamic>{},
      'breaks': <String, dynamic>{},
      'blockedDates': <String>[],
      'bufferMinutes': 10,
    };

/// An ApiProService whose persisted provider session is linked to [providerId]
/// (so the serviceId-only methods can resolve the salon path).
ApiProService _linked(MockClient client, {String providerId = 'provider1'}) {
  final store = InMemorySessionStore();
  store.save(jsonEncode({
    'token': 'tok',
    'refreshToken': 'r1',
    'provider': {
      'id': 'acc1',
      'phoneNumber': '+2250500000000',
      'businessName': 'Salon',
      'businessType': 'salon',
      'verificationStatus': 'pending',
      'kycDocs': <Map<String, dynamic>>[],
      'createdAt': '2026-01-01T00:00:00.000Z',
      'providerId': providerId,
    },
  }));
  return ApiProService(
    client: client,
    baseUrl: 'http://x',
    providerSessionStore: store,
  );
}

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

  test('getDepositPolicy GETs /providers/{id}/deposit-policy + parses',
      () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/providers/provider1/deposit-policy');
      return http.Response(
        jsonEncode({
          'depositRequired': true,
          'depositPercentage': 0.4,
          'cancellationWindowHours': 24,
          'mobileMoneyOperator': 'orangeMoney',
          'mobileMoneyNumber': '+2250700000000',
        }),
        200,
      );
    });
    final res = await _linked(client).getDepositPolicy('provider1');
    expect(res.success, isTrue);
    expect(res.data!.depositRequired, isTrue);
    expect(res.data!.depositPercentage, 0.4);
    expect(res.data!.mobileMoneyOperator, MobileMoneyOperator.orangeMoney);
  });

  test('updateDepositPolicy PUTs the policy (operator by wire name)', () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'PUT');
      expect(req.url.path, '/providers/provider1/deposit-policy');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(body), 200);
    });
    final res = await _linked(client).updateDepositPolicy(
      'provider1',
      depositRequired: true,
      depositPercentage: 0.5,
      cancellationWindowHours: 48,
      mobileMoneyOperator: MobileMoneyOperator.wave,
      mobileMoneyNumber: '+2250700000000',
    );
    expect(res.success, isTrue);
    expect(body!['mobileMoneyOperator'], 'wave');
    expect(body!['depositPercentage'], 0.5);
    expect(res.data!.mobileMoneyOperator, MobileMoneyOperator.wave);
  });

  test('getEarnings GETs /providers/{id}/earnings with the range + parses',
      () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/providers/provider1/earnings');
      expect(req.url.queryParameters['startDate'], isNotNull);
      return http.Response(
        jsonEncode({
          'totalEarnings': 15000,
          'transactions': [
            {
              'id': 'transaction_a1',
              'appointmentId': 'a1',
              'amount': 15000,
              'date': DateTime.utc(2030, 6, 10).toIso8601String(),
              'status': 'completed',
            },
          ],
        }),
        200,
      );
    });
    final res = await _linked(client).getEarnings(
      'provider1',
      startDate: DateTime.utc(2030, 6, 1),
    );
    expect(res.success, isTrue);
    expect(res.data!.totalEarnings, 15000);
    expect(res.data!.transactions.single.appointmentId, 'a1');
  });

  test('getDashboardStats GETs /providers/{id}/dashboard + parses', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/providers/provider1/dashboard');
      expect(
        req.headers['Authorization'] ?? req.headers['authorization'],
        'Bearer tok',
      );
      return http.Response(
        jsonEncode({
          'todayAppointments': 3,
          'pendingRequests': 1,
          'todayRevenue': 15000,
          'weekRevenue': 20000,
          'monthRevenue': 50000,
          'totalAppointments': 42,
        }),
        200,
      );
    });
    final res = await _linked(client).getDashboardStats('provider1');
    expect(res.success, isTrue);
    expect(res.data!.todayAppointments, 3);
    expect(res.data!.monthRevenue, 50000);
  });

  // ---- catalogue (services + availability) ----------------------------------

  test('getProviderServices GETs the salon services + parses active', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/providers/provider1/services');
      expect(
        req.headers['Authorization'] ?? req.headers['authorization'],
        'Bearer tok',
      );
      return http.Response(
        jsonEncode({
          'items': [_svcJson()],
          'total': 1
        }),
        200,
      );
    });
    final res = await _linked(client).getProviderServices('provider1');
    expect(res.success, isTrue);
    expect(res.data!.single.active, false);
  });

  test('createService POSTs the body → Service', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/providers/provider1/services');
      expect((jsonDecode(req.body) as Map)['name'], 'Coupe');
      return http.Response(jsonEncode(_svcJson(active: true)), 201);
    });
    final res = await _linked(client).createService(
      'provider1',
      {'name': 'Coupe', 'price': 5000, 'durationMinutes': 30},
    );
    expect(res.success, isTrue);
    expect(res.data!.active, true);
  });

  test('updateService PATCHes the salon-scoped path (providerId from session)',
      () async {
    String? path;
    final client = MockClient((req) async {
      path = req.url.path;
      return http.Response(jsonEncode(_svcJson()), 200);
    });
    final res = await _linked(client).updateService('svc1', {'price': 6000});
    expect(res.success, isTrue);
    expect(path, '/providers/provider1/services/svc1');
  });

  test('deleteService → 204 → true', () async {
    final client = MockClient((req) async {
      expect(req.method, 'DELETE');
      expect(req.url.path, '/providers/provider1/services/svc1');
      return http.Response('', 204);
    });
    expect((await _linked(client).deleteService('svc1')).success, isTrue);
  });

  test('setServiceActive PATCHes {active}', () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_svcJson()), 200);
    });
    final res = await _linked(client).setServiceActive('svc1', false);
    expect(res.success, isTrue);
    expect(body!['active'], false);
  });

  test('serviceId-only methods fail fast when the account is unlinked',
      () async {
    // _service stores a minimal provider with no providerId → no salon path.
    final client =
        MockClient((req) async => throw Exception('should not call'));
    expect((await _service(client).deleteService('svc1')).success, isFalse);
  });

  test('availability GET + PUT round-trip', () async {
    final client = MockClient((req) async {
      if (req.method == 'PUT') {
        expect(req.url.path, '/providers/provider1/availability');
      }
      return http.Response(jsonEncode(_availJson()), 200);
    });
    final svc = _linked(client);
    expect((await svc.getProviderAvailability('provider1')).success, isTrue);
    final put = await svc.updateAvailability(
      'provider1',
      Availability.fromJson(_availJson()),
    );
    expect(put.success, isTrue);
  });

  test('a 401 on a catalogue call triggers provider silent refresh', () async {
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
    final res = await _linked(client).getProviderServices('provider1');
    expect(res.success, isTrue);
    expect(refreshed, isTrue);
  });

  test('forbidden (cross-salon) maps to a clear error code', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'forbidden'}), 403),
    );
    final res = await _linked(client).getProviderServices('provider1');
    expect(res.success, isFalse);
    expect(res.code, 'forbidden');
  });

  test('createManualBooking POSTs /providers/{id}/appointments → Appointment',
      () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/providers/provider1/appointments');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_apptJson(status: 'confirmed')), 201);
    });
    final res = await _linked(client).createManualBooking(
      providerId: 'provider1',
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2030, 6, 25, 9),
      clientName: 'Awa',
      clientPhone: '+2250700000000',
      artistId: 'artist1',
    );
    expect(res.success, isTrue);
    expect(res.data!.status, AppointmentStatus.confirmed);
    expect(body!['clientName'], 'Awa');
    expect(body!['serviceIds'], ['service1']);
    // Audit 1.11: the journal gap prefill carries the filtered artist.
    expect(body!['artistId'], 'artist1');
  });

  test('rescheduleAppointment POSTs /appointments/{id}/reschedule → true',
      () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/appointments/a1/reschedule');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_apptJson(status: 'confirmed')), 200);
    });
    final res = await _linked(client).rescheduleAppointment(
      'a1',
      DateTime.utc(2030, 6, 25, 10),
    );
    expect(res.success, isTrue);
    expect(res.data, isTrue);
    expect(body!['newDateTime'], '2030-06-25T10:00:00.000Z');
  });

  test('rescheduleAppointment surfaces a conflict (slot_unavailable)',
      () async {
    final client = MockClient(
      (req) async =>
          http.Response(jsonEncode({'error': 'slot_unavailable'}), 409),
    );
    final res = await _linked(client).rescheduleAppointment(
      'a1',
      DateTime.utc(2030, 6, 25, 10),
    );
    expect(res.success, isFalse);
    expect(res.code, 'slot_unavailable');
  });

  test('getGalleryPhotos GETs /providers/{id}/gallery → imageUrls', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/providers/provider1/gallery');
      return http.Response(
        jsonEncode({
          'imageUrls': ['https://cdn/a.jpg', 'https://cdn/b.jpg']
        }),
        200,
      );
    });
    final res = await _linked(client).getGalleryPhotos('provider1');
    expect(res.success, isTrue);
    expect(res.data, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
  });

  test('updateGalleryPhotos PUTs {imageUrls} → parsed list', () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'PUT');
      expect(req.url.path, '/providers/provider1/gallery');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'imageUrls': ['https://cdn/x.jpg']
        }),
        200,
      );
    });
    final res = await _linked(client)
        .updateGalleryPhotos('provider1', ['https://cdn/x.jpg']);
    expect(res.success, isTrue);
    expect(res.data, ['https://cdn/x.jpg']);
    expect(body!['imageUrls'], ['https://cdn/x.jpg']);
  });

  test('depositScreenshotUrl GETs the signed deposit-screenshot URL', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/appointments/a1/deposit-screenshot');
      return http.Response(jsonEncode({'url': 'https://signed/proof'}), 200);
    });
    final res = await _linked(client).depositScreenshotUrl('a1');
    expect(res.success, isTrue);
    expect(res.data, 'https://signed/proof');
  });
}
