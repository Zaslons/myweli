import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/availability.dart' as availability;
import '../routes/providers/[id]/services/[serviceId].dart' as service_detail;
import '../routes/providers/[id]/services/index.dart' as services;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late InMemoryProvidersRepository providers;
  late InMemoryProviderAuthRepository providerAuth;
  late ProviderCatalogService catalog;
  final tokens = TokenService(secret: 'test-secret');
  late String accountId; // linked to provider1
  late String token;

  setUp(() async {
    providers = InMemoryProvidersRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    catalog = ProviderCatalogService(providers, providerAuth);
    final reg = await providerAuth.register(
      phoneNumber: '+2250500000010',
      businessName: 'X',
      businessType: 'salon',
      providerId: 'provider1',
    );
    accountId = reg.provider!.id;
    token = tokens.issueAccessToken(subject: accountId, role: 'provider').token;
  });

  group('ProviderCatalogService', () {
    test('create sets id/providerId/active, lists, updates, deletes', () async {
      final created = await catalog.createService(accountId, 'provider1', {
        'name': 'Coupe',
        'price': 5000,
        'durationMinutes': 30,
      });
      expect(created.ok, isTrue);
      final svc = created.data! as Map<String, dynamic>;
      expect(svc['providerId'], 'provider1');
      expect(svc['active'], true);
      expect((svc['id'] as String).isNotEmpty, isTrue);

      final list = await catalog.listServices(accountId, 'provider1');
      expect((list.data! as List).any((s) => s['id'] == svc['id']), isTrue);

      final upd = await catalog.updateService(
        accountId,
        'provider1',
        svc['id'] as String,
        {'price': 6000, 'active': false},
      );
      expect((upd.data! as Map)['price'], 6000);
      expect((upd.data! as Map)['active'], false);

      expect(
        (await catalog.deleteService(
          accountId,
          'provider1',
          svc['id'] as String,
        )).ok,
        isTrue,
      );
      expect(
        (await catalog.deleteService(
          accountId,
          'provider1',
          svc['id'] as String,
        )).error,
        'not_found',
      );
    });

    test(
      'rejects invalid name / price / duration with invalid_input',
      () async {
        Future<String?> err(Map<String, dynamic> b) async =>
            (await catalog.createService(accountId, 'provider1', b)).error;
        expect(
          await err({'name': '', 'price': 1, 'durationMinutes': 30}),
          'invalid_input',
        );
        expect(
          await err({'name': 'X', 'price': -1, 'durationMinutes': 30}),
          'invalid_input',
        );
        expect(
          await err({'name': 'X', 'price': 1, 'durationMinutes': 0}),
          'invalid_input',
        );
      },
    );

    test('a token for another salon → forbidden', () async {
      expect(
        (await catalog.createService(accountId, 'provider2', {
          'name': 'X',
          'price': 1,
          'durationMinutes': 30,
        })).error,
        'forbidden',
      );
      expect(
        (await catalog.getAvailability(accountId, 'provider2')).error,
        'forbidden',
      );
    });

    test('an unlinked provider account → forbidden', () async {
      final reg = await providerAuth.register(
        phoneNumber: '+2250500000011',
        businessName: 'Y',
        businessType: 'salon',
      );
      expect(
        (await catalog.listServices(reg.provider!.id, 'provider1')).error,
        'forbidden',
      );
    });

    test('replaceAvailability round-trips and validates windows', () async {
      final ok = await catalog.replaceAvailability(accountId, 'provider1', {
        'weeklySchedule': {
          '0': [
            {
              'startTime': '2024-01-01T09:00:00.000Z',
              'endTime': '2024-01-01T12:00:00.000Z',
              'isAvailable': true,
            },
          ],
        },
        'breaks': <String, dynamic>{},
        'blockedDates': <String>[],
        'bufferMinutes': 15,
      });
      expect(ok.ok, isTrue);
      expect((ok.data! as Map)['bufferMinutes'], 15);

      final bad = await catalog.replaceAvailability(accountId, 'provider1', {
        'weeklySchedule': {
          '0': [
            {
              'startTime': '2024-01-01T12:00:00.000Z',
              'endTime': '2024-01-01T09:00:00.000Z',
              'isAvailable': true,
            },
          ],
        },
      });
      expect(bad.error, 'invalid_input');
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<ProviderCatalogService>()).thenReturn(catalog);
      return context;
    }

    Request req(String method, String path, {String? bearer, Object? body}) =>
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
          body: body == null ? null : jsonEncode(body),
        );

    Future<Map<String, dynamic>> jsonOf(Response r) async =>
        await r.json() as Map<String, dynamic>;

    test(
      'POST → 201; GET list → 200; no token → 401; bad verb → 405',
      () async {
        final created = await services.onRequest(
          ctx(
            req(
              'POST',
              '/providers/provider1/services',
              bearer: token,
              body: {'name': 'Coupe', 'price': 5000, 'durationMinutes': 30},
            ),
          ),
          'provider1',
        );
        expect(created.statusCode, HttpStatus.created);

        final list = await services.onRequest(
          ctx(req('GET', '/providers/provider1/services', bearer: token)),
          'provider1',
        );
        expect(list.statusCode, HttpStatus.ok);
        expect((await jsonOf(list))['total'], greaterThanOrEqualTo(1));

        final noAuth = await services.onRequest(
          ctx(req('GET', '/providers/provider1/services')),
          'provider1',
        );
        expect(noAuth.statusCode, HttpStatus.unauthorized);

        final badVerb = await services.onRequest(
          ctx(req('DELETE', '/providers/provider1/services', bearer: token)),
          'provider1',
        );
        expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
      },
    );

    test('cross-salon POST → 403', () async {
      final res = await services.onRequest(
        ctx(
          req(
            'POST',
            '/providers/provider2/services',
            bearer: token,
            body: {'name': 'X', 'price': 1, 'durationMinutes': 30},
          ),
        ),
        'provider2',
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('PATCH unknown → 404; PATCH active → 200; DELETE → 204', () async {
      final created = await services.onRequest(
        ctx(
          req(
            'POST',
            '/providers/provider1/services',
            bearer: token,
            body: {'name': 'X', 'price': 1, 'durationMinutes': 30},
          ),
        ),
        'provider1',
      );
      final sid = (await jsonOf(created))['id'] as String;

      final patched = await service_detail.onRequest(
        ctx(
          req(
            'PATCH',
            '/providers/provider1/services/$sid',
            bearer: token,
            body: {'active': false},
          ),
        ),
        'provider1',
        sid,
      );
      expect(patched.statusCode, HttpStatus.ok);
      expect((await jsonOf(patched))['active'], false);

      final missing = await service_detail.onRequest(
        ctx(
          req(
            'PATCH',
            '/providers/provider1/services/nope',
            bearer: token,
            body: {'price': 1},
          ),
        ),
        'provider1',
        'nope',
      );
      expect(missing.statusCode, HttpStatus.notFound);

      final deleted = await service_detail.onRequest(
        ctx(req('DELETE', '/providers/provider1/services/$sid', bearer: token)),
        'provider1',
        sid,
      );
      expect(deleted.statusCode, HttpStatus.noContent);
    });

    test('GET availability → 200; PUT replaces → 200', () async {
      final got = await availability.onRequest(
        ctx(req('GET', '/providers/provider1/availability', bearer: token)),
        'provider1',
      );
      expect(got.statusCode, HttpStatus.ok);

      final put = await availability.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/availability',
            bearer: token,
            body: {
              'weeklySchedule': <String, dynamic>{},
              'breaks': <String, dynamic>{},
              'blockedDates': <String>[],
              'bufferMinutes': 20,
            },
          ),
        ),
        'provider1',
      );
      expect(put.statusCode, HttpStatus.ok);
      expect((await jsonOf(put))['bufferMinutes'], 20);
    });
  });
}
