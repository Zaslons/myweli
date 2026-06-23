import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/index.dart' as detail;
import '../../routes/appointments/index.dart' as list;

class _MockRequestContext extends Mock implements RequestContext {}

String _futureDate() =>
    DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String();

void main() {
  late InMemoryAppointmentRepository appts;
  late BookingService booking;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;

  setUp(() {
    appts = InMemoryAppointmentRepository();
    booking = BookingService(InMemoryProvidersRepository(), appts);
  });

  group('BookingService (server-authoritative pricing)', () {
    test('prices from the provider + applies the deposit policy', () async {
      // provider2 (Élégance) requires a 50% deposit; service4 = 25000.
      final res = await booking.book(
        userId: 'user_A',
        providerId: 'provider2',
        serviceIds: const ['service4'],
        appointmentDateTime: DateTime.now().add(const Duration(days: 2)),
      );
      expect(res.ok, isTrue);
      expect(res.appointment!['totalPrice'], 25000);
      expect(res.appointment!['depositAmount'], 12500);
      expect(res.appointment!['balanceDue'], 12500);
      expect(res.appointment!['status'], 'pending');
    });

    test('no deposit when the provider does not require one', () async {
      // provider1 service1 = 15000, no deposit.
      final res = await booking.book(
        userId: 'user_A',
        providerId: 'provider1',
        serviceIds: const ['service1'],
        appointmentDateTime: DateTime.now().add(const Duration(days: 2)),
      );
      expect(res.appointment!['totalPrice'], 15000);
      expect(res.appointment!['depositAmount'], 0);
    });

    test('rejects unknown provider / service / empty selection', () async {
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'nope',
          serviceIds: const ['service1'],
          appointmentDateTime: DateTime.now(),
        )).error,
        'provider_not_found',
      );
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'provider1',
          serviceIds: const ['not_a_service'],
          appointmentDateTime: DateTime.now(),
        )).error,
        'invalid_service',
      );
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'provider1',
          serviceIds: const [],
          appointmentDateTime: DateTime.now(),
        )).error,
        'no_services',
      );
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<BookingService>()).thenReturn(booking);
      when(() => context.read<AppointmentRepository>()).thenReturn(appts);
      return context;
    }

    Request bookReq(String token, Map<String, Object?> body) => Request.post(
      Uri.parse('http://localhost/appointments'),
      headers: {'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );

    Future<Map<String, dynamic>> jsonOf(Response r) async =>
        await r.json() as Map<String, dynamic>;

    test('POST without a token → 401', () async {
      final res = await list.onRequest(
        ctx(
          Request.post(
            Uri.parse('http://localhost/appointments'),
            body: jsonEncode({'providerId': 'provider1'}),
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('POST books a pending, server-priced appointment → 201', () async {
      final res = await list.onRequest(
        ctx(
          bookReq(accessA, {
            'providerId': 'provider1',
            'serviceIds': ['service1'],
            'appointmentDateTime': _futureDate(),
            // A hostile client price is ignored — the server computes it.
            'totalPrice': 1,
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.created);
      final body = await jsonOf(res);
      expect(body['userId'], 'user_A');
      expect(body['totalPrice'], 15000);
      expect(body['status'], 'pending');
    });

    test('GET lists only the caller’s appointments', () async {
      await list.onRequest(
        ctx(
          bookReq(accessA, {
            'providerId': 'provider1',
            'serviceIds': ['service1'],
            'appointmentDateTime': _futureDate(),
          }),
        ),
      );
      await list.onRequest(
        ctx(
          bookReq(accessB, {
            'providerId': 'provider1',
            'serviceIds': ['service1'],
            'appointmentDateTime': _futureDate(),
          }),
        ),
      );

      final res = await list.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/appointments'),
            headers: {'Authorization': 'Bearer $accessA'},
          ),
        ),
      );
      final body = await jsonOf(res);
      expect(body['total'], 1);
      expect((body['items'] as List).single['userId'], 'user_A');
    });

    test('GET /{id} enforces ownership (403) + 404 for unknown', () async {
      final created = await jsonOf(
        await list.onRequest(
          ctx(
            bookReq(accessA, {
              'providerId': 'provider1',
              'serviceIds': ['service1'],
              'appointmentDateTime': _futureDate(),
            }),
          ),
        ),
      );
      final id = created['id'] as String;

      final mine = await detail.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/appointments/$id'),
            headers: {'Authorization': 'Bearer $accessA'},
          ),
        ),
        id,
      );
      expect(mine.statusCode, HttpStatus.ok);

      final theirs = await detail.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/appointments/$id'),
            headers: {'Authorization': 'Bearer $accessB'},
          ),
        ),
        id,
      );
      expect(theirs.statusCode, HttpStatus.forbidden);

      final missing = await detail.onRequest(
        ctx(
          Request.get(
            Uri.parse('http://localhost/appointments/nope'),
            headers: {'Authorization': 'Bearer $accessA'},
          ),
        ),
        'nope',
      );
      expect(missing.statusCode, HttpStatus.notFound);
    });
  });
}
