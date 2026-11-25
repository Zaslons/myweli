import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/search_text.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/services/api/api_provider_service.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/services/mock/mock_search_fold.dart';

/// docs/design/consumer-search.md §2.3 (what the app sends) and §3 (what the
/// server — and so the mock — answers).
Provider _salon(
  String id, {
  String name = 'Salon',
  String description = '',
  String address = '',
  // Not null: `copyWith` keeps the seed's own commune (Cocody) for null.
  String commune = 'Plateau',
  String category = 'salon',
  double rating = 4,
  List<(String, bool)> services = const [],
}) {
  final base = MockData.providers.first;
  final service = base.services.first;
  return base.copyWith(
    id: SalonId(id),
    name: name,
    description: description,
    address: address,
    commune: commune,
    category: category,
    rating: rating,
    services: [
      for (final (i, (n, active)) in services.indexed)
        service.copyWith(id: '$id-s$i', name: n, active: active),
    ],
  );
}

Future<List<String>> _ids(MockProviderService svc, ProviderQuery q) async => [
  for (final p in (await svc.searchProviders(q)).data!.items) p.id,
];

void main() {
  group('cleanSearchText — what the field sends', () {
    test('trims, and makes every run of white space one space', () {
      expect(cleanSearchText('  tresses   cocody '), 'tresses cocody');
      expect(cleanSearchText('beauté  divine'), 'beauté divine');
    });

    test('a tab or a line break is a space, not a 400', () {
      // The server refuses any C0 control character (query_sanity.dart).
      expect(cleanSearchText('tresses\tcocody'), 'tresses cocody');
      expect(cleanSearchText('tresses\ncocody\r\n'), 'tresses cocody');
    });

    test('the other control characters are removed', () {
      expect(cleanSearchText('tre\u0001sses\u007F'), 'tresses');
      expect(cleanSearchText('a \u0002 b'), 'a b');
      for (final rune in cleanSearchText('x\u0000\u001By\u0007z').runes) {
        expect(rune, greaterThan(0x1F));
      }
    });

    test('only spaces is nothing', () {
      expect(cleanSearchText('     '), '');
      expect(cleanSearchText(''), '');
    });

    test('the first 100 characters, an emoji at the cut kept whole', () {
      final long = 'a' * 150;
      expect(cleanSearchText(long), 'a' * 100);
      final emoji = '${'a' * 99}💅bcd';
      final cut = cleanSearchText(emoji);
      expect(cut.runes.length, 100);
      expect(cut.endsWith('💅'), isTrue);
      expect(searchTextLength('💅'), 1);
    });
  });

  group('the mock folds with the server table', () {
    test('kMockSearchFold is the server table over Latin, entry for entry', () {
      final source = File(
        '../backend/lib/src/search_fold_table.dart',
      ).readAsStringSync();
      final server = {
        for (final m in RegExp(
          r"  0x([0-9A-F]+): '((?:[^'\\]|\\.)*)',",
        ).allMatches(source))
          int.parse(m.group(1)!, radix: 16): m
              .group(2)!
              .replaceAll(r"\'", "'")
              .replaceAll(r'\\', r'\'),
      };
      expect(server, hasLength(greaterThan(1600)), reason: 'table moved');
      bool latin(int c) =>
          (c >= 0x00A0 && c <= 0x024F) ||
          (c >= 0x0300 && c <= 0x036F) ||
          (c >= 0x1E00 && c <= 0x1EFF) ||
          (c >= 0x2000 && c <= 0x206F);
      final expected = {
        for (final e in server.entries)
          if (latin(e.key)) e.key: e.value,
      };
      expect(kMockSearchFold, expected);
    });

    test('accents, case, œ, æ, the smart apostrophe, a decomposed é', () {
      expect(mockFoldSearchText('BEAUTÉ'), 'beaute');
      expect(mockFoldSearchText('Œuvre Æther'), 'oeuvre aether');
      expect(mockFoldSearchText('d’Esperey'), "d'esperey");
      expect(mockFoldSearchText('café'), 'cafe');
      expect(mockFoldSearchText('a  b'), 'a b');
    });
  });

  group('MockProviderService.searchProviders, as A4-api answers', () {
    final salons = [
      _salon('a', name: 'Beauté Divine', commune: 'Marcory'),
      _salon('b', description: 'Tresses et tissages'),
      _salon('c', address: 'Rue des Jardins, Angré'),
      _salon('d', commune: 'Cocody'),
      _salon('e', services: [('Manucure française', true)]),
      _salon('f', services: [('Pédicure', false)]),
      _salon('g', name: 'Beauté', description: 'Divine'),
    ];
    final svc = MockProviderService(salons: salons);

    test('each field matches: name, description, address, commune, '
        'an active service', () async {
      expect(await _ids(svc, const ProviderQuery(text: 'divine')), ['a', 'g']);
      expect(await _ids(svc, const ProviderQuery(text: 'tresses')), ['b']);
      expect(await _ids(svc, const ProviderQuery(text: 'angre')), ['c']);
      expect(await _ids(svc, const ProviderQuery(text: 'cocody')), ['d']);
      expect(await _ids(svc, const ProviderQuery(text: 'manucure')), ['e']);
    });

    test('an inactive service does not match', () async {
      expect(await _ids(svc, const ProviderQuery(text: 'pedicure')), isEmpty);
    });

    test('a text spanning two fields matches neither', () async {
      // « Beauté » is g's name and « Divine » its description.
      expect(await _ids(svc, const ProviderQuery(text: 'beaute divine')), [
        'a',
      ]);
    });

    test('accents and case are ignored, spaces collapsed', () async {
      expect(await _ids(svc, const ProviderQuery(text: '  BEAUTE   divine ')), [
        'a',
      ]);
    });

    test('an empty text is no filter, and total counts the match', () async {
      final page = (await svc.searchProviders(const ProviderQuery())).data!;
      expect(page.total, salons.length);
      final some = (await svc.searchProviders(
        const ProviderQuery(text: 'beaute'),
      )).data!;
      expect(some.total, 2);
    });

    test('pages, with total, and hasMore until the last one', () async {
      final many = MockProviderService(
        salons: [
          for (var i = 0; i < 45; i++) _salon('s${'$i'.padLeft(2, '0')}'),
        ],
      );
      final p1 = (await many.searchProviders(const ProviderQuery())).data!;
      expect(
        (p1.page, p1.pageSize, p1.total, p1.items.length),
        (1, 20, 45, 20),
      );
      expect(p1.hasMore, isTrue);
      final p3 = (await many.searchProviders(
        const ProviderQuery(page: 3),
      )).data!;
      expect(p3.items.length, 5);
      expect(p3.hasMore, isFalse);
      expect(p3.items.first.id, 's40');
    });

    test('the page size is clamped to 50, as the server clamps it', () async {
      final many = MockProviderService(
        salons: [for (var i = 0; i < 60; i++) _salon('m$i')],
      );
      final page = (await many.searchProviders(
        const ProviderQuery(pageSize: 80),
      )).data!;
      expect((page.pageSize, page.items.length, page.total), (50, 50, 60));
    });

    test('every sort ends on the id', () async {
      final tied = MockProviderService(
        salons: [
          _salon('z', rating: 4),
          _salon('b', rating: 4),
          _salon('m', rating: 5),
        ],
      );
      expect(await _ids(tied, const ProviderQuery(sort: ProviderSort.rating)), [
        'm',
        'b',
        'z',
      ]);
    });

    test('category and commune narrow the same search', () async {
      final mixed = MockProviderService(
        salons: [
          _salon('n1', category: 'nails', commune: 'Cocody'),
          _salon('n2', category: 'nails', commune: 'Marcory'),
          _salon('s1', category: 'salon', commune: 'Cocody'),
        ],
      );
      expect(
        await _ids(
          mixed,
          const ProviderQuery(category: 'nails', commune: 'Cocody'),
        ),
        ['n1'],
      );
    });

    test('the error switch and the empty case', () async {
      final failing = MockProviderService(failSearches: true);
      final res = await failing.searchProviders(const ProviderQuery());
      expect(res.success, isFalse);
      expect((res.error, res.code), (kNoConnectionMessage, 'network'));

      final empty = MockProviderService(salons: const []);
      final none = (await empty.searchProviders(const ProviderQuery())).data!;
      expect(none.total, 0);
      expect(none.items, isEmpty);
      expect((await empty.getFeaturedProviders()).data, isEmpty);
    });
  });

  group('ApiProviderService.searchProviders', () {
    Map<String, dynamic> json(String id) => {
      'id': id,
      'name': 'Salon $id',
      'description': '',
      'address': '',
      'imageUrls': <String>[],
      'rating': 4.5,
      'reviewCount': 1,
      'services': <Map<String, dynamic>>[],
      'availability': {
        'providerId': id,
        'weeklySchedule': <String, dynamic>{},
        'blockedDates': <String>[],
      },
      'phoneNumber': '+22500',
      'category': 'salon',
    };

    test('sends every narrowing, and reads the total', () async {
      late Uri asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode({
            'items': [json('p1')],
            'page': 2,
            'pageSize': 20,
            'total': 41,
          }),
          200,
        );
      });
      final service = ApiProviderService(client: client, baseUrl: 'http://x');

      final res = await service.searchProviders(
        const ProviderQuery(
          text: 'tresses',
          category: 'nails',
          commune: 'Cocody',
          sort: ProviderSort.rating,
          availableToday: true,
          page: 2,
        ),
      );

      expect(asked.path, '/providers');
      expect(asked.queryParameters, {
        'q': 'tresses',
        'category': 'nails',
        'commune': 'Cocody',
        'sort': 'rating',
        'availableToday': 'true',
        'page': '2',
        'pageSize': '20',
      });
      final page = res.data!;
      expect((page.page, page.pageSize, page.total), (2, 20, 41));
      expect(page.items.single.id, 'p1');
      expect(page.hasMore, isTrue);
    });

    test('no narrowing is no parameter: only the page goes', () async {
      late Uri asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(
          jsonEncode({'items': [], 'page': 1, 'pageSize': 50, 'total': 0}),
          200,
        );
      });
      final service = ApiProviderService(client: client, baseUrl: 'http://x');

      await service.searchProviders(const ProviderQuery(pageSize: 50));

      expect(asked.queryParameters, {'page': '1', 'pageSize': '50'});
    });

    test('a body without its total is unreadable, not a count of 0', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'items': []}), 200),
      );
      final service = ApiProviderService(client: client, baseUrl: 'http://x');

      final res = await service.searchProviders(const ProviderQuery());

      expect(res.success, isFalse);
      expect(res.code, 'unreadable');
    });

    test('a 400 is an error with its code, not an empty list', () async {
      final client = MockClient(
        (req) async =>
            http.Response(jsonEncode({'error': 'invalid_input'}), 400),
      );
      final service = ApiProviderService(client: client, baseUrl: 'http://x');

      final res = await service.searchProviders(const ProviderQuery());

      expect(res.success, isFalse);
      expect(res.data, isNull);
    });
  });
}
