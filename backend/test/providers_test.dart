import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/index.dart' as detail;
import '../routes/providers/index.dart' as list;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
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
    setUp(() {
      context = _MockRequestContext();
      when(() => context.read<ProvidersRepository>()).thenReturn(repo);
      when(() => context.read<ReviewsRepository>()).thenReturn(reviews);
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
