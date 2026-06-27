import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/cors.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/slug.dart';
import 'package:test/test.dart';

import '../routes/providers/by-slug/[slug].dart' as by_slug;
import '../routes/sitemap/providers.dart' as sitemap;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockReviews extends Mock implements ReviewsRepository {}

void main() {
  group('slugify', () {
    test('lowercases, deaccents, hyphenates, trims', () {
      expect(slugify('Beauté Divine'), 'beaute-divine');
      expect(slugify('Élégance Coiffure'), 'elegance-coiffure');
      expect(slugify('Nails & Co'), 'nails-co');
      expect(slugify('  Salon   Excellence!! '), 'salon-excellence');
      expect(slugify('Çà & Là'), 'ca-la');
    });
  });

  group('InMemoryProvidersRepository.bySlug', () {
    final repo = InMemoryProvidersRepository();
    test('resolves a seeded slug; misses return null', () async {
      final p = await repo.bySlug('beaute-divine');
      expect(p?['id'], 'provider1');
      expect(await repo.bySlug('does-not-exist'), isNull);
    });
  });

  group('GET /providers/by-slug/{slug}', () {
    late InMemoryProvidersRepository providers;
    late _MockReviews reviews;

    setUp(() {
      providers = InMemoryProvidersRepository();
      reviews = _MockReviews();
      when(
        () => reviews.recentForProvider(any(), any()),
      ).thenAnswer((_) async => const []);
    });

    RequestContext ctx(String method) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(method, Uri.parse('http://localhost/providers/by-slug/x')),
      );
      when(() => c.read<ProvidersRepository>()).thenReturn(providers);
      when(() => c.read<ReviewsRepository>()).thenReturn(reviews);
      return c;
    }

    test('known slug → 200 with the provider', () async {
      final res = await by_slug.onRequest(ctx('GET'), 'beaute-divine');
      expect(res.statusCode, HttpStatus.ok);
      expect((await res.json() as Map)['id'], 'provider1');
    });

    test('unknown slug → 404', () async {
      final res = await by_slug.onRequest(ctx('GET'), 'nope');
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('non-GET → 405', () async {
      final res = await by_slug.onRequest(ctx('POST'), 'beaute-divine');
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /sitemap/providers', () {
    test('lists active provider slugs', () async {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request.get(Uri.parse('http://localhost/sitemap/providers')),
      );
      when(
        () => c.read<ProvidersRepository>(),
      ).thenReturn(InMemoryProvidersRepository());
      final res = await sitemap.onRequest(c);
      expect(res.statusCode, HttpStatus.ok);
      final items = (await res.json() as Map)['items'] as List;
      expect(items.map((e) => (e as Map)['slug']), contains('beaute-divine'));
    });
  });

  group('corsMiddleware', () {
    final mw = corsMiddleware(const ['http://localhost:3000']);
    Handler wrap() => mw((_) async => Response(body: 'ok'));

    RequestContext ctx(String method, {String? origin}) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost/providers'),
          headers: origin == null ? null : {'Origin': origin},
        ),
      );
      return c;
    }

    test('allowed origin → echoes CORS headers', () async {
      final res = await wrap()(ctx('GET', origin: 'http://localhost:3000'));
      expect(
        res.headers['Access-Control-Allow-Origin'],
        'http://localhost:3000',
      );
      expect(res.headers['Access-Control-Allow-Credentials'], 'true');
    });

    test('preflight OPTIONS (allowed) → 204', () async {
      final res = await wrap()(ctx('OPTIONS', origin: 'http://localhost:3000'));
      expect(res.statusCode, 204);
      expect(
        res.headers['Access-Control-Allow-Origin'],
        'http://localhost:3000',
      );
    });

    test('disallowed origin → no CORS headers', () async {
      final res = await wrap()(ctx('GET', origin: 'http://evil.example'));
      expect(res.headers.containsKey('Access-Control-Allow-Origin'), isFalse);
    });
  });
}
