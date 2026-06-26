import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/appointments/[id]/deposit-screenshot.dart' as view_route;
import '../routes/appointments/[id]/deposit.dart' as deposit_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late DepositService service;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;
  late String salonToken; // provider managing provider1
  late String salonAccountId; // provider1's account id
  late String otherSalonToken; // provider managing provider2

  Future<void> seed(
    String id, {
    String userId = 'user_A',
    String status = 'pending',
    String? screenshot,
  }) => appts.create({
    'id': id,
    'userId': userId,
    'providerId': 'provider1',
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
    'durationMinutes': 60,
    'status': status,
    'totalPrice': 15000,
    'depositAmount': 4500,
    'balanceDue': 10500,
    'depositScreenshotUrl': screenshot,
    'createdAt': DateTime.utc(2030).toIso8601String(),
  });

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    service = DepositService(appts, providerAuth, const FakeStorageService());
    final p1 = await providerAuth.register(
      phoneNumber: '+2250500000080',
      businessName: 'S1',
      businessType: 'salon',
      providerId: 'provider1',
    );
    final p2 = await providerAuth.register(
      phoneNumber: '+2250500000081',
      businessName: 'S2',
      businessType: 'salon',
      providerId: 'provider2',
    );
    salonAccountId = p1.provider!.id;
    salonToken = tokens
        .issueAccessToken(subject: salonAccountId, role: 'provider')
        .token;
    otherSalonToken = tokens
        .issueAccessToken(subject: p2.provider!.id, role: 'provider')
        .token;
  });

  group('DepositService.submit', () {
    test('owner attaches a screenshot key under their own prefix', () async {
      await seed('a1');
      final r = await service.submit('user_A', 'a1', 'deposit/user_A/x.jpg');
      expect(r.ok, isTrue);
      expect((r.data! as Map)['depositScreenshotUrl'], 'deposit/user_A/x.jpg');
    });

    test('rejects foreign key / non-owner / non-pending / unknown', () async {
      await seed('a1');
      expect(
        (await service.submit('user_A', 'a1', 'deposit/user_B/x.jpg')).error,
        'invalid_input', // not under the caller's prefix
      );
      expect(
        (await service.submit('user_B', 'a1', 'deposit/user_B/x.jpg')).error,
        'forbidden', // not the owner
      );
      await seed('done', status: 'completed');
      expect(
        (await service.submit('user_A', 'done', 'deposit/user_A/x.jpg')).error,
        'invalid_state',
      );
      expect(
        (await service.submit('user_A', 'nope', 'deposit/user_A/x.jpg')).error,
        'not_found',
      );
    });
  });

  group('DepositService.screenshotUrl', () {
    test('owner consumer + owning salon can view; a stranger cannot', () async {
      await seed('a1', screenshot: 'deposit/user_A/x.jpg');
      expect(
        (await service.screenshotUrl('a1', sub: 'user_A', role: 'user')).ok,
        isTrue,
      );
      // The salon that owns provider1.
      expect(
        (await service.screenshotUrl(
          'a1',
          sub: salonAccountId,
          role: 'provider',
        )).ok,
        isTrue,
      );
      // Another consumer → forbidden.
      expect(
        (await service.screenshotUrl('a1', sub: 'user_B', role: 'user')).error,
        'forbidden',
      );
    });

    test('404 when there is no screenshot', () async {
      await seed('a1'); // no screenshot
      expect(
        (await service.screenshotUrl('a1', sub: 'user_A', role: 'user')).error,
        'not_found',
      );
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<DepositService>()).thenReturn(service);
      return context;
    }

    Request req(String method, {String? bearer, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/appointments/a1/deposit'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : '{"screenshotKey":"deposit/user_A/x.jpg"}',
    );

    test(
      'POST deposit: 200 owner; 403 other; 401 none; provider → 403; 405',
      () async {
        await seed('a1');
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: accessA, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: accessB, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.forbidden, // not the owner
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', body: {})),
            'a1',
          )).statusCode,
          HttpStatus.unauthorized,
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: salonToken, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.forbidden, // provider can't submit a deposit
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('GET', bearer: accessA)),
            'a1',
          )).statusCode,
          HttpStatus.methodNotAllowed,
        );
      },
    );

    test(
      'GET deposit-screenshot: consumer + salon 200; other salon 403; 404',
      () async {
        await seed('a1', screenshot: 'deposit/user_A/x.jpg');
        Request get(String? bearer) => Request.get(
          Uri.parse('http://localhost/appointments/a1/deposit-screenshot'),
          headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
        );
        expect(
          (await view_route.onRequest(ctx(get(accessA)), 'a1')).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await view_route.onRequest(ctx(get(salonToken)), 'a1')).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await view_route.onRequest(
            ctx(get(otherSalonToken)),
            'a1',
          )).statusCode,
          HttpStatus.forbidden,
        );
      },
    );
  });
}
