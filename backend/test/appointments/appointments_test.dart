import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../../routes/appointments/[id]/index.dart' as detail;
import '../../routes/appointments/index.dart' as list;

class _MockRequestContext extends Mock implements RequestContext {}

/// A future Mon–Sat at [hour]:00 UTC — an open slot in the seed schedule.
DateTime _slotAt(int hour) {
  final now = DateTime.now().toUtc();
  var d = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 7));
  while (d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return DateTime.utc(d.year, d.month, d.day, hour);
}

void main() {
  late InMemoryAppointmentRepository appts;
  late InMemoryProvidersRepository providers;
  late BookingService booking;
  late InMemoryProviderAuthRepository providerAuth;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;

  setUp(() {
    providers = InMemoryProvidersRepository();
    appts = InMemoryAppointmentRepository();
    booking = BookingService(providers, appts, SlotService(providers, appts));
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
  });

  /// Registers a provider account (optionally linked to [providerId]) and
  /// returns a provider-role access token for it.
  Future<String> providerToken(String phone, {String? providerId}) async {
    final reg = await providerAuth.register(
      phoneNumber: phone,
      businessName: 'Salon',
      businessType: 'salon',
      providerId: providerId,
    );
    return tokens
        .issueAccessToken(subject: reg.provider!.id, role: 'provider')
        .token;
  }

  Map<String, Object?> bookBody(DateTime when, {String service = 'service1'}) =>
      {
        'providerId': 'provider1',
        'serviceIds': [service],
        'appointmentDateTime': when.toIso8601String(),
      };

  group('BookingService', () {
    test(
      'server prices + applies the deposit policy on an available slot',
      () async {
        // provider2 (Élégance) requires a 50% deposit; service4 = 25000, 90 min.
        final res = await booking.book(
          userId: 'user_A',
          providerId: 'provider2',
          serviceIds: const ['service4'],
          appointmentDateTime: _slotAt(9),
        );
        expect(res.ok, isTrue);
        expect(res.appointment!['totalPrice'], 25000);
        expect(res.appointment!['depositAmount'], 12500);
        expect(res.appointment!['durationMinutes'], 90); // service4 = 90 min
        expect(res.appointment!['status'], 'pending');
      },
    );

    test(
      'a saved deposit policy drives the next booking (server authority)',
      () async {
        final catalog = ProviderCatalogService(providers, providerAuth);
        final reg = await providerAuth.register(
          phoneNumber: '+2250500000099',
          businessName: 'Salon',
          businessType: 'salon',
          providerId: 'provider1',
        );

        // provider1's seed policy has no deposit.
        final before = await booking.book(
          userId: 'user_A',
          providerId: 'provider1',
          serviceIds: const ['service1'],
          appointmentDateTime: _slotAt(9),
        );
        expect(before.appointment!['depositAmount'], 0);
        final total = before.appointment!['totalPrice'] as num;

        // The salon turns on a 40% deposit (with a Mobile Money destination).
        final upd = await catalog
            .updateDepositPolicy(reg.provider!.id, 'provider1', {
              'depositRequired': true,
              'depositPercentage': 0.4,
              'cancellationWindowHours': 24,
              'mobileMoneyOperator': 'wave',
              'mobileMoneyNumber': '+2250700000000',
            });
        expect(upd.ok, isTrue);

        // A new (non-overlapping) booking now carries the 40% deposit — no
        // booking change needed (service1 is 180 min, so 09:00 runs to 12:00).
        final after = await booking.book(
          userId: 'user_B',
          providerId: 'provider1',
          serviceIds: const ['service1'],
          appointmentDateTime: _slotAt(14),
        );
        expect(after.appointment!['depositAmount'], total * 0.4);
        expect(after.appointment!['balanceDue'], total - total * 0.4);
      },
    );

    test('rejects unknown provider / service / empty selection', () async {
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'nope',
          serviceIds: const ['service1'],
          appointmentDateTime: _slotAt(9),
        )).error,
        'provider_not_found',
      );
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'provider1',
          serviceIds: const ['not_a_service'],
          appointmentDateTime: _slotAt(9),
        )).error,
        'invalid_service',
      );
      expect(
        (await booking.book(
          userId: 'u',
          providerId: 'provider1',
          serviceIds: const [],
          appointmentDateTime: _slotAt(9),
        )).error,
        'no_services',
      );
    });

    test(
      'rejects a non-aligned / closed-day time as slot_unavailable',
      () async {
        // 09:15 is not a 30-min opening slot.
        final nonAligned = _slotAt(9).add(const Duration(minutes: 15));
        expect(
          (await booking.book(
            userId: 'u',
            providerId: 'provider1',
            serviceIds: const ['service1'],
            appointmentDateTime: nonAligned,
          )).error,
          'slot_unavailable',
        );
      },
    );

    test(
      'double-booking is prevented (same slot, second client → conflict)',
      () async {
        final slot = _slotAt(14); // service1 is 180 min → 14:00..17:00 fits
        expect(
          (await booking.book(
            userId: 'user_A',
            providerId: 'provider1',
            serviceIds: const ['service1'],
            appointmentDateTime: slot,
          )).ok,
          isTrue,
        );
        expect(
          (await booking.book(
            userId: 'user_B',
            providerId: 'provider1',
            serviceIds: const ['service1'],
            appointmentDateTime: slot,
          )).error,
          'slot_unavailable',
        );
      },
    );
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<BookingService>()).thenReturn(booking);
      when(() => context.read<AppointmentRepository>()).thenReturn(appts);
      when(
        () => context.read<ProviderAuthRepository>(),
      ).thenReturn(providerAuth);
      return context;
    }

    Request getReq(String token, {String query = ''}) => Request.get(
      Uri.parse('http://localhost/appointments$query'),
      headers: {'Authorization': 'Bearer $token'},
    );

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
            body: jsonEncode(bookBody(_slotAt(9))),
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('POST books a pending, server-priced appointment → 201', () async {
      final res = await list.onRequest(
        ctx(
          bookReq(accessA, {
            ...bookBody(_slotAt(9)),
            'totalPrice': 1, // hostile client price — ignored
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.created);
      final body = await jsonOf(res);
      expect(body['userId'], 'user_A');
      expect(body['status'], 'pending');
    });

    test('POST an unavailable slot → 409', () async {
      final res = await list.onRequest(
        ctx(
          bookReq(
            accessA,
            bookBody(_slotAt(9).add(const Duration(minutes: 15))),
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.conflict);
      expect((await jsonOf(res))['error'], 'slot_unavailable');
    });

    test('GET lists only the caller’s appointments', () async {
      await list.onRequest(ctx(bookReq(accessA, bookBody(_slotAt(9)))));
      await list.onRequest(ctx(bookReq(accessB, bookBody(_slotAt(14)))));

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

    test(
      'GET as a provider lists its salon’s appointments (not by user)',
      () async {
        // Two different users book provider1; the linked salon sees both.
        await list.onRequest(ctx(bookReq(accessA, bookBody(_slotAt(9)))));
        await list.onRequest(ctx(bookReq(accessB, bookBody(_slotAt(14)))));
        final token = await providerToken(
          '+2250500000001',
          providerId: 'provider1',
        );

        final res = await list.onRequest(ctx(getReq(token)));

        final body = await jsonOf(res);
        expect(body['total'], 2);
        expect(
          (body['items'] as List).every((a) => a['providerId'] == 'provider1'),
          isTrue,
        );
      },
    );

    test('GET as a provider honors ?status=', () async {
      final booked = await list.onRequest(
        ctx(bookReq(accessA, bookBody(_slotAt(9)))),
      );
      await appts.update((await jsonOf(booked))['id'] as String, {
        'status': 'confirmed',
      });
      await list.onRequest(
        ctx(bookReq(accessB, bookBody(_slotAt(14)))),
      ); // pending
      final token = await providerToken(
        '+2250500000002',
        providerId: 'provider1',
      );

      final res = await list.onRequest(
        ctx(getReq(token, query: '?status=confirmed')),
      );

      final body = await jsonOf(res);
      expect(body['total'], 1);
      expect((body['items'] as List).single['status'], 'confirmed');
    });

    test('GET as an unlinked provider → 403', () async {
      final token = await providerToken('+2250500000003'); // no providerId

      final res = await list.onRequest(ctx(getReq(token)));

      expect(res.statusCode, HttpStatus.forbidden);
      expect((await jsonOf(res))['error'], 'forbidden');
    });

    test('GET /{id} enforces ownership (403) + 404 for unknown', () async {
      final created = await jsonOf(
        await list.onRequest(ctx(bookReq(accessA, bookBody(_slotAt(9))))),
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
