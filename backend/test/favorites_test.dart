import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/favorites_repository.dart';
import 'package:myweli_backend/src/favorites_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../routes/me/favorites/[providerId].dart' as item;
import '../routes/me/favorites/index.dart' as list_route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryFavoritesRepository repo;
  late FavoritesService service;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;
  final providerTok = tokens
      .issueAccessToken(subject: 'acc1', role: 'provider')
      .token;

  setUp(() {
    repo = InMemoryFavoritesRepository();
    service = FavoritesService(repo, InMemoryProvidersRepository());
  });

  group('FavoritesRepository', () {
    test(
      'add is idempotent, newest-first; remove is idempotent; isolated',
      () async {
        await repo.add('user_A', 'provider1');
        await repo.add('user_A', 'provider1'); // dup → no-op
        await repo.add('user_A', 'provider2');
        expect(await repo.listForUser('user_A'), ['provider2', 'provider1']);
        expect(await repo.listForUser('user_B'), isEmpty); // isolation

        await repo.remove('user_A', 'provider1');
        await repo.remove('user_A', 'provider1'); // already gone → no-op
        expect(await repo.listForUser('user_A'), ['provider2']);
      },
    );
  });

  group('FavoritesService', () {
    test(
      'add validates provider existence; list + remove round-trip',
      () async {
        expect((await service.add('user_A', 'nope')).error, 'not_found');

        expect((await service.add('user_A', 'provider1')).ok, isTrue);
        expect((await service.list('user_A')).providerIds, ['provider1']);

        expect((await service.remove('user_A', 'provider1')).ok, isTrue);
        expect((await service.list('user_A')).providerIds, isEmpty);
      },
    );
  });

  group('a favourite survives the salon going dark (Decision C)', () {
    // The relationship lives on the server, so the server hydrates it. Web
    // fanned out one `GET /providers/{id}` per favourite and dropped any that
    // 404'd — so closing the public read would have made a favourite of a
    // stopped salon SILENTLY VANISH from the list and from the RGPD export,
    // on a page whose own copy promises « profil, rendez-vous et favoris ».
    late InMemoryProvidersRepository salons;
    late InMemoryFavoritesRepository stored;
    late FavoritesService svc;

    setUp(() {
      // Isolated fixtures, never the shared mutable `seedProviders`:
      // `admin_provider_test.dart:53` suspends `provider1` without restoring.
      salons = InMemoryProvidersRepository([
        {'id': 'live', 'name': 'Salon Live', 'status': 'active'},
        {'id': 'stopped', 'name': 'Salon Arrêté', 'status': 'suspended'},
        {'id': 'unpublished', 'name': 'Salon Brouillon', 'status': 'draft'},
      ]);
      stored = InMemoryFavoritesRepository();
      svc = FavoritesService(stored, salons);
    });

    test('a suspended salon is returned, carrying its status', () async {
      await svc.add('user_A', 'live');
      final r = await svc.list('user_A');
      // Favouriting a stopped salon is impossible now (below), so seed it the
      // way reality does — the salon stops AFTER it was favourited — by
      // writing to the STORAGE directly. The guard lives on the service.
      await stored.add('user_A', 'stopped');

      final after = await svc.list('user_A');
      expect(after.providerIds, containsAll(['live', 'stopped']));
      final byId = {for (final p in after.providers!) p['id'] as String: p};
      expect(byId.keys, containsAll(['live', 'stopped']));
      expect(byId['stopped']!['status'], 'suspended');
      expect(byId['stopped']!['name'], 'Salon Arrêté');
      // The pair: a live salon must not be marked stopped, or « always
      // suspended » would pass everything above.
      expect(byId['live']!['status'], 'active');
      expect(r.providerIds, ['live']);
    });

    test('providerIds still ships — a released app build reads it', () async {
      // Additive, not replacing: `api_favorites_service.dart` is on real
      // devices in the field and parses `providerIds`.
      await svc.add('user_A', 'live');
      expect((await svc.list('user_A')).providerIds, ['live']);
    });

    test('you cannot NEWLY favourite a salon you cannot reach', () async {
      // The other half of the rule. The existing favourite is a relationship;
      // a new one would be a way to name a salon the public read hides.
      expect((await svc.add('user_A', 'stopped')).error, 'not_found');
      expect((await svc.add('user_A', 'unpublished')).error, 'not_found');
      // The pair.
      expect((await svc.add('user_A', 'live')).ok, isTrue);
    });

    test('a salon that no longer exists at all just drops out', () async {
      await stored.add('user_A', 'vanished');
      final r = await svc.list('user_A');
      expect(r.providerIds, contains('vanished'));
      expect(
        r.providers!.map((p) => p['id']),
        isNot(contains('vanished')),
        reason:
            'a deleted salon has no document to hydrate — unlike a hidden '
            'one, which does',
      );
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<FavoritesService>()).thenReturn(service);
      return context;
    }

    Request req(String method, String path, {String? bearer}) => Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
    );

    test('GET → 200; POST → 204; unknown → 404; DELETE → 204; isolated; '
        '401/403/405', () async {
      // Empty to start.
      final empty = await list_route.onRequest(
        ctx(req('GET', '/me/favorites', bearer: accessA)),
      );
      expect(empty.statusCode, HttpStatus.ok);
      expect((await empty.json() as Map)['providerIds'], isEmpty);

      // Add provider1.
      final added = await item.onRequest(
        ctx(req('POST', '/me/favorites/provider1', bearer: accessA)),
        'provider1',
      );
      expect(added.statusCode, HttpStatus.noContent);

      final afterAdd = await list_route.onRequest(
        ctx(req('GET', '/me/favorites', bearer: accessA)),
      );
      expect((await afterAdd.json() as Map)['providerIds'], ['provider1']);

      // Unknown provider → 404.
      final unknown = await item.onRequest(
        ctx(req('POST', '/me/favorites/nope', bearer: accessA)),
        'nope',
      );
      expect(unknown.statusCode, HttpStatus.notFound);

      // Cross-user isolation: B sees nothing.
      final bList = await list_route.onRequest(
        ctx(req('GET', '/me/favorites', bearer: accessB)),
      );
      expect((await bList.json() as Map)['providerIds'], isEmpty);

      // Remove.
      final removed = await item.onRequest(
        ctx(req('DELETE', '/me/favorites/provider1', bearer: accessA)),
        'provider1',
      );
      expect(removed.statusCode, HttpStatus.noContent);

      // No token → 401.
      final noAuth = await list_route.onRequest(
        ctx(req('GET', '/me/favorites')),
      );
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      // Provider token → 403 (consumer feature).
      final asProvider = await list_route.onRequest(
        ctx(req('GET', '/me/favorites', bearer: providerTok)),
      );
      expect(asProvider.statusCode, HttpStatus.forbidden);

      // Bad verb → 405.
      final badVerb = await item.onRequest(
        ctx(req('PUT', '/me/favorites/provider1', bearer: accessA)),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
