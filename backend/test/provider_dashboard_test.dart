import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_dashboard_service.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/dashboard.dart' as dashboard;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late ProviderDashboardService service;
  final tokens = TokenService(secret: 'test-secret');
  late String accountId; // linked to provider1
  late String token;

  final now = DateTime.now().toUtc();
  DateTime todayAt(int h) => DateTime.utc(now.year, now.month, now.day, h);

  Future<void> seed({
    required String id,
    String status = 'confirmed',
    required DateTime when,
    num price = 10000,
    String providerId = 'provider1',
  }) => appts.create({
    'id': id,
    'userId': 'u1',
    'providerId': providerId,
    'serviceIds': ['s1'],
    'artistId': null,
    'appointmentDate': when.toUtc().toIso8601String(),
    'status': status,
    'totalPrice': price,
    'depositAmount': 0,
    'balanceDue': price,
    'cancellationWindowHours': 24,
    'clientName': null,
    'clientPhone': null,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': now.toIso8601String(),
  });

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    service = ProviderDashboardService(providerAuth, appts);
    final reg = await providerAuth.register(
      phoneNumber: '+2250500000020',
      businessName: 'X',
      businessType: 'salon',
      providerId: 'provider1',
    );
    accountId = reg.provider!.id;
    token = tokens.issueAccessToken(subject: accountId, role: 'provider').token;
  });

  group('ProviderDashboardService', () {
    test('computes the six stats with the agreed status filters', () async {
      await seed(id: 'a1', status: 'confirmed', when: todayAt(9), price: 10000);
      await seed(id: 'a2', status: 'completed', when: todayAt(11), price: 5000);
      await seed(id: 'a3', status: 'pending', when: todayAt(14), price: 7000);
      await seed(id: 'a4', status: 'cancelled', when: todayAt(16), price: 9000);
      // Far-future confirmed: only counts toward totalAppointments.
      await seed(
        id: 'a5',
        status: 'confirmed',
        when: now.add(const Duration(days: 40)),
        price: 99999,
      );

      final r = await service.statsFor(accountId, 'provider1');
      expect(r.ok, isTrue);
      final s = r.data!;
      expect(s['todayAppointments'], 3); // a1, a2, a3 (a4 cancelled excluded)
      expect(s['pendingRequests'], 1); // a3
      expect(s['todayRevenue'], 15000); // a1 + a2 (confirmed + completed)
      expect(s['weekRevenue'], 15000);
      expect(s['monthRevenue'], 15000);
      expect(s['totalAppointments'], 5); // all, incl. cancelled + far-future
    });

    test('ownership: unlinked account and cross-salon → forbidden', () async {
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000021',
        businessName: 'Y',
        businessType: 'salon',
      );
      expect(
        (await service.statsFor(reg.provider!.id, 'provider1')).error,
        'forbidden',
      );
      expect(
        (await service.statsFor(accountId, 'provider2')).error,
        'forbidden',
      );
    });
  });

  group('route', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ProviderDashboardService>()).thenReturn(service);
      return context;
    }

    Request get(String path, {String? bearer}) => Request.get(
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
    );

    test(
      'GET → 200 with stats; no token → 401; cross-salon → 403; POST → 405',
      () async {
        final ok = await dashboard.onRequest(
          ctx(get('/providers/provider1/dashboard', bearer: token)),
          'provider1',
        );
        expect(ok.statusCode, HttpStatus.ok);
        expect((await ok.json() as Map)['todayAppointments'], isA<int>());

        final noAuth = await dashboard.onRequest(
          ctx(get('/providers/provider1/dashboard')),
          'provider1',
        );
        expect(noAuth.statusCode, HttpStatus.unauthorized);

        final cross = await dashboard.onRequest(
          ctx(get('/providers/provider2/dashboard', bearer: token)),
          'provider2',
        );
        expect(cross.statusCode, HttpStatus.forbidden);

        final post = await dashboard.onRequest(
          ctx(
            Request.post(
              Uri.parse('http://localhost/providers/provider1/dashboard'),
              headers: {'Authorization': 'Bearer $token'},
            ),
          ),
          'provider1',
        );
        expect(post.statusCode, HttpStatus.methodNotAllowed);
      },
    );
  });
}
