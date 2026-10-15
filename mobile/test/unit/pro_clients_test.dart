import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/services/api/api_pro_clients_service.dart';
import 'package:myweli/services/interfaces/pro_clients_service_interface.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';

/// Module `clients` C1c (docs/design/clients-c1.md §5/§9): mock realism,
/// provider state, and the API impl (incl. the 409 dedupe-carries-id rule).
void main() {
  // The locator slot is `late final`: one assignment per test file. The
  // providers read this double, whose seeded mock a test can renew.
  final service = _CountingClients();
  setUpAll(() => serviceLocator.proClientsService = service);

  group('maskClientPhone', () {
    test('masks to the card-safe shape', () {
      expect(maskClientPhone('+2250700000089'), '+225 07 •• •• •89');
      expect(maskClientPhone(null), '');
      expect(maskClientPhone('123'), '123');
    });

    // phone-leftovers.md §8 — the mask took the first THREE digits after `+`
    // for the calling code, whatever the country: a French client's row read
    // « +336 12 … ». The calling code is the longest one the number starts
    // with, the reading `PhoneNumberField` and `Helpers.maskPhoneNumber` give.
    test('another country keeps ITS calling code — +33, not +336', () {
      expect(maskClientPhone('+33612345678'), '+33 61 •• •• •78');
    });

    test('a one-digit calling code too — +1, not +141', () {
      expect(maskClientPhone('+14155550123'), '+1 41 •• •• •23');
    });

    test('no calling code: the first two digits, as before', () {
      expect(maskClientPhone('0700000089'), '07 •• •• •89');
    });
  });

  group('MockProClientsService', () {
    test('lists sorted by last visit; search by name and digits', () async {
      final service = MockProClientsService();
      final all = await service.listClients('p1');
      expect(all.data!.items.first.displayName, 'Aïcha Koné');
      expect(all.data!.availableTags, containsAll(salonClientPresetTags));

      final byName = await service.listClients('p1', query: 'koffi');
      expect(byName.data!.items.single.displayName, 'Koffi Yao');

      final byDigits = await service.listClients('p1', query: '00 03');
      expect(byDigits.data!.items.single.displayName, 'Tante Marie');

      final byTag = await service.listClients('p1', tag: 'VIP');
      expect(byTag.data!.items.single.displayName, 'Aïcha Koné');
    });

    test(
      'addClient dedupes by phone → client_exists + the EXISTING id',
      () async {
        final service = MockProClientsService();
        final dup = await service.addClient(
          'p1',
          name: 'Doublon',
          phone: '+2250700000001', // Aïcha's number
        );
        expect(dup.success, isFalse);
        expect(dup.code, 'client_exists');
        expect(dup.data, 'sc1');

        final ok = await service.addClient(
          'p1',
          name: 'Nouvelle',
          phone: '+2250700000099',
          note: 'Vient de l’immeuble d’en face',
        );
        expect(ok.success, isTrue);
        final card = await service.getCard('p1', ok.data!);
        expect(card.data!.notes.single.body, 'Vient de l’immeuble d’en face');
      },
    );

    test('tags validated; notes capped at 500', () async {
      final service = MockProClientsService();
      final bad = await service.updateTags('p1', 'sc1', ['x' * 25]);
      expect(bad.code, 'invalid_tags');
      final tooLong = await service.addNote('p1', 'sc1', 'x' * 501);
      expect(tooLong.code, 'note_too_long');
    });
  });

  // phone-leftovers.md §8 — the mock answers a number change the way the
  // server does, history included: a guest card finds its visits BY ITS
  // NUMBER (`_visitsOf`), so the salon's walk-ins under the old number move
  // with it, or the card would come back empty.
  group('MockProClientsService.updatePhone', () {
    const old = '+2250700000003'; // « Tante Marie », the seeded guest (sc3)
    const fresh = '+2250700000033';

    test(
      'a guest card takes the new number, and its history follows',
      () async {
        final service = MockProClientsService();
        final before = await service.getVisits('p1', 'sc3');
        expect(before.data, hasLength(1), reason: 'the seeded walk-in');
        expect(before.data!.single.userId, 'manual');
        expect(before.data!.single.clientPhone, old);

        final r = await service.updatePhone('p1', 'sc3', fresh);
        expect(r.success, isTrue);
        expect(r.data!.card!.client.phone, fresh);
        expect(r.data!.card!.stats.visits, 1, reason: 'the count follows too');

        final after = await service.getVisits('p1', 'sc3');
        expect(
          after.data!.map((a) => a.id),
          before.data!.map((a) => a.id),
          reason: 'the same visits — moved, not lost',
        );
        expect(after.data!.single.clientPhone, fresh);
        final card = await service.getCard('p1', 'sc3');
        expect(card.data!.client.phone, fresh);
        expect(card.data!.stats.visits, 1);
        final list = await service.listClients('p1', query: '00 33');
        expect(
          list.data!.items.single.id,
          'sc3',
          reason: 'found by its new one',
        );
      },
    );

    test('another salon\'s walk-ins under the old number stay where they '
        'are (T45)', () async {
      final service = MockProClientsService();
      // Salon p2 has its own walk-in under the same old number.
      expect((await service.getVisits('p2', 'sc3')).data, hasLength(1));

      await service.updatePhone('p1', 'sc3', fresh);

      expect(
        (await service.getVisits('p2', 'sc3')).data,
        isEmpty,
        reason: 'p2\'s booking did not move to the new number',
      );
      // The old number is free on the cards now; a card for it at p2 finds
      // p2's booking still there, under the old number.
      final added = await service.addClient('p2', name: 'Autre', phone: old);
      final p2 = await service.getVisits('p2', added.data!);
      expect(p2.data!.single.clientPhone, old);
    });

    test('a card linked to an account keeps the account\'s number: '
        'client_linked, nothing changes', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone('p1', 'sc1', fresh);
      expect(r.success, isFalse);
      expect(r.code, 'client_linked');
      expect(
        (await service.getCard('p1', 'sc1')).data!.client.phone,
        '+2250700000001',
      );
    });

    test('a number the server would refuse is invalid_phone — empty, short, '
        'or with separators', () async {
      final service = MockProClientsService();
      for (final bad in ['', '+225', '+22507000', '+225 07 00 00 00 33']) {
        final r = await service.updatePhone('p1', 'sc3', bad);
        expect(r.code, 'invalid_phone', reason: '« $bad »');
      }
      expect((await service.getCard('p1', 'sc3')).data!.client.phone, old);
    });

    test('a number already on another card is client_exists with THAT card\'s '
        'id; nothing moves', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone('p1', 'sc3', '+2250700000002');
      expect(r.success, isFalse);
      expect(r.code, 'client_exists');
      expect(r.data!.takenBy, 'sc2', reason: 'Koffi Yao\'s card');
      expect((await service.getCard('p1', 'sc3')).data!.client.phone, old);
      expect(
        (await service.getVisits('p1', 'sc3')).data!.single.clientPhone,
        old,
      );
    });

    test('the same number: nothing to do, and the card comes back', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone('p1', 'sc3', old);
      expect(r.success, isTrue);
      expect(r.data!.card!.client.phone, old);
    });

    test('an unknown card is not_found', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone('p1', 'ghost', fresh);
      expect(r.code, 'not_found');
    });
  });

  group('ProClientsProvider', () {
    test('load → list + tags; search narrows; tag toggle clears', () async {
      final provider = ProClientsProvider();
      await provider.load('p1');
      expect(provider.clients, hasLength(3));
      expect(provider.availableTags, contains('VIP'));

      await provider.search('p1', 'koffi');
      expect(provider.clients.single.displayName, 'Koffi Yao');

      await provider.search('p1', '');
      await provider.filterByTag('p1', 'VIP');
      expect(provider.clients.single.displayName, 'Aïcha Koné');
      await provider.filterByTag('p1', 'VIP'); // toggle off
      expect(provider.clients, hasLength(3));
    });

    test('addClient duplicate → existing id + lastAddWasDuplicate', () async {
      final provider = ProClientsProvider();
      await provider.load('p1');
      final id = await provider.addClient(
        'p1',
        name: 'Doublon',
        phone: '+2250700000002',
      );
      expect(id, 'sc2');
      expect(provider.lastAddWasDuplicate, isTrue);
    });

    test('card: load + note add/delete + tags update', () async {
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'sc1');
      expect(provider.card!.client.displayName, 'Aïcha Koné');
      expect(provider.card!.stats.visits, 12);
      expect(provider.visits, isNotEmpty);

      expect(await provider.addNote('p1', 'sc1', 'Nouvelle note'), isTrue);
      expect(provider.card!.notes.first.body, 'Nouvelle note');
      final noteId = provider.card!.notes.first.id;
      expect(await provider.deleteNote('p1', 'sc1', noteId), isTrue);
      expect(provider.card!.notes.every((n) => n.id != noteId), isTrue);

      expect(await provider.updateTags('p1', 'sc1', ['VIP', 'Fidèle']), isTrue);
      expect(provider.card!.client.tags, ['VIP', 'Fidèle']);
    });

    test('unknown card → cardNotFound state', () async {
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'ghost');
      expect(provider.cardNotFound, isTrue);
    });
  });

  // phone-leftovers.md §8 — the card's number change, as the sheet sees it.
  group('ProClientsProvider.updatePhone', () {
    // Each test starts from the seed: the number change writes to the base.
    setUp(service.reset);

    test('done: the card AND its visits are read again, and the list row '
        'shows the new number', () async {
      final provider = ProClientsProvider();
      await provider.load('p1');
      await provider.loadCard('p1', 'sc3');
      final visitReads = service.visitReads;

      final refusal = await provider.updatePhone('p1', 'sc3', '+2250700000033');

      expect(refusal, isNull);
      expect(provider.card!.client.phone, '+2250700000033');
      expect(
        service.visitReads,
        visitReads + 1,
        reason: 'the history is read again — it follows the number',
      );
      expect(provider.visits.single.clientPhone, '+2250700000033');
      expect(
        provider.clients.firstWhere((c) => c.id == 'sc3').phone,
        '+2250700000033',
        reason: 'back on the list, the row is not the old number',
      );
    });

    test('a number on another card: client_exists, with that card\'s id AND '
        'name; the open card is untouched', () async {
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'sc3');

      final refusal = await provider.updatePhone('p1', 'sc3', '+2250700000002');

      expect(refusal!.code, 'client_exists');
      expect(refusal.takenById, 'sc2');
      expect(refusal.takenByName, 'Koffi Yao');
      expect(provider.card!.client.displayName, 'Tante Marie');
      expect(provider.card!.client.phone, '+2250700000003');
    });

    test('client_exists whose card cannot be read: no name, the id still '
        'comes back', () async {
      service.failCardOf = 'sc2';
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'sc3');

      final refusal = await provider.updatePhone('p1', 'sc3', '+2250700000002');

      expect(refusal!.code, 'client_exists');
      expect(refusal.takenById, 'sc2');
      expect(refusal.takenByName, isNull);
    });

    test('done even when the history cannot be read afterwards: the change '
        'was made, and is not reported as a failure', () async {
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'sc3');
      service.visitsThrow = true;

      final refusal = await provider.updatePhone('p1', 'sc3', '+2250700000033');

      expect(refusal, isNull);
      expect(provider.card!.client.phone, '+2250700000033');
      expect(provider.visits, isNotEmpty, reason: 'the visits it had stay');
    });

    test(
      'client_linked: the card is read again, so it shows as linked',
      () async {
        final provider = ProClientsProvider();
        await provider.loadCard('p1', 'sc1');
        final cardReads = service.cardReads;

        final refusal = await provider.updatePhone(
          'p1',
          'sc1',
          '+2250700000033',
        );

        expect(refusal!.code, 'client_linked');
        expect(service.cardReads, cardReads + 1);
        expect(provider.card!.client.linked, isTrue);
        expect(provider.card!.client.phone, '+2250700000001');
      },
    );

    test('invalid_phone comes back as the field\'s fault', () async {
      final provider = ProClientsProvider();
      await provider.loadCard('p1', 'sc3');
      final refusal = await provider.updatePhone('p1', 'sc3', '+22507');
      expect(refusal!.code, 'invalid_phone');
      expect(provider.card!.client.phone, '+2250700000003');
    });
  });

  group('ApiProClientsService', () {
    ApiProClientsService linked(MockClient client) {
      final store = InMemorySessionStore();
      store.save(
        jsonEncode({
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
            'providerId': 'provider1',
          },
        }),
      );
      return ApiProClientsService(
        client: client,
        baseUrl: 'http://x',
        providerSessionStore: store,
      );
    }

    Map<String, dynamic> clientJson() => {
      'id': 'sc1',
      'displayName': 'Aïcha',
      'phone': '+2250700000001',
      'tags': ['VIP'],
      'lastVisitAt': '2026-07-01T10:00:00.000Z',
      'linked': true,
      'createdAt': '2026-06-01T10:00:00.000Z',
      'visits': 4,
      'noShows': 1,
    };

    test('listClients GETs with query params and parses the page', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/providers/provider1/clients');
        expect(req.url.queryParameters['query'], 'ami');
        expect(req.url.queryParameters['page'], '2');
        return http.Response(
          jsonEncode({
            'items': [clientJson()],
            'page': 2,
            'pageSize': 20,
            'total': 21,
            'availableTags': ['VIP'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final res = await linked(
        client,
      ).listClients('provider1', query: 'ami', page: 2);
      expect(res.success, isTrue);
      expect(res.data!.items.single.visits, 4);
      expect(res.data!.total, 21);
    });

    test('addClient 409 carries the existing card id', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'error': 'client_exists', 'clientId': 'sc9'}),
          409,
          headers: {'content-type': 'application/json'},
        ),
      );
      final res = await linked(
        client,
      ).addClient('provider1', name: 'X', phone: '+2250700000001');
      expect(res.success, isFalse);
      expect(res.code, 'client_exists');
      expect(res.data, 'sc9');
    });

    test('card + note round-trip', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({
              ...clientJson(),
              'stats': {
                'visits': 4,
                'spentFcfa': 60000,
                'noShows': 1,
                'cancellations': 0,
              },
              'notes': [
                {
                  'id': 'n1',
                  'authorName': 'Vous',
                  'body': 'Préfère Awa',
                  'createdAt': '2026-07-01T10:00:00.000Z',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(req.url.path, '/providers/provider1/clients/sc1/notes');
        return http.Response(
          jsonEncode({
            'id': 'n2',
            'authorName': 'Vous',
            'body': 'Nouvelle',
            'createdAt': '2026-07-02T10:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = linked(client);
      final card = await service.getCard('provider1', 'sc1');
      expect(card.data!.stats.spentFcfa, 60000);
      expect(card.data!.notes.single.authorName, 'Vous');
      final note = await service.addNote('provider1', 'sc1', 'Nouvelle');
      expect(note.data!.id, 'n2');
    });

    // phone-leftovers.md §8 — the PATCH carries `phone`; the answer is the card.
    test('updatePhone PATCHes {phone} and parses the updated card', () async {
      final client = MockClient((req) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, '/providers/provider1/clients/sc1');
        expect(jsonDecode(req.body), {'phone': '+2250700000033'});
        return http.Response(
          jsonEncode({
            ...clientJson(),
            'phone': '+2250700000033',
            'linked': false,
            'stats': {
              'visits': 4,
              'spentFcfa': 60000,
              'noShows': 1,
              'cancellations': 0,
            },
            'notes': <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final res = await linked(
        client,
      ).updatePhone('provider1', 'sc1', '+2250700000033');
      expect(res.success, isTrue);
      expect(res.data!.card!.client.phone, '+2250700000033');
      expect(res.data!.card!.stats.visits, 4);
    });

    test(
      'updatePhone 409 client_exists carries the OTHER card\'s id',
      () async {
        final client = MockClient(
          (req) async => http.Response(
            jsonEncode({'error': 'client_exists', 'clientId': 'sc9'}),
            409,
            headers: {'content-type': 'application/json'},
          ),
        );
        final res = await linked(
          client,
        ).updatePhone('provider1', 'sc1', '+2250700000002');
        expect(res.success, isFalse);
        expect(res.code, 'client_exists');
        expect(res.data!.takenBy, 'sc9');
      },
    );

    for (final (status, code) in [
      (409, 'client_linked'),
      (400, 'invalid_phone'),
      (403, 'forbidden'),
    ]) {
      test('updatePhone $status $code comes back as its code', () async {
        final client = MockClient(
          (req) async => http.Response(
            jsonEncode({'error': code}),
            status,
            headers: {'content-type': 'application/json'},
          ),
        );
        final res = await linked(
          client,
        ).updatePhone('provider1', 'sc1', '+2250700000002');
        expect(res.success, isFalse);
        expect(res.code, code);
        expect(res.data, isNull);
      });
    }
  });
}

/// The seeded mock behind the one locator slot, renewed by [reset]. Counts the
/// card's reads and can fail one card's — what the provider's number change
/// does after its PATCH is what the `updatePhone` tests are about.
class _CountingClients implements ProClientsServiceInterface {
  MockProClientsService _base = MockProClientsService();
  int cardReads = 0;
  int visitReads = 0;
  String? failCardOf;

  /// The history read throws (offline after the PATCH went through).
  bool visitsThrow = false;

  void reset() {
    _base = MockProClientsService();
    cardReads = 0;
    visitReads = 0;
    failCardOf = null;
    visitsThrow = false;
  }

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
  }) => _base.listClients(providerId, query: query, tag: tag, page: page);

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  ) {
    cardReads++;
    if (clientId == failCardOf) {
      return Future.value(ApiResponse.error('Pas de connexion. Réessayez.'));
    }
    return _base.getCard(providerId, clientId);
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    String providerId,
    String clientId, {
    int page = 1,
  }) {
    visitReads++;
    if (visitsThrow) {
      return Future.error(const SocketException('offline'));
    }
    return _base.getVisits(providerId, clientId, page: page);
  }

  @override
  Future<ApiResponse<String>> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) => _base.addClient(providerId, name: name, phone: phone, note: note);

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) => _base.updateTags(providerId, clientId, tags);

  @override
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    String providerId,
    String clientId,
    String phone,
  ) => _base.updatePhone(providerId, clientId, phone);

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body,
  ) => _base.addNote(providerId, clientId, body);

  @override
  Future<ApiResponse<bool>> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  ) => _base.deleteNote(providerId, clientId, noteId);
}
