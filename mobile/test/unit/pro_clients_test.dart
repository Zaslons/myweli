import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/services/api/api_pro_clients_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';

/// Module `clients` C1c (docs/design/clients-c1.md §5/§9): mock realism,
/// provider state, and the API impl (incl. the 409 dedupe-carries-id rule).
void main() {
  group('maskClientPhone', () {
    test('masks to the card-safe shape', () {
      expect(maskClientPhone('+2250700000089'), '+225 07 •• •• •89');
      expect(maskClientPhone(null), '');
      expect(maskClientPhone('123'), '123');
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

    test('addClient dedupes by phone → client_exists + the EXISTING id',
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
    });

    test('tags validated; notes capped at 500', () async {
      final service = MockProClientsService();
      final bad = await service.updateTags('p1', 'sc1', ['x' * 25]);
      expect(bad.code, 'invalid_tags');
      final tooLong = await service.addNote('p1', 'sc1', 'x' * 501);
      expect(tooLong.code, 'note_too_long');
    });
  });

  group('ProClientsProvider', () {
    setUpAll(() {
      serviceLocator.proClientsService = MockProClientsService();
    });

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

  group('ApiProClientsService', () {
    ApiProClientsService linked(MockClient client) {
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
          'providerId': 'provider1',
        },
      }));
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
      final res =
          await linked(client).listClients('provider1', query: 'ami', page: 2);
      expect(res.success, isTrue);
      expect(res.data!.items.single.visits, 4);
      expect(res.data!.total, 21);
    });

    test('addClient 409 carries the existing card id', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({'error': 'client_exists', 'clientId': 'sc9'}),
            409,
            headers: {'content-type': 'application/json'},
          ));
      final res = await linked(client).addClient(
        'provider1',
        name: 'X',
        phone: '+2250700000001',
      );
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
  });
}
