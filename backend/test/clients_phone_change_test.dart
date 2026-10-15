import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/clients/[clientId]/index.dart' as card_route;
import 'http/observed.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// Lands [beforeWrite] between the service's read of the card and the
/// repository's write — exactly where a concurrent request would land.
class _RacingClientsRepository extends InMemoryClientsRepository {
  _RacingClientsRepository({required super.appointments});

  Future<void> Function()? beforeWrite;

  @override
  Future<GuestPhoneChange> changeGuestPhone(
    String providerId,
    String clientId,
    String phone,
  ) async {
    final race = beforeWrite;
    beforeWrite = null;
    if (race != null) await race();
    return super.changeGuestPhone(providerId, clientId, phone);
  }
}

/// docs/design/phone-leftovers.md §8 — « Modifier le numéro d'une fiche
/// client », decided 2026-10-15: the history follows the number; a card
/// linked to an account keeps the account's number; a number already on
/// another card is refused with that card's id; no merge.
///
/// `PATCH /providers/{id}/clients/{clientId}` takes `phone` beside `tags`.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late _RacingClientsRepository clientsRepo;
  late InMemoryProviderAuditLogRepository audit;
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late InMemoryAuthRepository users;
  late ClientsService service;
  late String accountId; // manages provider1
  late String otherAccountId; // manages provider2 (cross-salon negatives)

  // +225 numbers: the code, then exactly 10 digits.
  const oldPhone = '+2250700000101';
  const newPhone = '+2250500000202';

  Future<void> seedAppointment({
    required String id,
    String userId = 'manual',
    String? clientPhone = oldPhone,
    String status = 'completed',
    String providerId = 'provider1',
    DateTime? when,
  }) => appts.create({
    'id': id,
    'userId': userId,
    'providerId': providerId,
    'serviceIds': ['s1'],
    'artistId': null,
    'appointmentDate': (when ?? DateTime.utc(2026, 6, 1, 10)).toIso8601String(),
    'status': status,
    'totalPrice': 10000,
    'depositAmount': 0,
    'balanceDue': 10000,
    'cancellationWindowHours': 24,
    'clientName': 'Tante Marie',
    'clientPhone': clientPhone,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.utc(2026).toIso8601String(),
  });

  Future<String> guestCard(String phone, {String name = 'Tante Marie'}) async {
    final r = await service.addClient(
      accountId,
      'provider1',
      name: name,
      phone: phone,
    );
    return r.data!['id'] as String;
  }

  Future<String> linkedCard(String phone) async {
    final otp = await users.requestOtp(phone);
    final uid = (await users.verifyOtp(phone, otp.devCode!)).user!.id;
    await service.recordBooking({'providerId': 'provider1', 'userId': uid});
    final card = await clientsRepo.byUserId('provider1', uid);
    return card!['id'] as String;
  }

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    clientsRepo = _RacingClientsRepository(appointments: appts);
    audit = InMemoryProviderAuditLogRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    users = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
    service = ClientsService(
      providerAuth,
      MembershipService(InMemoryMembershipRepository(), providerAuth),
      users,
      clientsRepo,
      appts,
      audit,
    );
    accountId = (await providerAuth.register(
      email: 'owner1@test.pro',
      authProvider: 'google',
      googleSub: 'sub-owner-1',
      phoneNumber: '+2250500000030',
      businessName: 'Salon Un',
      businessType: 'salon',
      providerId: 'provider1',
    )).provider!.id;
    otherAccountId = (await providerAuth.register(
      email: 'owner2@test.pro',
      authProvider: 'google',
      googleSub: 'sub-owner-2',
      phoneNumber: '+2250500000031',
      businessName: 'Salon Deux',
      businessType: 'salon',
      providerId: 'provider2',
    )).provider!.id;
  });

  group('PATCH /providers/{id}/clients/{clientId} — phone', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ClientsService>()).thenReturn(service);
      return context;
    }

    String proTok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'provider').token;

    /// Through `observabilityMiddleware`, as production answers it: a throw
    /// comes back as the 500 a client would see, not as a test error.
    Future<Response> send(
      String clientId, {
      String method = 'PATCH',
      String? json,
      String providerId = 'provider1',
      String? token,
    }) => observed(
      (c) => card_route.onRequest(c, providerId, clientId),
      ctx(
        Request(
          method,
          Uri.parse('http://localhost/providers/$providerId/clients/$clientId'),
          headers: {
            'Authorization': 'Bearer ${token ?? proTok(accountId)}',
            'content-type': 'application/json',
          },
          body: json,
        ),
      ),
    );

    Future<Map<String, dynamic>> bodyOf(Response r) async =>
        (await r.json() as Map).cast<String, dynamic>();

    Future<Map<String, dynamic>> stored(String clientId) async =>
        (await clientsRepo.byId('provider1', clientId))!;

    Future<String?> phoneOfAppointment(String id) async =>
        (await appts.byId(id))!['clientPhone'] as String?;

    test('a guest card takes the new number, and its history follows it — '
        'this salon\'s manual bookings only', () async {
      final id = await guestCard(oldPhone);
      await seedAppointment(id: 'm1', when: DateTime.utc(2026, 6, 1, 10));
      await seedAppointment(
        id: 'm2',
        status: 'noShow',
        when: DateTime.utc(2026, 6, 2, 10),
      );
      await seedAppointment(id: 'm3', when: DateTime.utc(2026, 6, 3, 10));
      // ANOTHER salon's walk-in with the same number — never theirs to move.
      await seedAppointment(id: 'x1', providerId: 'provider2');
      // A consumer's own booking that happens to carry the number.
      await seedAppointment(id: 'u1', userId: 'user_consumer');

      final before = (await service.card(accountId, 'provider1', id)).data!;
      expect(before['stats'], containsPair('visits', 2));
      expect(before['stats'], containsPair('noShows', 1));

      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      // The card, as GET returns it.
      expect(body['id'], id);
      expect(body['phone'], newPhone);
      expect(body['stats'], before['stats']);
      expect(body['notes'], isA<List<dynamic>>());

      expect((await stored(id))['phone'], newPhone);
      for (final m in ['m1', 'm2', 'm3']) {
        expect(await phoneOfAppointment(m), newPhone, reason: m);
      }
      expect(await phoneOfAppointment('x1'), oldPhone, reason: 'T45');
      expect(await phoneOfAppointment('u1'), oldPhone, reason: 'not manual');

      // The card's counts are the same through every reader.
      final after = (await service.card(accountId, 'provider1', id)).data!;
      expect(after['stats'], before['stats']);
      final visits = await service.visits(accountId, 'provider1', id);
      expect(visits.data!['total'], 3);
      final listed =
          ((await service.list(accountId, 'provider1')).data!['items'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((c) => c['id'] == id);
      expect(listed['visits'], 2);
      expect(listed['noShows'], 1);
    });

    test('the change is audited — ids only, never a number', () async {
      final id = await guestCard(oldPhone);
      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.ok);

      final entries = await audit.entriesFor('provider1');
      final change = entries.singleWhere(
        (e) => e['action'] == 'client.phone_changed',
      );
      expect(change['actorAccountId'], accountId);
      expect(change['targetId'], id);
      final dump = jsonEncode(entries);
      for (final digits in ['0700000101', '0500000202']) {
        expect(dump, isNot(contains(digits)), reason: 'PII in the audit log');
      }
    });

    test('a card linked to an account keeps the account\'s number → 409 '
        'client_linked, nothing changes', () async {
      const accountPhone = '+2250100000303';
      final id = await linkedCard(accountPhone);
      await seedAppointment(id: 'm1', clientPhone: accountPhone);

      for (final phone in [newPhone, '', 'abc']) {
        final res = await send(id, json: jsonEncode({'phone': phone}));
        expect(res.statusCode, HttpStatus.conflict, reason: phone);
        expect(await bodyOf(res), {'error': 'client_linked'}, reason: phone);
      }
      expect((await stored(id))['phone'], accountPhone);
      expect(await phoneOfAppointment('m1'), accountPhone);

      // Its tags stay editable.
      final tags = await send(
        id,
        json: jsonEncode({
          'tags': ['VIP'],
        }),
      );
      expect(tags.statusCode, HttpStatus.ok);
      expect((await stored(id))['tags'], ['VIP']);
    });

    /// An erased account's card (T48: `anonymizeUser` clears its userId and
    /// phone, its name becomes « Client »). Not linked, no number — the
    /// linked rule alone would let a salon attach a number to it again, and
    /// with it re-identify the erased person's tags and notes. Refused.
    test('an erased client\'s anonymised card takes no number → 409 '
        'client_anonymized, nothing changes', () async {
      const accountPhone = '+2250100000404';
      final otp = await users.requestOtp(accountPhone);
      final uid = (await users.verifyOtp(accountPhone, otp.devCode!)).user!.id;
      await service.recordBooking({'providerId': 'provider1', 'userId': uid});
      final id =
          (await clientsRepo.byUserId('provider1', uid))!['id'] as String;
      await service.anonymizeUser(uid);
      expect((await stored(id))['userId'], isNull);
      expect((await stored(id))['phone'], isNull);

      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'client_anonymized'});
      expect((await stored(id))['phone'], isNull);
      final actions = [
        for (final e in await audit.entriesFor('provider1')) e['action'],
      ];
      expect(actions, isNot(contains('client.phone_changed')));
    });

    test('an invalid number → 400 invalid_phone, empty included; nothing '
        'changes', () async {
      final id = await guestCard(oldPhone);
      await seedAppointment(id: 'm1');
      for (final phone in [
        '',
        '   ',
        '+2250700000', // 7 digits after +225 — a CI number has 10
        '07 00 00 01 01', // not normalised: the clients send E.164
        '+225070000010199',
      ]) {
        final res = await send(id, json: jsonEncode({'phone': phone}));
        expect(res.statusCode, HttpStatus.badRequest, reason: phone);
        expect((await bodyOf(res))['error'], 'invalid_phone', reason: phone);
      }
      expect((await stored(id))['phone'], oldPhone);
      expect(await phoneOfAppointment('m1'), oldPhone);
    });

    test('the same number → 200, nothing to do (no audit row)', () async {
      final id = await guestCard(oldPhone);
      final res = await send(id, json: jsonEncode({'phone': oldPhone}));
      expect(res.statusCode, HttpStatus.ok);
      expect((await bodyOf(res))['phone'], oldPhone);
      final actions = [
        for (final e in await audit.entriesFor('provider1')) e['action'],
      ];
      expect(actions, isNot(contains('client.phone_changed')));
    });

    test('a number already on another card of this salon → 409 '
        'client_exists + that card\'s id; nothing changes', () async {
      final id = await guestCard(oldPhone);
      final other = await guestCard(newPhone, name: 'Awa');
      await seedAppointment(id: 'm1');

      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {'error': 'client_exists', 'clientId': other});
      expect((await stored(id))['phone'], oldPhone);
      expect((await stored(other))['phone'], newPhone);
      expect(await phoneOfAppointment('m1'), oldPhone);
    });

    test('the same number on ANOTHER salon\'s card is no conflict', () async {
      final id = await guestCard(oldPhone);
      await service.addClient(
        otherAccountId,
        'provider2',
        name: 'Ailleurs',
        phone: newPhone,
      );
      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.ok);
    });

    test(
      'cross-salon → 403 (T45); a foreign or unknown clientId → 404',
      () async {
        final id = await guestCard(oldPhone);
        final json = jsonEncode({'phone': newPhone});

        final foreign = await send(
          id,
          json: json,
          token: proTok(otherAccountId),
        );
        expect(foreign.statusCode, HttpStatus.forbidden);

        // The other owner, on THEIR salon, naming provider1's card.
        final leak = await send(
          id,
          json: json,
          providerId: 'provider2',
          token: proTok(otherAccountId),
        );
        expect(leak.statusCode, HttpStatus.notFound);

        expect(
          (await send('client_ghost', json: json)).statusCode,
          HttpStatus.notFound,
        );
        expect((await stored(id))['phone'], oldPhone);
      },
    );

    test('405 unchanged for other verbs', () async {
      final id = await guestCard(oldPhone);
      for (final method in ['PUT', 'POST', 'DELETE']) {
        final res = await send(id, method: method, json: '{}');
        expect(res.statusCode, HttpStatus.methodNotAllowed, reason: method);
      }
    });

    test('neither phone nor tags → 400 invalid_tags (as before); a phone of '
        'the wrong JSON type → 400 invalid_body, not 500', () async {
      final id = await guestCard(oldPhone);
      for (final json in ['{}', '{"phone": null}', '{"tags": null}']) {
        final res = await send(id, json: json);
        expect(res.statusCode, HttpStatus.badRequest, reason: json);
        expect((await bodyOf(res))['error'], 'invalid_tags', reason: json);
      }
      final typed = await send(id, json: '{"phone": 2250500000202}');
      expect(typed.statusCode, HttpStatus.badRequest);
      expect((await bodyOf(typed))['error'], 'invalid_body');
      expect((await stored(id))['phone'], oldPhone);
    });

    test(
      'phone + tags together: both land; an invalid tag lands neither',
      () async {
        final id = await guestCard(oldPhone);
        final bad = await send(
          id,
          json: jsonEncode({
            'phone': newPhone,
            'tags': ['x' * 30],
          }),
        );
        expect(bad.statusCode, HttpStatus.badRequest);
        expect((await bodyOf(bad))['error'], 'invalid_tags');
        expect((await stored(id))['phone'], oldPhone);

        final ok = await send(
          id,
          json: jsonEncode({
            'phone': newPhone,
            'tags': ['VIP'],
          }),
        );
        expect(ok.statusCode, HttpStatus.ok);
        expect((await stored(id))['phone'], newPhone);
        expect((await stored(id))['tags'], ['VIP']);
      },
    );

    test('tags alone behave as before — and answer with the card', () async {
      final id = await guestCard(oldPhone);
      final res = await send(
        id,
        json: jsonEncode({
          'tags': ['VIP', ' VIP ', 'Fidèle'],
        }),
      );
      expect(res.statusCode, HttpStatus.ok);
      final body = await bodyOf(res);
      expect(body['tags'], ['VIP', 'Fidèle']);
      expect(body['phone'], oldPhone);
      expect(body['stats'], isA<Map<String, dynamic>>());
    });

    test('a race lost to another card answers 409 client_exists with its id, '
        'never 500 — and moves nothing', () async {
      final id = await guestCard(oldPhone);
      await seedAppointment(id: 'm1');
      // Another request files the number between this one's read and write.
      clientsRepo.beforeWrite = () async {
        await clientsRepo.create({
          'id': 'client_racer',
          'providerId': 'provider1',
          'userId': null,
          'displayName': 'Arrivée entre-temps',
          'phone': newPhone,
          'tags': const <String>[],
          'lastVisitAt': null,
          'createdAt': DateTime.utc(2026).toIso8601String(),
        });
      };
      final res = await send(id, json: jsonEncode({'phone': newPhone}));
      expect(res.statusCode, HttpStatus.conflict);
      expect(await bodyOf(res), {
        'error': 'client_exists',
        'clientId': 'client_racer',
      });
      expect((await stored(id))['phone'], oldPhone);
      expect(await phoneOfAppointment('m1'), oldPhone);
    });
  });

  group('ClientsService.updateClient', () {
    test('no clients.view in the salon → forbidden; nothing changes', () async {
      final id = await guestCard(oldPhone);
      final r = await service.updateClient(
        otherAccountId,
        'provider1',
        id,
        phone: newPhone,
      );
      expect(r.error, 'forbidden');
      expect((await clientsRepo.byId('provider1', id))!['phone'], oldPhone);
    });

    test('unknown card → not_found', () async {
      final r = await service.updateClient(
        accountId,
        'provider1',
        'client_ghost',
        phone: newPhone,
      );
      expect(r.error, 'not_found');
    });

    test('linked → client_linked, before the number is even read', () async {
      final id = await linkedCard('+2250100000303');
      for (final phone in [newPhone, 'pas un numéro']) {
        final r = await service.updateClient(
          accountId,
          'provider1',
          id,
          phone: phone,
        );
        expect(r.error, 'client_linked', reason: phone);
      }
    });

    test('invalid → invalid_phone; surrounding blanks are trimmed', () async {
      final id = await guestCard(oldPhone);
      final bad = await service.updateClient(
        accountId,
        'provider1',
        id,
        phone: '+225070',
      );
      expect(bad.error, 'invalid_phone');
      final padded = await service.updateClient(
        accountId,
        'provider1',
        id,
        phone: ' $newPhone ',
      );
      expect(padded.ok, isTrue);
      expect(padded.data!['phone'], newPhone);
    });

    test(
      'taken → client_exists + clientId (the POST …/clients shape)',
      () async {
        final id = await guestCard(oldPhone);
        final other = await guestCard(newPhone);
        final r = await service.updateClient(
          accountId,
          'provider1',
          id,
          phone: newPhone,
        );
        expect(r.ok, isFalse);
        expect(r.error, 'client_exists');
        expect(r.data, {'clientId': other});
      },
    );

    test('changed → the card (GET shape) + one client.phone_changed row; '
        'the read-back is audited like any card read (T46)', () async {
      final id = await guestCard(oldPhone);
      final r = await service.updateClient(
        accountId,
        'provider1',
        id,
        phone: newPhone,
      );
      expect(r.ok, isTrue);
      expect(r.data!.keys, containsAll(['id', 'phone', 'stats', 'notes']));
      final actions = [
        for (final e in await audit.entriesFor('provider1')) e['action'],
      ];
      expect(actions.where((a) => a == 'client.phone_changed'), hasLength(1));
      expect(actions.first, 'clients.view');
      final change = (await audit.entriesFor(
        'provider1',
      )).singleWhere((e) => e['action'] == 'client.phone_changed');
      expect(change['meta'], isEmpty, reason: 'ids only — no number');
    });
  });

  group('InMemoryClientsRepository.changeGuestPhone — the twin of the '
      'Postgres transaction', () {
    Future<Map<String, dynamic>> card(
      String id, {
      String providerId = 'provider1',
      String? userId,
      String? phone = oldPhone,
    }) => clientsRepo.create({
      'id': id,
      'providerId': providerId,
      'userId': userId,
      'displayName': 'X',
      'phone': phone,
      'tags': const <String>[],
      'lastVisitAt': null,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    });

    test('changed: the card and THIS salon\'s manual bookings with the old '
        'number — nothing else', () async {
      await card('g1');
      await seedAppointment(id: 'm1');
      await seedAppointment(id: 'm2', status: 'cancelled');
      await seedAppointment(id: 'x1', providerId: 'provider2');
      await seedAppointment(id: 'u1', userId: 'user_consumer');
      await seedAppointment(id: 'o1', clientPhone: '+2250700000999');

      final r = await clientsRepo.changeGuestPhone('provider1', 'g1', newPhone);
      expect(r.outcome, GuestPhoneOutcome.changed);
      expect(r.client!['phone'], newPhone);
      expect((await clientsRepo.byId('provider1', 'g1'))!['phone'], newPhone);
      final phones = {
        for (final id in ['m1', 'm2', 'x1', 'u1', 'o1'])
          id: (await appts.byId(id))!['clientPhone'],
      };
      expect(phones, {
        'm1': newPhone,
        'm2': newPhone,
        'x1': oldPhone,
        'u1': oldPhone,
        'o1': '+2250700000999',
      });
    });

    test('a phone-less card takes a number without adopting the salon\'s '
        'phone-less walk-ins', () async {
      await card('anon', phone: null); // e.g. an erased account's card (T48)
      await seedAppointment(id: 'w1', clientPhone: null);
      final r = await clientsRepo.changeGuestPhone(
        'provider1',
        'anon',
        newPhone,
      );
      expect(r.outcome, GuestPhoneOutcome.changed);
      expect((await appts.byId('w1'))!['clientPhone'], isNull);
    });

    test('notFound for another salon\'s card (T45); linked; unchanged; '
        'taken — each writes nothing', () async {
      await card('g1');
      await card('l1', userId: 'user_1', phone: '+2250100000303');
      await card('g2', phone: newPhone);
      await seedAppointment(id: 'm1');

      final foreign = await clientsRepo.changeGuestPhone(
        'provider2',
        'g1',
        '+2250500000404',
      );
      expect(foreign.outcome, GuestPhoneOutcome.notFound);

      final linked = await clientsRepo.changeGuestPhone(
        'provider1',
        'l1',
        '+2250500000404',
      );
      expect(linked.outcome, GuestPhoneOutcome.linked);
      expect(
        (await clientsRepo.byId('provider1', 'l1'))!['phone'],
        '+2250100000303',
      );

      final same = await clientsRepo.changeGuestPhone(
        'provider1',
        'g1',
        oldPhone,
      );
      expect(same.outcome, GuestPhoneOutcome.unchanged);

      final taken = await clientsRepo.changeGuestPhone(
        'provider1',
        'g1',
        newPhone,
      );
      expect(taken.outcome, GuestPhoneOutcome.taken);
      expect(taken.takenBy, 'g2');

      expect((await clientsRepo.byId('provider1', 'g1'))!['phone'], oldPhone);
      expect((await appts.byId('m1'))!['clientPhone'], oldPhone);
    });

    test('without its appointments twin it refuses loudly rather than strand '
        'the history', () async {
      final bare = InMemoryClientsRepository();
      await bare.create({
        'id': 'g1',
        'providerId': 'provider1',
        'userId': null,
        'displayName': 'X',
        'phone': oldPhone,
        'tags': const <String>[],
        'lastVisitAt': null,
        'createdAt': DateTime.utc(2026).toIso8601String(),
      });
      await expectLater(
        bare.changeGuestPhone('provider1', 'g1', newPhone),
        throwsStateError,
      );
      expect((await bare.byId('provider1', 'g1'))!['phone'], oldPhone);
    });
  });
}
