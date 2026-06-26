import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_earnings_service.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/earnings.dart' as earnings;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late ProviderEarningsService service;
  final tokens = TokenService(secret: 'test-secret');
  late String accountId; // linked to provider1
  late String token;

  Future<void> seed({
    required String id,
    String status = 'completed',
    required DateTime when,
    num price = 10000,
  }) => appts.create({
    'id': id,
    'userId': 'u1',
    'providerId': 'provider1',
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
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    service = ProviderEarningsService(providerAuth, appts);
    final reg = await providerAuth.register(
      phoneNumber: '+2250500000040',
      businessName: 'X',
      businessType: 'salon',
      providerId: 'provider1',
    );
    accountId = reg.provider!.id;
    token = tokens.issueAccessToken(subject: accountId, role: 'provider').token;
  });

  group('ProviderEarningsService', () {
    test('totals + transactions cover only completed bookings', () async {
      await seed(id: 'c1', when: DateTime.utc(2030, 6, 10), price: 10000);
      await seed(id: 'c2', when: DateTime.utc(2030, 6, 12), price: 5000);
      await seed(
        id: 'x1',
        status: 'confirmed',
        when: DateTime.utc(2030, 6, 11),
      );
      await seed(id: 'x2', status: 'pending', when: DateTime.utc(2030, 6, 11));

      final r = await service.earningsFor(accountId, 'provider1');
      expect(r.ok, isTrue);
      final d = r.data!;
      expect(d['totalEarnings'], 15000);
      final tx = d['transactions'] as List;
      expect(tx.length, 2); // only c1, c2
      expect(tx.every((t) => t['status'] == 'completed'), isTrue);
      final first = tx.first as Map;
      expect(first['id'], 'transaction_${first['appointmentId']}');
      expect(first['amount'], isA<num>());
    });

    test('honours the date range (inclusive)', () async {
      await seed(id: 'old', when: DateTime.utc(2030, 1, 1), price: 9000);
      await seed(id: 'new', when: DateTime.utc(2030, 6, 15), price: 4000);

      final r = await service.earningsFor(
        accountId,
        'provider1',
        startDate: DateTime.utc(2030, 6, 1),
      );
      expect(r.data!['totalEarnings'], 4000);
      expect((r.data!['transactions'] as List).single['appointmentId'], 'new');
    });

    test('ownership: unlinked + cross-salon → forbidden', () async {
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000041',
        businessName: 'Y',
        businessType: 'salon',
      );
      expect(
        (await service.earningsFor(reg.provider!.id, 'provider1')).error,
        'forbidden',
      );
      expect(
        (await service.earningsFor(accountId, 'provider2')).error,
        'forbidden',
      );
    });
  });

  group('route', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ProviderEarningsService>()).thenReturn(service);
      return context;
    }

    Request get(String path, {String? bearer}) => Request.get(
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
    );

    test('GET → 200 EarningsData; bad date → 400; no token → 401; '
        'cross-salon → 403; POST → 405', () async {
      await seed(id: 'c1', when: DateTime.utc(2030, 6, 10), price: 7000);

      final ok = await earnings.onRequest(
        ctx(get('/providers/provider1/earnings', bearer: token)),
        'provider1',
      );
      expect(ok.statusCode, HttpStatus.ok);
      expect((await ok.json() as Map)['totalEarnings'], 7000);

      final badDate = await earnings.onRequest(
        ctx(get('/providers/provider1/earnings?startDate=nope', bearer: token)),
        'provider1',
      );
      expect(badDate.statusCode, HttpStatus.badRequest);

      final noAuth = await earnings.onRequest(
        ctx(get('/providers/provider1/earnings')),
        'provider1',
      );
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      final cross = await earnings.onRequest(
        ctx(get('/providers/provider2/earnings', bearer: token)),
        'provider2',
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final post = await earnings.onRequest(
        ctx(
          Request.post(
            Uri.parse('http://localhost/providers/provider1/earnings'),
            headers: {'Authorization': 'Bearer $token'},
          ),
        ),
        'provider1',
      );
      expect(post.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
