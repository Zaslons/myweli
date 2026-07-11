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
import '../routes/providers/[id]/clients/[clientId]/notes/[noteId].dart'
    as note_delete_route;
import '../routes/providers/[id]/clients/[clientId]/notes/index.dart'
    as notes_route;
import '../routes/providers/[id]/clients/[clientId]/visits.dart'
    as visits_route;
import '../routes/providers/[id]/clients/index.dart' as clients_route;

class _MockRequestContext extends Mock implements RequestContext {}

/// Module `clients` C1 (docs/design/clients-c1.md): the salon client base —
/// derived from bookings, salon-scoped, audited reads, threats T45–T49.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryClientsRepository clientsRepo;
  late InMemoryProviderAuditLogRepository audit;
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late InMemoryAuthRepository users;
  late ClientsService service;
  late String accountId; // manages provider1
  late String otherAccountId; // manages provider2 (cross-salon negatives)

  Future<String> makeUser(String phone, {String? name}) async {
    final otp = await users.requestOtp(phone);
    final v = await users.verifyOtp(phone, otp.devCode!);
    final user = v.user!;
    if (name != null) await users.updateUser(user.id, name: name);
    return user.id;
  }

  Future<void> seedAppointment({
    required String id,
    String? userId,
    String? clientName,
    String? clientPhone,
    String status = 'completed',
    String providerId = 'provider1',
    DateTime? when,
    num price = 10000,
  }) => appts.create({
    'id': id,
    'userId': userId ?? 'manual',
    'providerId': providerId,
    'serviceIds': ['s1'],
    'artistId': null,
    'appointmentDate': (when ?? DateTime.utc(2026, 6, 1, 10)).toIso8601String(),
    'status': status,
    'totalPrice': price,
    'depositAmount': 0,
    'balanceDue': price,
    'cancellationWindowHours': 24,
    'clientName': clientName,
    'clientPhone': clientPhone,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.utc(2026).toIso8601String(),
  });

  setUp(() async {
    clientsRepo = InMemoryClientsRepository();
    audit = InMemoryProviderAuditLogRepository();
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    users = InMemoryAuthRepository(tokens: tokens, isProd: false);
    service = ClientsService(
      providerAuth,
      MembershipService(InMemoryMembershipRepository(), providerAuth),
      users,
      clientsRepo,
      appts,
      audit,
    );

    final reg1 = await providerAuth.register(
      email: 'owner1@test.pro',
      authProvider: 'google',
      googleSub: 'sub-owner-1',
      phoneNumber: '+2250500000030',
      businessName: 'Salon Un',
      businessType: 'salon',
      providerId: 'provider1',
    );
    accountId = reg1.provider!.id;
    final reg2 = await providerAuth.register(
      email: 'owner2@test.pro',
      authProvider: 'google',
      googleSub: 'sub-owner-2',
      phoneNumber: '+2250500000031',
      businessName: 'Salon Deux',
      businessType: 'salon',
      providerId: 'provider2',
    );
    otherAccountId = reg2.provider!.id;
  });

  group('derived base (recordBooking / recordCompletion)', () {
    test(
      'a consumer booking creates the client row — name + VERIFIED phone',
      () async {
        final uid = await makeUser('+2250700000040', name: 'Aïcha');
        await service.recordBooking({'providerId': 'provider1', 'userId': uid});
        final r = await service.list(accountId, 'provider1');
        final items = r.data!['items'] as List;
        expect(items, hasLength(1));
        final c = items.first as Map;
        expect(c['displayName'], 'Aïcha');
        expect(c['phone'], '+2250700000040'); // OTP-verified → stored
        expect(c['linked'], isTrue);

        // Idempotent — same user again is NOT a second row.
        await service.recordBooking({'providerId': 'provider1', 'userId': uid});
        final r2 = await service.list(accountId, 'provider1');
        expect(r2.data!['items'] as List, hasLength(1));
      },
    );

    test('a manual booking creates a guest row; no phone → no row', () async {
      await service.recordBooking({
        'providerId': 'provider1',
        'userId': 'manual',
        'clientName': 'Tante Marie',
        'clientPhone': '+2250700000041',
      });
      await service.recordBooking({
        'providerId': 'provider1',
        'userId': 'manual',
        'clientName': 'Sans Téléphone',
        'clientPhone': null,
      });
      final r = await service.list(accountId, 'provider1');
      final items = r.data!['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['displayName'], 'Tante Marie');
      expect((items.first as Map)['linked'], isFalse);
    });

    test(
      'T49: an UNVERIFIED contact phone is never stored on the client row',
      () async {
        final uid = await makeUser('+2250700000042');
        // Contact-phone update resets verification (auth overhaul rule).
        await users.updateUser(uid, phone: '+2250700000043');
        await service.recordBooking({'providerId': 'provider1', 'userId': uid});
        final r = await service.list(accountId, 'provider1');
        expect(((r.data!['items'] as List).first as Map)['phone'], isNull);
      },
    );

    test('recordCompletion bumps lastVisitAt (never backwards)', () async {
      await service.recordBooking({
        'providerId': 'provider1',
        'userId': 'manual',
        'clientName': 'G',
        'clientPhone': '+2250700000044',
      });
      final later = {
        'providerId': 'provider1',
        'userId': 'manual',
        'clientPhone': '+2250700000044',
        'appointmentDate': DateTime.utc(2026, 7, 2, 10).toIso8601String(),
      };
      final earlier = {
        ...later,
        'appointmentDate': DateTime.utc(2026, 6, 1, 10).toIso8601String(),
      };
      await service.recordCompletion(later);
      await service.recordCompletion(earlier); // older — must not regress
      final r = await service.list(accountId, 'provider1');
      expect(
        ((r.data!['items'] as List).first as Map)['lastVisitAt'],
        DateTime.utc(2026, 7, 2, 10).toIso8601String(),
      );
    });
  });

  group('list', () {
    late String uid;
    setUp(() async {
      uid = await makeUser('+2250700000050', name: 'Aminata');
      await service.recordBooking({'providerId': 'provider1', 'userId': uid});
      await service.recordBooking({
        'providerId': 'provider1',
        'userId': 'manual',
        'clientName': 'Binta',
        'clientPhone': '+2250701112233',
      });
      await seedAppointment(id: 'v1', userId: uid, status: 'completed');
      await seedAppointment(id: 'v2', userId: uid, status: 'noShow');
      await service.updateTags(
        accountId,
        'provider1',
        ((await service.list(accountId, 'provider1')).data!['items'] as List)
                .cast<Map<String, dynamic>>()
                .firstWhere((c) => c['displayName'] == 'Binta')['id']
            as String,
        ['VIP'],
      );
    });

    test(
      'items carry visits + noShows; page 1 carries availableTags',
      () async {
        final r = await service.list(accountId, 'provider1');
        final items = (r.data!['items'] as List).cast<Map<String, dynamic>>();
        final aminata = items.firstWhere((c) => c['displayName'] == 'Aminata');
        expect(aminata['visits'], 1);
        expect(aminata['noShows'], 1);
        expect(
          r.data!['availableTags'],
          containsAll(['VIP', 'Fidèle', 'À risque']),
        );
      },
    );

    test('search by name and by phone digits; tag filter', () async {
      final byName = await service.list(accountId, 'provider1', query: 'amin');
      expect((byName.data!['items'] as List), hasLength(1));

      final byPhone = await service.list(
        accountId,
        'provider1',
        query: '0701 11',
      );
      expect(
        ((byPhone.data!['items'] as List).first as Map)['displayName'],
        'Binta',
      );

      final byTag = await service.list(accountId, 'provider1', tag: 'VIP');
      expect(
        ((byTag.data!['items'] as List).first as Map)['displayName'],
        'Binta',
      );
    });

    test('pagination clamps pageSize to 50 and paginates', () async {
      final r = await service.list(
        accountId,
        'provider1',
        page: 2,
        pageSize: 999,
      );
      expect(r.data!['pageSize'], 50);
      expect(r.data!['page'], 2);
      expect(r.data!['total'], 2);
      expect(r.data!['items'] as List, isEmpty);
    });

    test('T46: list reads are audited (with the query)', () async {
      await service.list(accountId, 'provider1', query: 'ami');
      final entries = await audit.entriesFor('provider1');
      expect(entries.first['action'], 'clients.list');
      expect((entries.first['meta'] as Map)['query'], 'ami');
      expect(entries.first['actorAccountId'], accountId);
    });

    test('T45: a foreign account is forbidden', () async {
      final r = await service.list(otherAccountId, 'provider1');
      expect(r.error, 'forbidden');
    });
  });

  group('card + visits', () {
    late String clientId;
    late String uid;
    setUp(() async {
      uid = await makeUser('+2250700000060', name: 'Fatou');
      await service.recordBooking({'providerId': 'provider1', 'userId': uid});
      await seedAppointment(
        id: 'c1',
        userId: uid,
        status: 'completed',
        price: 12000,
      );
      await seedAppointment(
        id: 'c2',
        userId: uid,
        status: 'completed',
        price: 8000,
      );
      await seedAppointment(id: 'c3', userId: uid, status: 'noShow');
      await seedAppointment(id: 'c4', userId: uid, status: 'cancelled');
      await seedAppointment(
        id: 'c5',
        userId: uid,
        status: 'confirmed',
        when: DateTime.now().toUtc().add(const Duration(days: 3)),
      );
      final list = await service.list(accountId, 'provider1');
      clientId = ((list.data!['items'] as List).first as Map)['id'] as String;
    });

    test('stats + upcoming + audited read', () async {
      final r = await service.card(accountId, 'provider1', clientId);
      expect(r.ok, isTrue);
      final stats = r.data!['stats'] as Map;
      expect(stats['visits'], 2);
      expect(stats['spentFcfa'], 20000);
      expect(stats['noShows'], 1);
      expect(stats['cancellations'], 1);
      expect((r.data!['upcoming'] as Map)['id'], 'c5');
      final entries = await audit.entriesFor('provider1');
      expect(entries.first['action'], 'clients.view');
      expect(entries.first['targetId'], clientId);
    });

    test('visit history is salon-scoped and paginated (T45)', () async {
      // Same user books at ANOTHER salon — must never appear here.
      await seedAppointment(id: 'x1', userId: uid, providerId: 'provider2');
      final r = await service.visits(
        accountId,
        'provider1',
        clientId,
        pageSize: 3,
      );
      expect(r.data!['total'], 5); // c1..c5 only — x1 excluded
      expect(r.data!['items'] as List, hasLength(3));
    });

    test('foreign clientId → not_found (no existence leak)', () async {
      final r = await service.card(accountId, 'provider1', 'client_ghost');
      expect(r.error, 'not_found');
    });
  });

  group('manual add + tags + notes', () {
    test('addClient dedupes by phone → client_exists + existing id', () async {
      final first = await service.addClient(
        accountId,
        'provider1',
        name: 'Mariam',
        phone: '+2250700000070',
        note: 'Préfère Awa',
      );
      expect(first.ok, isTrue);
      final dup = await service.addClient(
        accountId,
        'provider1',
        name: 'Mariam Bis',
        phone: '+2250700000070',
      );
      expect(dup.error, 'client_exists');
      expect(dup.data!['clientId'], first.data!['id']);

      // The optional first note landed, authored by the owner.
      final card = await service.card(
        accountId,
        'provider1',
        first.data!['id'] as String,
      );
      final notes = card.data!['notes'] as List;
      expect(notes, hasLength(1));
      expect((notes.first as Map)['body'], 'Préfère Awa');
    });

    test(
      'tags: presets + custom ok; >10 or >24 chars → invalid_tags',
      () async {
        final c = await service.addClient(
          accountId,
          'provider1',
          name: 'T',
          phone: '+2250700000071',
        );
        final id = c.data!['id'] as String;
        final ok = await service.updateTags(accountId, 'provider1', id, [
          'VIP',
          'Habituée du samedi',
        ]);
        expect(ok.ok, isTrue);
        expect(ok.data!['tags'], ['VIP', 'Habituée du samedi']);

        final tooMany = await service.updateTags(
          accountId,
          'provider1',
          id,
          List.generate(11, (i) => 't$i'),
        );
        expect(tooMany.error, 'invalid_tags');

        final tooLong = await service.updateTags(accountId, 'provider1', id, [
          'x' * 25,
        ]);
        expect(tooLong.error, 'invalid_tags');
      },
    );

    test('notes: cap at 500 (T47); delete removes', () async {
      final c = await service.addClient(
        accountId,
        'provider1',
        name: 'N',
        phone: '+2250700000072',
      );
      final id = c.data!['id'] as String;
      final tooLong = await service.addNote(
        accountId,
        'provider1',
        id,
        'x' * 501,
      );
      expect(tooLong.error, 'note_too_long');

      final note = await service.addNote(
        accountId,
        'provider1',
        id,
        'Allergique à l’ammoniaque',
      );
      expect(note.ok, isTrue);
      final del = await service.deleteNote(
        accountId,
        'provider1',
        id,
        (note.data!['id']) as String,
      );
      expect(del.ok, isTrue);
      final card = await service.card(accountId, 'provider1', id);
      expect(card.data!['notes'] as List, isEmpty);
    });
  });

  group('enrichment + anonymization', () {
    test('enrichForProvider adds salonClientId + clientNoShowCount', () async {
      final uid = await makeUser('+2250700000080', name: 'K');
      await service.recordBooking({'providerId': 'provider1', 'userId': uid});
      await seedAppointment(id: 'n1', userId: uid, status: 'noShow');
      await seedAppointment(id: 'n2', userId: uid, status: 'noShow');
      await seedAppointment(id: 'n3', userId: uid, status: 'pending');

      final enriched = await service.enrichForProvider(
        'provider1',
        await appts.listForProvider('provider1'),
      );
      final pending = enriched.firstWhere((a) => a['id'] == 'n3');
      expect(pending['clientNoShowCount'], 2);
      expect(pending['salonClientId'], isNotNull);
    });

    test('guest no-shows count by phone', () async {
      await service.recordBooking({
        'providerId': 'provider1',
        'userId': 'manual',
        'clientName': 'W',
        'clientPhone': '+2250700000081',
      });
      await seedAppointment(
        id: 'g1',
        clientPhone: '+2250700000081',
        status: 'noShow',
      );
      await seedAppointment(
        id: 'g2',
        clientPhone: '+2250700000081',
        status: 'pending',
      );
      final enriched = await service.enrichForProvider(
        'provider1',
        await appts.listForProvider('provider1'),
      );
      expect(
        enriched.firstWhere((a) => a['id'] == 'g2')['clientNoShowCount'],
        1,
      );
    });

    test('T48: account deletion anonymizes across every salon', () async {
      final uid = await makeUser('+2250700000082', name: 'Départ');
      await service.recordBooking({'providerId': 'provider1', 'userId': uid});
      await service.recordBooking({'providerId': 'provider2', 'userId': uid});
      await service.anonymizeUser(uid);

      for (final (acct, pid) in [
        (accountId, 'provider1'),
        (otherAccountId, 'provider2'),
      ]) {
        final r = await service.list(acct, pid);
        final c = (r.data!['items'] as List).first as Map;
        expect(c['displayName'], 'Client');
        expect(c['phone'], isNull);
        expect(c['linked'], isFalse);
      }
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ClientsService>()).thenReturn(service);
      return context;
    }

    String proTok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'provider').token;
    String userTok() =>
        tokens.issueAccessToken(subject: 'u1', role: 'user').token;

    Request req(String method, String path, {String? token, Object? body}) =>
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: body == null ? null : (body as Map).toString(),
        );

    test('list: 401 anonymous · 403 consumer role · 405 bad verb', () async {
      expect(
        (await clients_route.onRequest(
          ctx(req('GET', '/providers/provider1/clients')),
          'provider1',
        )).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await clients_route.onRequest(
          ctx(req('GET', '/providers/provider1/clients', token: userTok())),
          'provider1',
        )).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await clients_route.onRequest(
          ctx(
            req(
              'PUT',
              '/providers/provider1/clients',
              token: proTok(accountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });

    test('list 200 for the owner; cross-salon → 403 (T45)', () async {
      expect(
        (await clients_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/clients',
              token: proTok(accountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await clients_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/clients',
              token: proTok(otherAccountId),
            ),
          ),
          'provider1',
        )).statusCode,
        HttpStatus.forbidden,
      );
    });

    test('create: 400 invalid phone · 201 · 409 duplicate', () async {
      Request post(Map<String, dynamic> body) => Request.post(
        Uri.parse('http://localhost/providers/provider1/clients'),
        headers: {
          'Authorization': 'Bearer ${proTok(accountId)}',
          'content-type': 'application/json',
        },
        body: '{"name": "${body['name']}", "phone": "${body['phone']}"}',
      );
      expect(
        (await clients_route.onRequest(
          ctx(post({'name': 'X', 'phone': '0700'})),
          'provider1',
        )).statusCode,
        HttpStatus.badRequest,
      );
      expect(
        (await clients_route.onRequest(
          ctx(post({'name': 'X', 'phone': '+2250700000090'})),
          'provider1',
        )).statusCode,
        HttpStatus.created,
      );
      final dup = await clients_route.onRequest(
        ctx(post({'name': 'Y', 'phone': '+2250700000090'})),
        'provider1',
      );
      expect(dup.statusCode, HttpStatus.conflict);
      expect((await dup.json() as Map)['error'], 'client_exists');
    });

    test('card 200 / foreign id 404; visits 200; note routes', () async {
      final add = await service.addClient(
        accountId,
        'provider1',
        name: 'R',
        phone: '+2250700000091',
      );
      final id = add.data!['id'] as String;

      expect(
        (await card_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/clients/$id',
              token: proTok(accountId),
            ),
          ),
          'provider1',
          id,
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await card_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/clients/ghost',
              token: proTok(accountId),
            ),
          ),
          'provider1',
          'ghost',
        )).statusCode,
        HttpStatus.notFound,
      );
      expect(
        (await visits_route.onRequest(
          ctx(
            req(
              'GET',
              '/providers/provider1/clients/$id/visits',
              token: proTok(accountId),
            ),
          ),
          'provider1',
          id,
        )).statusCode,
        HttpStatus.ok,
      );

      final noteRes = await notes_route.onRequest(
        ctx(
          Request.post(
            Uri.parse('http://localhost/providers/provider1/clients/$id/notes'),
            headers: {
              'Authorization': 'Bearer ${proTok(accountId)}',
              'content-type': 'application/json',
            },
            body: '{"body": "RDV toujours en retard"}',
          ),
        ),
        'provider1',
        id,
      );
      expect(noteRes.statusCode, HttpStatus.created);
      final noteId = (await noteRes.json() as Map)['id'] as String;

      expect(
        (await note_delete_route.onRequest(
          ctx(
            req(
              'DELETE',
              '/providers/provider1/clients/$id/notes/$noteId',
              token: proTok(accountId),
            ),
          ),
          'provider1',
          id,
          noteId,
        )).statusCode,
        HttpStatus.noContent,
      );
    });

    test('tags PATCH: invalid → 400', () async {
      final add = await service.addClient(
        accountId,
        'provider1',
        name: 'S',
        phone: '+2250700000092',
      );
      final id = add.data!['id'] as String;
      final res = await card_route.onRequest(
        ctx(
          Request.patch(
            Uri.parse('http://localhost/providers/provider1/clients/$id'),
            headers: {
              'Authorization': 'Bearer ${proTok(accountId)}',
              'content-type': 'application/json',
            },
            body: '{"tags": ["${'x' * 30}"]}',
          ),
        ),
        'provider1',
        id,
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });
  });
}
