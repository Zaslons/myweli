import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/artists/[artistId].dart' as artist_detail;
import '../routes/providers/[id]/artists/index.dart' as artists_route;
import '../routes/providers/[id]/availability.dart' as availability;
import '../routes/providers/[id]/before-after.dart' as before_after_route;
import '../routes/providers/[id]/deposit-policy.dart' as deposit_route;
import '../routes/providers/[id]/gallery.dart' as gallery_route;
import '../routes/providers/[id]/index.dart' as provider_route;
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
    catalog = ProviderCatalogService(
      providers,
      providerAuth,
      MembershipService(InMemoryMembershipRepository(), providerAuth),
    );
    final reg = await providerAuth.register(
      email: 'reg3@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-3',
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
        email: 'reg4@test.pro',
        authProvider: 'google',
        googleSub: 'reg-sub-4',
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

    test('gallery: read, replace, validation, ownership', () async {
      // Replace, then read back.
      final saved = await catalog.updateGallery(accountId, 'provider1', {
        'imageUrls': ['https://cdn/a.jpg', '  https://cdn/b.jpg  '],
      });
      expect(saved.ok, isTrue);
      expect((saved.data! as Map)['imageUrls'], [
        'https://cdn/a.jpg',
        'https://cdn/b.jpg', // trimmed
      ]);

      final got = await catalog.gallery(accountId, 'provider1');
      expect((got.data! as Map)['imageUrls'], [
        'https://cdn/a.jpg',
        'https://cdn/b.jpg',
      ]);

      // Validation: over cap (21), non-string, empty entry → invalid_input.
      expect(
        (await catalog.updateGallery(accountId, 'provider1', {
          'imageUrls': List.generate(21, (i) => 'https://cdn/$i.jpg'),
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateGallery(accountId, 'provider1', {
          'imageUrls': [1, 2],
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateGallery(accountId, 'provider1', {
          'imageUrls': ['  '],
        })).error,
        'invalid_input',
      );

      // Ownership: another salon cannot touch provider1's gallery.
      expect(
        (await catalog.gallery(accountId, 'provider2')).error,
        'forbidden',
      );
      expect(
        (await catalog.updateGallery(accountId, 'provider2', {
          'imageUrls': <String>[],
        })).error,
        'forbidden',
      );
    });

    test('before/after: read, replace, validation, ownership', () async {
      final saved = await catalog.updateBeforeAfters(accountId, 'provider1', {
        'beforeAfters': [
          {'before': 'https://cdn/b1.jpg', 'after': '  https://cdn/a1.jpg  '},
          {
            'before': 'https://cdn/b2.jpg',
            'after': 'https://cdn/a2.jpg',
            'caption': '  Tresses  ',
          },
        ],
      });
      expect(saved.ok, isTrue);
      final pairs = (saved.data! as Map)['beforeAfters'] as List;
      expect(pairs.length, 2);
      expect((pairs[0] as Map)['after'], 'https://cdn/a1.jpg'); // trimmed
      expect((pairs[0] as Map).containsKey('caption'), isFalse); // omitted
      expect((pairs[1] as Map)['caption'], 'Tresses'); // trimmed

      final got = await catalog.beforeAfters(accountId, 'provider1');
      expect(((got.data! as Map)['beforeAfters'] as List).length, 2);

      // Validation: >12 pairs · missing `after` · bad-type url · caption >120.
      expect(
        (await catalog.updateBeforeAfters(accountId, 'provider1', {
          'beforeAfters': List.generate(
            13,
            (i) => {
              'before': 'https://cdn/b$i.jpg',
              'after': 'https://cdn/a$i.jpg',
            },
          ),
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateBeforeAfters(accountId, 'provider1', {
          'beforeAfters': [
            {'before': 'https://cdn/b.jpg'},
          ],
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateBeforeAfters(accountId, 'provider1', {
          'beforeAfters': [
            {'before': 'https://cdn/b.jpg', 'after': '  '},
          ],
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateBeforeAfters(accountId, 'provider1', {
          'beforeAfters': [
            {
              'before': 'https://cdn/b.jpg',
              'after': 'https://cdn/a.jpg',
              'caption': 'x' * 121,
            },
          ],
        })).error,
        'invalid_input',
      );

      // Ownership: another salon cannot read/write provider1's pairs.
      expect(
        (await catalog.beforeAfters(accountId, 'provider2')).error,
        'forbidden',
      );
      expect(
        (await catalog.updateBeforeAfters(accountId, 'provider2', {
          'beforeAfters': <Map<String, dynamic>>[],
        })).error,
        'forbidden',
      );
    });

    test(
      'gallery origin allowlist (when configured) rejects foreign URLs',
      () async {
        final scoped = ProviderCatalogService(
          providers,
          providerAuth,
          MembershipService(InMemoryMembershipRepository(), providerAuth),
          allowedImageOrigins: const ['https://cdn.myweli.com', 'asset:'],
        );
        // In-origin + asset placeholder pass.
        expect(
          (await scoped.updateGallery(accountId, 'provider1', {
            'imageUrls': ['https://cdn.myweli.com/g/x.jpg', 'asset:seed.jpg'],
          })).ok,
          isTrue,
        );
        // A foreign origin is rejected.
        expect(
          (await scoped.updateGallery(accountId, 'provider1', {
            'imageUrls': ['https://evil.example/x.jpg'],
          })).error,
          'invalid_input',
        );
      },
    );

    test('deposit policy: read, replace, validation, ownership', () async {
      Map<String, dynamic> validBody({
        bool required = true,
        num pct = 0.4,
        num hours = 24,
        String? op = 'wave',
        String? number = '+2250700000000',
      }) => {
        'depositRequired': required,
        'depositPercentage': pct,
        'cancellationWindowHours': hours,
        'mobileMoneyOperator': op,
        'mobileMoneyNumber': number,
      };

      // T52 (parity audit 8.1): an UNVERIFIED salon cannot enable deposits.
      final gated = await catalog.updateDepositPolicy(
        accountId,
        'provider1',
        validBody(),
      );
      expect(gated.error, 'verification_required');
      // …but can still store a policy with deposits OFF.
      expect(
        (await catalog.updateDepositPolicy(accountId, 'provider1', {
          'depositRequired': false,
          'depositPercentage': 0,
          'cancellationWindowHours': 24,
        })).ok,
        isTrue,
      );

      await providerAuth.setVerification(accountId, status: 'verified');

      // Replace, then read back (DTO uses the mobileMoney* names).
      final saved = await catalog.updateDepositPolicy(
        accountId,
        'provider1',
        validBody(),
      );
      expect(saved.ok, isTrue);
      final d = saved.data! as Map;
      expect(d['depositRequired'], true);
      expect(d['depositPercentage'], 0.4);
      expect(d['mobileMoneyOperator'], 'wave');
      expect(d['mobileMoneyNumber'], '+2250700000000');

      final got = await catalog.depositPolicy(accountId, 'provider1');
      expect((got.data! as Map)['mobileMoneyOperator'], 'wave');

      Future<String?> err(Map<String, dynamic> b) async =>
          (await catalog.updateDepositPolicy(accountId, 'provider1', b)).error;
      // Out-of-range percentage, required-with-0%, bad window, bad operator,
      // bad phone all → invalid_input.
      expect(await err(validBody(pct: 1.5)), 'invalid_input');
      expect(await err(validBody(pct: 0)), 'invalid_input');
      expect(await err(validBody(hours: 1000)), 'invalid_input');
      expect(await err(validBody(op: 'paypal')), 'invalid_input');
      expect(await err(validBody(number: '0700')), 'invalid_input');
      // Required deposit without a Mobile Money handle → invalid_input.
      expect(await err(validBody(op: null, number: null)), 'invalid_input');
      // Not required → handle optional; 0% allowed.
      expect(
        (await catalog.updateDepositPolicy(accountId, 'provider1', {
          'depositRequired': false,
          'depositPercentage': 0,
          'cancellationWindowHours': 48,
        })).ok,
        isTrue,
      );

      // Ownership.
      expect(
        (await catalog.depositPolicy(accountId, 'provider2')).error,
        'forbidden',
      );
      expect(
        (await catalog.updateDepositPolicy(
          accountId,
          'provider2',
          validBody(),
        )).error,
        'forbidden',
      );
    });

    test(
      'artists: create (server-owned id/rating), list, update, delete',
      () async {
        final created = await catalog.createArtist(accountId, 'provider1', {
          'name': 'Awa',
          'specialization': 'Tresses',
          'rating': 5, // client value must be ignored
          'reviewCount': 99,
        });
        expect(created.ok, isTrue);
        final a = created.data! as Map<String, dynamic>;
        expect(a['providerId'], 'provider1');
        expect((a['id'] as String).isNotEmpty, isTrue);
        expect(a['rating'], isNull); // server-owned, not the client's 5
        expect(a['reviewCount'], isNull);

        final list = await catalog.listArtists(accountId, 'provider1');
        expect((list.data! as List).any((x) => x['id'] == a['id']), isTrue);

        final upd = await catalog.updateArtist(
          accountId,
          'provider1',
          a['id'] as String,
          {'name': 'Awa K.', 'rating': 1}, // rating ignored
        );
        expect((upd.data! as Map)['name'], 'Awa K.');
        expect((upd.data! as Map)['rating'], isNull);

        // Empty name → invalid_input.
        expect(
          (await catalog.createArtist(accountId, 'provider1', {
            'name': ' ',
          })).error,
          'invalid_input',
        );
        // Unknown artist → not_found.
        expect(
          (await catalog.updateArtist(accountId, 'provider1', 'nope', {
            'name': 'X',
          })).error,
          'not_found',
        );
        // Cross-salon → forbidden.
        expect(
          (await catalog.createArtist(accountId, 'provider2', {
            'name': 'X',
          })).error,
          'forbidden',
        );

        expect(
          (await catalog.deleteArtist(
            accountId,
            'provider1',
            a['id'] as String,
          )).ok,
          isTrue,
        );
        expect(
          (await catalog.deleteArtist(
            accountId,
            'provider1',
            a['id'] as String,
          )).error,
          'not_found',
        );
      },
    );
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

    test('gallery: GET → 200; PUT replaces → 200; over-cap → 400; '
        'cross-salon → 403; bad verb → 405', () async {
      final got = await gallery_route.onRequest(
        ctx(req('GET', '/providers/provider1/gallery', bearer: token)),
        'provider1',
      );
      expect(got.statusCode, HttpStatus.ok);
      expect((await jsonOf(got))['imageUrls'], isA<List<dynamic>>());

      final put = await gallery_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/gallery',
            bearer: token,
            body: {
              'imageUrls': ['https://cdn/x.jpg', 'https://cdn/y.jpg'],
            },
          ),
        ),
        'provider1',
      );
      expect(put.statusCode, HttpStatus.ok);
      expect((await jsonOf(put))['imageUrls'], [
        'https://cdn/x.jpg',
        'https://cdn/y.jpg',
      ]);

      final overCap = await gallery_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/gallery',
            bearer: token,
            body: {'imageUrls': List.generate(21, (i) => 'https://cdn/$i.jpg')},
          ),
        ),
        'provider1',
      );
      expect(overCap.statusCode, HttpStatus.badRequest);

      final cross = await gallery_route.onRequest(
        ctx(req('GET', '/providers/provider2/gallery', bearer: token)),
        'provider2',
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final badVerb = await gallery_route.onRequest(
        ctx(req('DELETE', '/providers/provider1/gallery', bearer: token)),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('before-after: GET → 200; PUT replaces → 200; bad → 400; '
        'cross-salon → 403; bad verb → 405', () async {
      final got = await before_after_route.onRequest(
        ctx(req('GET', '/providers/provider1/before-after', bearer: token)),
        'provider1',
      );
      expect(got.statusCode, HttpStatus.ok);
      expect((await jsonOf(got))['beforeAfters'], isA<List<dynamic>>());

      final put = await before_after_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/before-after',
            bearer: token,
            body: {
              'beforeAfters': [
                {'before': 'https://cdn/b.jpg', 'after': 'https://cdn/a.jpg'},
              ],
            },
          ),
        ),
        'provider1',
      );
      expect(put.statusCode, HttpStatus.ok);
      expect(((await jsonOf(put))['beforeAfters'] as List).length, 1);

      final bad = await before_after_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/before-after',
            bearer: token,
            body: {
              'beforeAfters': [
                {'before': 'https://cdn/b.jpg'}, // missing after
              ],
            },
          ),
        ),
        'provider1',
      );
      expect(bad.statusCode, HttpStatus.badRequest);

      final cross = await before_after_route.onRequest(
        ctx(req('GET', '/providers/provider2/before-after', bearer: token)),
        'provider2',
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final badVerb = await before_after_route.onRequest(
        ctx(req('DELETE', '/providers/provider1/before-after', bearer: token)),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('deposit policy: GET → 200; PUT replaces → 200; bad → 400; '
        'cross-salon → 403; bad verb → 405', () async {
      // T52: the PUT below enables deposits — needs a verified account.
      await providerAuth.setVerification(accountId, status: 'verified');

      final got = await deposit_route.onRequest(
        ctx(req('GET', '/providers/provider1/deposit-policy', bearer: token)),
        'provider1',
      );
      expect(got.statusCode, HttpStatus.ok);

      final put = await deposit_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/deposit-policy',
            bearer: token,
            body: {
              'depositRequired': true,
              'depositPercentage': 0.5,
              'cancellationWindowHours': 24,
              'mobileMoneyOperator': 'orangeMoney',
              'mobileMoneyNumber': '+2250700000000',
            },
          ),
        ),
        'provider1',
      );
      expect(put.statusCode, HttpStatus.ok);
      expect((await jsonOf(put))['depositPercentage'], 0.5);

      final bad = await deposit_route.onRequest(
        ctx(
          req(
            'PUT',
            '/providers/provider1/deposit-policy',
            bearer: token,
            body: {
              'depositRequired': true,
              'depositPercentage': 0.5,
              'cancellationWindowHours': 24,
              // missing Mobile Money handle for a required deposit
            },
          ),
        ),
        'provider1',
      );
      expect(bad.statusCode, HttpStatus.badRequest);

      final cross = await deposit_route.onRequest(
        ctx(req('GET', '/providers/provider2/deposit-policy', bearer: token)),
        'provider2',
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final badVerb = await deposit_route.onRequest(
        ctx(
          req('DELETE', '/providers/provider1/deposit-policy', bearer: token),
        ),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('artists: POST → 201; GET → 200; PATCH unknown → 404; DELETE → 204; '
        'cross-salon → 403; bad verb → 405', () async {
      final created = await artists_route.onRequest(
        ctx(
          req(
            'POST',
            '/providers/provider1/artists',
            bearer: token,
            body: {'name': 'Awa'},
          ),
        ),
        'provider1',
      );
      expect(created.statusCode, HttpStatus.created);
      final aid = (await jsonOf(created))['id'] as String;

      final list = await artists_route.onRequest(
        ctx(req('GET', '/providers/provider1/artists', bearer: token)),
        'provider1',
      );
      expect(list.statusCode, HttpStatus.ok);
      expect((await jsonOf(list))['total'], greaterThanOrEqualTo(1));

      final patched = await artist_detail.onRequest(
        ctx(
          req(
            'PATCH',
            '/providers/provider1/artists/$aid',
            bearer: token,
            body: {'specialization': 'Coloriste'},
          ),
        ),
        'provider1',
        aid,
      );
      expect(patched.statusCode, HttpStatus.ok);
      expect((await jsonOf(patched))['specialization'], 'Coloriste');

      final missing = await artist_detail.onRequest(
        ctx(
          req(
            'PATCH',
            '/providers/provider1/artists/nope',
            bearer: token,
            body: {'name': 'X'},
          ),
        ),
        'provider1',
        'nope',
      );
      expect(missing.statusCode, HttpStatus.notFound);

      final cross = await artists_route.onRequest(
        ctx(
          req(
            'POST',
            '/providers/provider2/artists',
            bearer: token,
            body: {'name': 'X'},
          ),
        ),
        'provider2',
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final deleted = await artist_detail.onRequest(
        ctx(req('DELETE', '/providers/provider1/artists/$aid', bearer: token)),
        'provider1',
        aid,
      );
      expect(deleted.statusCode, HttpStatus.noContent);

      final badVerb = await artists_route.onRequest(
        ctx(req('DELETE', '/providers/provider1/artists', bearer: token)),
        'provider1',
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('provider profile (M7.3e)', () {
    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderCatalogService>()).thenReturn(catalog);
      return c;
    }

    Request req(String method, {String? bearer, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/providers/provider1'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : jsonEncode(body),
    );

    test('service: owner updates; cross-tenant 403; validation', () async {
      final ok = await catalog.updateProfile(accountId, 'provider1', {
        'name': 'Salon Web',
        'phoneNumber': '+2250700000099',
      });
      expect(ok.ok, isTrue);
      expect((await providers.byId('provider1'))!['name'], 'Salon Web');

      expect(
        (await catalog.updateProfile(accountId, 'provider2', {
          'name': 'X',
        })).error,
        'forbidden',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'name': '  ',
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'phoneNumber': 'abc',
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'slug': 'x',
        })).error,
        'invalid_input',
      );
    });

    test('profile: the map pin + category (pro-salon-lifecycle L1)', () async {
      // A valid pair lands.
      final ok = await catalog.updateProfile(accountId, 'provider1', {
        'latitude': 5.3601,
        'longitude': -3.9905,
        'category': 'barber',
      });
      expect(ok.ok, isTrue);
      final p = (await providers.byId('provider1'))!;
      expect(p['latitude'], 5.3601);
      expect(p['longitude'], -3.9905);
      expect(p['category'], 'barber');

      // Half a pair, out-of-range, junk category → invalid_input.
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'latitude': 5.36,
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'latitude': 123.0,
          'longitude': -3.99,
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'latitude': '5.36',
          'longitude': '-3.99',
        })).error,
        'invalid_input',
      );
      expect(
        (await catalog.updateProfile(accountId, 'provider1', {
          'category': 'bank',
        })).error,
        'invalid_input',
      );
    });

    test('route PATCH: 200 owner · 401 anon · 405 bad verb', () async {
      final ok = await provider_route.onRequest(
        ctx(req('PATCH', bearer: token, body: {'name': 'Salon Z'})),
        'provider1',
      );
      expect(ok.statusCode, HttpStatus.ok);

      final anon = await provider_route.onRequest(
        ctx(req('PATCH', body: {'name': 'Y'})),
        'provider1',
      );
      expect(anon.statusCode, HttpStatus.unauthorized);

      final bad = await provider_route.onRequest(
        ctx(req('PUT', bearer: token)),
        'provider1',
      );
      expect(bad.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
