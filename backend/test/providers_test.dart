import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/provider_discovery.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/index.dart' as detail;
import '../routes/providers/index.dart' as list;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('sortProviders (FR-DISC-007)', () {
    final list = [
      {
        'id': 'a',
        'rating': 4.2,
        'services': [
          {'price': 9000, 'active': true},
        ],
      },
      {
        'id': 'b',
        'rating': 4.9,
        'services': [
          {'price': 15000, 'active': true},
          {'price': 5000, 'active': false}, // inactive ignored
        ],
      },
      {
        'id': 'c',
        'rating': 4.5,
        'services': const <Map<String, dynamic>>[],
      }, // no price → last
    ];

    test('rating sorts desc', () {
      expect(sortProviders(list, 'rating').map((p) => p['id']), [
        'b',
        'c',
        'a',
      ]);
    });

    test('price sorts by min active price asc; no-price last', () {
      expect(sortProviders(list, 'price').map((p) => p['id']), ['a', 'b', 'c']);
    });

    test('relevance / unknown keeps the input order', () {
      expect(sortProviders(list, null).map((p) => p['id']), ['a', 'b', 'c']);
      expect(sortProviders(list, 'relevance').map((p) => p['id']), [
        'a',
        'b',
        'c',
      ]);
    });
  });

  group('InMemoryProvidersRepository', () {
    final repo = InMemoryProvidersRepository();

    test('returns all providers sorted by rating desc', () async {
      final all = await repo.query();
      expect(all, isNotEmpty);
      for (var i = 1; i < all.length; i++) {
        expect(
          (all[i - 1]['rating'] as num) >= (all[i]['rating'] as num),
          isTrue,
        );
      }
    });

    test('filters by category and commune', () async {
      expect(
        (await repo.query(
          category: 'barber',
        )).every((p) => p['category'] == 'barber'),
        isTrue,
      );
      expect(
        (await repo.query(
          commune: 'Cocody',
        )).every((p) => p['commune'] == 'Cocody'),
        isTrue,
      );
    });

    test('free-text search matches name/description/address', () async {
      final res = await repo.query(q: 'barbier');
      expect(res, isNotEmpty);
      expect(res.first['id'], 'provider3');
    });

    test('byId hits and misses', () async {
      expect(await repo.byId('provider1'), isNotNull);
      expect(await repo.byId('nope'), isNull);
    });
  });

  group('routes', () {
    late RequestContext context;
    final repo = InMemoryProvidersRepository();
    final reviews = InMemoryReviewsRepository();
    final slots = SlotService(repo, InMemoryAppointmentRepository());
    setUp(() {
      context = _MockRequestContext();
      when(() => context.read<ProvidersRepository>()).thenReturn(repo);
      when(() => context.read<ReviewsRepository>()).thenReturn(reviews);
      when(() => context.read<SlotService>()).thenReturn(slots);
    });

    test('GET /providers returns a page with items + total', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/providers?pageSize=2')),
      );

      final response = await list.onRequest(context);
      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as Map<String, dynamic>;
      expect((body['items'] as List).length, 2);
      expect(body['total'], greaterThanOrEqualTo(2));
    });

    test('GET /providers?category=barber filters', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/providers?category=barber')),
      );

      final response = await list.onRequest(context);
      final body = await response.json() as Map<String, dynamic>;
      final items = body['items'] as List;
      expect(items, isNotEmpty);
      expect(items.every((p) => (p as Map)['category'] == 'barber'), isTrue);
    });

    test('GET /providers?sort=rating orders by rating desc', () async {
      when(() => context.request).thenReturn(
        Request.get(
          Uri.parse('http://localhost/providers?sort=rating&pageSize=50'),
        ),
      );
      final body =
          await (await list.onRequest(context)).json() as Map<String, dynamic>;
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      for (var i = 1; i < items.length; i++) {
        expect(
          (items[i - 1]['rating'] as num) >= (items[i]['rating'] as num),
          isTrue,
        );
      }
    });

    test(
      'GET /providers?availableToday=true → only salons free today',
      () async {
        final today = DateTime.now().toUtc();
        final all = await repo.query();
        final expected = <String>[];
        for (final p in all) {
          final r = await slots.availableSlots(
            providerId: p['id'] as String,
            date: today,
          );
          if (r.slots != null && r.slots!.isNotEmpty) {
            expected.add(p['id'] as String);
          }
        }

        when(() => context.request).thenReturn(
          Request.get(
            Uri.parse(
              'http://localhost/providers?availableToday=true&pageSize=50',
            ),
          ),
        );
        final body =
            await (await list.onRequest(context)).json()
                as Map<String, dynamic>;
        final ids = (body['items'] as List)
            .map((p) => (p as Map)['id'])
            .toList();
        expect(ids.toSet(), expected.toSet());
        expect(body['total'], expected.length);
      },
    );

    test(
      'GET /providers/{id} returns the provider, 404 when missing',
      () async {
        when(() => context.request).thenReturn(
          Request.get(Uri.parse('http://localhost/providers/provider1')),
        );
        final ok = await detail.onRequest(context, 'provider1');
        expect(ok.statusCode, HttpStatus.ok);
        final body = await ok.json() as Map<String, dynamic>;
        expect(body['id'], 'provider1');

        final missing = await detail.onRequest(context, 'nope');
        expect(missing.statusCode, HttpStatus.notFound);
      },
    );

    test('non-GET is rejected with 405', () async {
      when(
        () => context.request,
      ).thenReturn(Request.post(Uri.parse('http://localhost/providers')));
      final response = await list.onRequest(context);
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
