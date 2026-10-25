import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
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

  // phone-leftovers.md §8 — the card says whether its number can be changed
  // (`phoneEditable`: the PATCH takes a number for a guest card that has one).
  // Only a true says yes: absent is a server from before the change, whose
  // PATCH refuses a number.
  group('SalonClient.phoneEditable', () {
    Map<String, dynamic> card([Map<String, dynamic> extra = const {}]) => {
      'id': 'sc3',
      'displayName': 'Tante Marie',
      'phone': '+2250700000003',
      'tags': <String>[],
      'linked': false,
      'stats': {'visits': 1, 'spentFcfa': 15000},
      'notes': <Object>[],
      ...extra,
    };

    test('true when the card says so', () {
      final c = SalonClientCard.fromJson(card({'phoneEditable': true}));
      expect(c.client.phoneEditable, isTrue);
    });

    test('false when absent — a server from before the flag', () {
      expect(SalonClientCard.fromJson(card()).client.phoneEditable, isFalse);
      expect(SalonClient.fromJson(card()).phoneEditable, isFalse);
    });

    test('false when false, or anything that is not true', () {
      for (final v in [false, null, 'true', 1]) {
        final c = SalonClientCard.fromJson(card({'phoneEditable': v}));
        expect(c.client.phoneEditable, isFalse, reason: '« $v »');
      }
    });

    test('kept by copyWith, and part of equality', () {
      final c = SalonClient.fromJson(card({'phoneEditable': true}));
      expect(c.copyWith(tags: ['VIP']).phoneEditable, isTrue);
      expect(c.copyWith(phone: '+2250700000033').phoneEditable, isTrue);
      expect(c, isNot(SalonClient.fromJson(card())));
    });
  });

  group('MockProClientsService', () {
    // The mock sends the flag the way the server does: on the card (`GET`
    // and every `PATCH` answer) — true for a guest card with a number only.
    test('phoneEditable: a guest card yes, a linked card no — on every '
        'answer that is a card', () async {
      final service = MockProClientsService();
      expect(
        (await service.getCard(
          SalonId('p1'),
          'sc3',
        )).data!.client.phoneEditable,
        isTrue,
      );
      expect(
        (await service.getCard(
          SalonId('p1'),
          'sc1',
        )).data!.client.phoneEditable,
        isFalse,
        reason: 'linked: the account\'s number',
      );
      expect(
        (await service.updateTags(SalonId('p1'), 'sc3', [
          'VIP',
        ])).data!.phoneEditable,
        isTrue,
        reason: 'the tags PATCH answers the card too — « Modifier » stays',
      );
      expect(
        (await service.updateTags(SalonId('p1'), 'sc1', [
          'VIP',
        ])).data!.phoneEditable,
        isFalse,
      );
      final changed = await service.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000033',
      );
      expect(changed.data!.card!.client.phoneEditable, isTrue);
      final added = await service.addClient(
        SalonId('p1'),
        name: 'Nouvelle',
        phone: '+2250700000099',
      );
      expect(
        (await service.getCard(
          SalonId('p1'),
          added.data!,
        )).data!.client.phoneEditable,
        isTrue,
      );
    });

    test('lists sorted by last visit; search by name and digits', () async {
      final service = MockProClientsService();
      final all = await service.listClients(SalonId('p1'));
      expect(all.data!.items.first.displayName, 'Aïcha Koné');
      expect(all.data!.availableTags, containsAll(salonClientPresetTags));

      final byName = await service.listClients(SalonId('p1'), query: 'koffi');
      expect(byName.data!.items.single.displayName, 'Koffi Yao');

      final byDigits = await service.listClients(SalonId('p1'), query: '00 03');
      expect(byDigits.data!.items.single.displayName, 'Tante Marie');

      final byTag = await service.listClients(SalonId('p1'), tag: 'VIP');
      expect(byTag.data!.items.single.displayName, 'Aïcha Koné');
    });

    // The export walks the base page by page with the size the server
    // echoes (app-pro-export-completeness.md §4) — the mock clamps and
    // echoes like `ClientsService.list`, or the walk is never exercised.
    test('honours pageSize with the server clamp, and echoes it', () async {
      final service = MockProClientsService();
      final byDefault = await service.listClients(SalonId('p1'));
      expect(byDefault.data!.pageSize, 20);
      expect(byDefault.data!.items, hasLength(3));

      final first = await service.listClients(SalonId('p1'), pageSize: 2);
      expect(first.data!.pageSize, 2);
      expect(first.data!.items, hasLength(2));
      expect(first.data!.total, 3);
      final second = await service.listClients(
        SalonId('p1'),
        page: 2,
        pageSize: 2,
      );
      expect(second.data!.items, hasLength(1));
      expect(
        {...first.data!.items, ...second.data!.items}.map((c) => c.id),
        hasLength(3),
      );

      expect(
        (await service.listClients(SalonId('p1'), pageSize: 0)).data!.pageSize,
        1,
      );
      expect(
        (await service.listClients(
          SalonId('p1'),
          pageSize: 500,
        )).data!.pageSize,
        50,
      );
    });

    test(
      'addClient dedupes by phone → client_exists + the EXISTING id',
      () async {
        final service = MockProClientsService();
        final dup = await service.addClient(
          SalonId('p1'),
          name: 'Doublon',
          phone: '+2250700000001', // Aïcha's number
        );
        expect(dup.success, isFalse);
        expect(dup.code, 'client_exists');
        expect(dup.data, 'sc1');

        final ok = await service.addClient(
          SalonId('p1'),
          name: 'Nouvelle',
          phone: '+2250700000099',
          note: 'Vient de l’immeuble d’en face',
        );
        expect(ok.success, isTrue);
        final card = await service.getCard(SalonId('p1'), ok.data!);
        expect(card.data!.notes.single.body, 'Vient de l’immeuble d’en face');
      },
    );

    test('tags validated; notes capped at 500', () async {
      final service = MockProClientsService();
      final bad = await service.updateTags(SalonId('p1'), 'sc1', ['x' * 25]);
      expect(bad.code, 'invalid_tags');
      final tooLong = await service.addNote(SalonId('p1'), 'sc1', 'x' * 501);
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
        final before = await service.getVisits(SalonId('p1'), 'sc3');
        expect(before.data, hasLength(1), reason: 'the seeded walk-in');
        expect(before.data!.single.userId, 'manual');
        expect(before.data!.single.clientPhone, old);

        final r = await service.updatePhone(SalonId('p1'), 'sc3', fresh);
        expect(r.success, isTrue);
        expect(r.data!.card!.client.phone, fresh);
        expect(r.data!.card!.stats.visits, 1, reason: 'the count follows too');

        final after = await service.getVisits(SalonId('p1'), 'sc3');
        expect(
          after.data!.map((a) => a.id),
          before.data!.map((a) => a.id),
          reason: 'the same visits — moved, not lost',
        );
        expect(after.data!.single.clientPhone, fresh);
        final card = await service.getCard(SalonId('p1'), 'sc3');
        expect(card.data!.client.phone, fresh);
        expect(card.data!.stats.visits, 1);
        final list = await service.listClients(SalonId('p1'), query: '00 33');
        expect(
          list.data!.items.single.id,
          'sc3',
          reason: 'found by its new one',
        );
      },
    );

    // Each salon has its own cards — the server's `(provider_id, phone)`: a
    // change at one salon is that salon's card and that salon's walk-ins.
    // Another salon's card keeps its number AND its history (T45). The mock
    // used to share one card base across salons, so the change emptied the
    // other salon's card.
    test('another salon\'s card keeps its number and its history '
        '(T45)', () async {
      final service = MockProClientsService();
      // Salon p2 has its own walk-in under the same old number.
      expect(
        (await service.getVisits(SalonId('p2'), 'sc3')).data,
        hasLength(1),
      );

      await service.updatePhone(SalonId('p1'), 'sc3', fresh);

      final card = await service.getCard(SalonId('p2'), 'sc3');
      expect(card.data!.client.phone, old, reason: 'p2\'s card is p2\'s');
      expect(card.data!.stats.visits, 1, reason: 'its count stays');
      expect(
        (await service.getVisits(
          SalonId('p2'),
          'sc3',
        )).data!.single.clientPhone,
        old,
        reason: 'p2\'s booking did not move to the new number',
      );
      final byOld = await service.listClients(SalonId('p2'), query: '00 03');
      expect(byOld.data!.items.single.id, 'sc3');
      final byNew = await service.listClients(SalonId('p2'), query: '00 33');
      expect(byNew.data!.items, isEmpty);
      // The old number is still on a card there: a new one for it is that
      // card.
      final dup = await service.addClient(
        SalonId('p2'),
        name: 'Autre',
        phone: old,
      );
      expect(dup.code, 'client_exists');
      expect(dup.data, 'sc3');
    });

    test('a card added, or tagged, at one salon is not another\'s', () async {
      final service = MockProClientsService();
      const number = '+2250700000099';
      final added = await service.addClient(
        SalonId('p1'),
        name: 'Nouvelle',
        phone: number,
      );
      final p2 = await service.listClients(SalonId('p2'));
      expect(p2.data!.items.map((c) => c.id), isNot(contains(added.data)));
      expect(
        (await service.getCard(SalonId('p2'), added.data!)).code,
        'not_found',
      );
      final there = await service.addClient(
        SalonId('p2'),
        name: 'Autre',
        phone: number,
      );
      expect(there.success, isTrue, reason: 'the number is free at p2');

      await service.updateTags(SalonId('p1'), 'sc3', ['VIP']);
      expect((await service.getCard(SalonId('p2'), 'sc3')).data!.client.tags, [
        'Fidèle',
      ]);
    });

    test('a card linked to an account keeps the account\'s number: '
        'client_linked, nothing changes', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone(SalonId('p1'), 'sc1', fresh);
      expect(r.success, isFalse);
      expect(r.code, 'client_linked');
      expect(
        (await service.getCard(SalonId('p1'), 'sc1')).data!.client.phone,
        '+2250700000001',
      );
    });

    test('a number the server would refuse is invalid_phone — empty, short, '
        'or with separators', () async {
      final service = MockProClientsService();
      for (final bad in ['', '+225', '+22507000', '+225 07 00 00 00 33']) {
        final r = await service.updatePhone(SalonId('p1'), 'sc3', bad);
        expect(r.code, 'invalid_phone', reason: '« $bad »');
      }
      expect(
        (await service.getCard(SalonId('p1'), 'sc3')).data!.client.phone,
        old,
      );
    });

    test('a number already on another card is client_exists with THAT card\'s '
        'id; nothing moves', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000002',
      );
      expect(r.success, isFalse);
      expect(r.code, 'client_exists');
      expect(r.data!.takenBy, 'sc2', reason: 'Koffi Yao\'s card');
      expect(
        (await service.getCard(SalonId('p1'), 'sc3')).data!.client.phone,
        old,
      );
      expect(
        (await service.getVisits(
          SalonId('p1'),
          'sc3',
        )).data!.single.clientPhone,
        old,
      );
    });

    test('the same number: nothing to do, and the card comes back', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone(SalonId('p1'), 'sc3', old);
      expect(r.success, isTrue);
      expect(r.data!.card!.client.phone, old);
    });

    test('an unknown card is not_found', () async {
      final service = MockProClientsService();
      final r = await service.updatePhone(SalonId('p1'), 'ghost', fresh);
      expect(r.code, 'not_found');
    });
  });

  group('ProClientsProvider', () {
    test('load → list + tags; search narrows; tag toggle clears', () async {
      final provider = ProClientsProvider();
      await provider.load(SalonId('p1'));
      expect(provider.clients, hasLength(3));
      expect(provider.availableTags, contains('VIP'));

      await provider.search(SalonId('p1'), 'koffi');
      expect(provider.clients.single.displayName, 'Koffi Yao');

      await provider.search(SalonId('p1'), '');
      await provider.filterByTag(SalonId('p1'), 'VIP');
      expect(provider.clients.single.displayName, 'Aïcha Koné');
      await provider.filterByTag(SalonId('p1'), 'VIP'); // toggle off
      expect(provider.clients, hasLength(3));
    });

    test('addClient duplicate → existing id + lastAddWasDuplicate', () async {
      final provider = ProClientsProvider();
      await provider.load(SalonId('p1'));
      final id = await provider.addClient(
        SalonId('p1'),
        name: 'Doublon',
        phone: '+2250700000002',
      );
      expect(id, 'sc2');
      expect(provider.lastAddWasDuplicate, isTrue);
    });

    test('card: load + note add/delete + tags update', () async {
      final provider = ProClientsProvider();
      await provider.loadCard(SalonId('p1'), 'sc1');
      expect(provider.card!.client.displayName, 'Aïcha Koné');
      expect(provider.card!.stats.visits, 12);
      expect(provider.visits, isNotEmpty);

      expect(
        await provider.addNote(SalonId('p1'), 'sc1', 'Nouvelle note'),
        isTrue,
      );
      expect(provider.card!.notes.first.body, 'Nouvelle note');
      final noteId = provider.card!.notes.first.id;
      expect(await provider.deleteNote(SalonId('p1'), 'sc1', noteId), isTrue);
      expect(provider.card!.notes.every((n) => n.id != noteId), isTrue);

      expect(
        await provider.updateTags(SalonId('p1'), 'sc1', ['VIP', 'Fidèle']),
        isTrue,
      );
      expect(provider.card!.client.tags, ['VIP', 'Fidèle']);
    });

    test('unknown card → cardNotFound state', () async {
      final provider = ProClientsProvider();
      await provider.loadCard(SalonId('p1'), 'ghost');
      expect(provider.cardNotFound, isTrue);
    });

    // docs/design/export-unreadable-200.md §2: a page that comes back
    // without its list is a failed read — the list's error, never « Vos
    // clients apparaîtront ici » and never a list that ends early.
    group('a page that comes back without its list', () {
      setUp(service.reset);
      tearDown(service.reset);

      Map<String, dynamic> row(String id) => {
        'id': id,
        'displayName': 'Client $id',
        'tags': <String>[],
        'linked': false,
      };

      test('page 1 → the error state, not an empty base', () async {
        service.wireOf = (_) => {'page': 1, 'pageSize': 20};
        final provider = ProClientsProvider();
        await provider.load(SalonId('p1'));

        // The service's own word for an answer it cannot read — never
        // « FormatException: A clients page without its items », which the
        // list's error state would show as its description, and no longer
        // « Erreur » alone (docs/design/app-failure-messages.md §8).
        expect(provider.error, 'Une erreur est survenue. Réessayez.');
        expect(provider.clients, isEmpty);
      });

      test(
        'a later page → nothing appended, the list still has more',
        () async {
          service.wireOf = (page) => page == 1
              ? {
                  'items': [row('sc1')],
                  'page': 1,
                  'pageSize': 1,
                  'total': 2,
                }
              : {'page': page, 'pageSize': 1};
          final provider = ProClientsProvider();
          await provider.load(SalonId('p1'));
          expect(provider.hasMore, isTrue);

          await provider.loadMore(SalonId('p1'));

          expect(provider.clients.map((c) => c.id), ['sc1']);
          expect(provider.total, 2);
          expect(provider.hasMore, isTrue);
          expect(provider.isLoadingMore, isFalse);
          // The loaded list stays on screen: no error swaps it for
          // « Une erreur est survenue ».
          expect(provider.error, isNull);

          // The next scroll asks for the SAME page — no hole in the list.
          service.wireOf = (page) => {
            'items': [row('sc$page')],
            'page': page,
            'pageSize': 1,
            'total': 2,
          };
          await provider.loadMore(SalonId('p1'));

          expect(provider.clients.map((c) => c.id), ['sc1', 'sc2']);
          expect(service.pagesAsked, [1, 2, 2]);
          expect(provider.hasMore, isFalse);
        },
      );
    });
  });

  // phone-leftovers.md §8 — the card's number change, as the sheet sees it.
  group('ProClientsProvider.updatePhone', () {
    // Each test starts from the seed: the number change writes to the base.
    setUp(service.reset);

    test('done: the card AND its visits are read again, and the list row '
        'shows the new number', () async {
      final provider = ProClientsProvider();
      await provider.load(SalonId('p1'));
      await provider.loadCard(SalonId('p1'), 'sc3');
      final visitReads = service.visitReads;

      final refusal = await provider.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000033',
      );

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
      await provider.loadCard(SalonId('p1'), 'sc3');

      final refusal = await provider.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000002',
      );

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
      await provider.loadCard(SalonId('p1'), 'sc3');

      final refusal = await provider.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000002',
      );

      expect(refusal!.code, 'client_exists');
      expect(refusal.takenById, 'sc2');
      expect(refusal.takenByName, isNull);
    });

    test('done even when the history cannot be read afterwards: the change '
        'was made, and is not reported as a failure', () async {
      final provider = ProClientsProvider();
      await provider.loadCard(SalonId('p1'), 'sc3');
      service.visitsThrow = true;

      final refusal = await provider.updatePhone(
        SalonId('p1'),
        'sc3',
        '+2250700000033',
      );

      expect(refusal, isNull);
      expect(provider.card!.client.phone, '+2250700000033');
      expect(provider.visits, isNotEmpty, reason: 'the visits it had stay');
    });

    test(
      'client_linked: the card is read again, so it shows as linked',
      () async {
        final provider = ProClientsProvider();
        await provider.loadCard(SalonId('p1'), 'sc1');
        final cardReads = service.cardReads;

        final refusal = await provider.updatePhone(
          SalonId('p1'),
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
      await provider.loadCard(SalonId('p1'), 'sc3');
      final refusal = await provider.updatePhone(
        SalonId('p1'),
        'sc3',
        '+22507',
      );
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
      ).listClients(SalonId('provider1'), query: 'ami', page: 2);
      expect(res.success, isTrue);
      expect(res.data!.items.single.visits, 4);
      expect(res.data!.total, 21);
      expect(res.data!.pageSize, 20);
    });

    test('listClients sends pageSize only when asked', () async {
      final sent = <Map<String, String>>[];
      final client = MockClient((req) async {
        sent.add(req.url.queryParameters);
        return http.Response(
          jsonEncode({
            'items': <Object>[],
            'page': 1,
            'pageSize': 50,
            'total': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = linked(client);
      await service.listClients(SalonId('provider1'));
      await service.listClients(SalonId('provider1'), page: 3, pageSize: 50);
      expect(sent[0].containsKey('pageSize'), isFalse);
      expect(sent[1], {'page': '3', 'pageSize': '50'});
    });

    test('a page without a pageSize echo parses it as null', () {
      expect(
        SalonClientsPage.fromJson({
          'items': <Object>[],
          'page': 1,
          'total': 0,
        }).pageSize,
        isNull,
      );
    });

    // The server always sends `items` and `total`: a page without them is a
    // body that did not arrive whole. Read as « no clients, total 0 », page 1
    // `{"pageSize":50}` passed the export's walk as an empty base, complete
    // (docs/design/export-unreadable-200.md §1).
    group('a page without its items or its total does not parse', () {
      final bodies = <String, Map<String, dynamic>>{
        '{}': {},
        'only a pageSize': {'pageSize': 50},
        'items: null': {'items': null, 'total': 0, 'pageSize': 50},
        'items: "x"': {'items': 'x', 'total': 0, 'pageSize': 50},
        'no total': {'items': <Object>[], 'pageSize': 50},
        // Not only an empty one: two clients and no total must not read as a
        // base of two, complete.
        'items, no total': {
          'items': [
            {
              'id': 'sc1',
              'displayName': 'A',
              'tags': <String>[],
              'linked': false,
            },
            {
              'id': 'sc2',
              'displayName': 'B',
              'tags': <String>[],
              'linked': false,
            },
          ],
          'pageSize': 50,
        },
        'total: null': {'items': <Object>[], 'total': null, 'pageSize': 50},
        'total: "x"': {'items': <Object>[], 'total': 'x', 'pageSize': 50},
      };
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        test(name, () {
          expect(() => SalonClientsPage.fromJson(body), throwsFormatException);
        });
      }
    });

    test('CONTROL: an empty base the server sent parses as one', () {
      final page = SalonClientsPage.fromJson({
        'items': <Object>[],
        'page': 1,
        'pageSize': 50,
        'total': 0,
      });
      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.pageSize, 50);
    });

    test('listClients: a 200 without its list, or cut off, is an error — '
        'never an empty page, never a throw', () async {
      for (final body in [
        jsonEncode({'pageSize': 50}),
        '{"items":[{"id"',
      ]) {
        final client = MockClient(
          (req) async => http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        final res = await linked(
          client,
        ).listClients(SalonId('provider1'), pageSize: 50);
        expect(res.success, isFalse, reason: body);
        expect(res.error, 'Une erreur est survenue. Réessayez.', reason: body);
        expect(res.code, 'unreadable', reason: body);
      }
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
      ).addClient(SalonId('provider1'), name: 'X', phone: '+2250700000001');
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
      final card = await service.getCard(SalonId('provider1'), 'sc1');
      expect(card.data!.stats.spentFcfa, 60000);
      expect(card.data!.notes.single.authorName, 'Vous');
      final note = await service.addNote(
        SalonId('provider1'),
        'sc1',
        'Nouvelle',
      );
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
            'phoneEditable': true,
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
      ).updatePhone(SalonId('provider1'), 'sc1', '+2250700000033');
      expect(res.success, isTrue);
      expect(res.data!.card!.client.phone, '+2250700000033');
      expect(res.data!.card!.client.phoneEditable, isTrue);
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
        ).updatePhone(SalonId('provider1'), 'sc1', '+2250700000002');
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
        ).updatePhone(SalonId('provider1'), 'sc1', '+2250700000002');
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

  /// The 200 body a list page answers, parsed as `ApiProClientsService`
  /// does (`SalonClientsPage.fromJson`, an unreadable page → « Erreur »);
  /// null = the seeded mock answers.
  Map<String, dynamic>? Function(int page)? wireOf;

  /// Every page `listClients` was asked for, in order.
  final pagesAsked = <int>[];

  void reset() {
    _base = MockProClientsService();
    cardReads = 0;
    visitReads = 0;
    failCardOf = null;
    visitsThrow = false;
    wireOf = null;
    pagesAsked.clear();
  }

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    SalonId providerId, {
    String? query,
    String? tag,
    int page = 1,
    int? pageSize,
  }) async {
    pagesAsked.add(page);
    if (wireOf?.call(page) case final wire?) {
      try {
        return ApiResponse.success(SalonClientsPage.fromJson(wire));
      } on FormatException {
        // The real service's word for an unreadable page since batch 3.
        return ApiResponse.error(
          'Une erreur est survenue. Réessayez.',
          code: 'unreadable',
        );
      }
    }
    return _base.listClients(
      providerId,
      query: query,
      tag: tag,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    SalonId providerId,
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
    SalonId providerId,
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
    SalonId providerId, {
    required String name,
    required String phone,
    String? note,
  }) => _base.addClient(providerId, name: name, phone: phone, note: note);

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    SalonId providerId,
    String clientId,
    List<String> tags,
  ) => _base.updateTags(providerId, clientId, tags);

  @override
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    SalonId providerId,
    String clientId,
    String phone,
  ) => _base.updatePhone(providerId, clientId, phone);

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    SalonId providerId,
    String clientId,
    String body, {
    String? idempotencyKey,
  }) =>
      _base.addNote(providerId, clientId, body, idempotencyKey: idempotencyKey);

  @override
  Future<ApiResponse<bool>> deleteNote(
    SalonId providerId,
    String clientId,
    String noteId,
  ) => _base.deleteNote(providerId, clientId, noteId);
}
