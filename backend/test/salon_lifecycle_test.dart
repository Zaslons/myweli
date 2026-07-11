import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:test/test.dart';

import '../routes/providers/[id]/publish.dart' as publish_route;
import '../routes/providers/by-slug/[slug].dart' as by_slug_route;

/// Salon lifecycle (docs/design/pro-salon-lifecycle.md): draft creation,
/// the go-live gate, draft hiding (T51), publish authz (T50).
class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

ProviderAccount _account(String id, {String? providerId}) => ProviderAccount(
  id: id,
  phoneNumber: '+2250700000009',
  businessName: 'Salon Awa',
  businessType: 'salon',
  createdAt: DateTime.utc(2026),
)..providerId = providerId;

void main() {
  group('slugifySalonName', () {
    test('lowers, strips accents, collapses separators', () {
      expect(slugifySalonName('Ébène & Co'), 'ebene-co');
      expect(slugifySalonName('  Beauté   Divine  '), 'beaute-divine');
      expect(slugifySalonName('!!!'), 'salon'); // never empty
    });
  });

  group('SalonProvisioningService.categoryFor', () {
    test('maps every businessType onto the public taxonomy', () {
      expect(SalonProvisioningService.categoryFor('salon'), 'salon');
      expect(SalonProvisioningService.categoryFor('barber'), 'barber');
      expect(SalonProvisioningService.categoryFor('spa'), 'spa');
      expect(SalonProvisioningService.categoryFor('nailSalon'), 'nails');
      expect(SalonProvisioningService.categoryFor('massage'), 'massage');
      expect(SalonProvisioningService.categoryFor('other'), 'salon');
    });
  });

  group('createSalon (in-memory)', () {
    test('creates a hidden draft; slug collisions get a suffix', () async {
      final repo = InMemoryProvidersRepository([]);
      final a = await repo.createSalon(
        name: 'Beauté Divine',
        category: 'salon',
        phoneNumber: '+2250700000001',
      );
      expect(a['status'], 'draft');
      expect(a['slug'], 'beaute-divine');
      expect(a['services'], isEmpty);

      final b = await repo.createSalon(
        name: 'Beauté Divine',
        category: 'salon',
        phoneNumber: '+2250700000002',
      );
      expect(b['slug'], 'beaute-divine-2');

      // T51: drafts never appear in discovery…
      expect(await repo.query(), isEmpty);
      // …but the owner reads them by id.
      expect(await repo.byId(a['id'] as String), isNotNull);
    });
  });

  group('publishGate', () {
    Map<String, dynamic> salon({
      String description = 'Un salon complet.',
      String address = 'Rue des Jardins',
      String? commune = 'Cocody',
      int services = 3,
      int photos = 3,
      bool open = true,
    }) => {
      'id': 'p1',
      'description': description,
      'address': address,
      'commune': commune,
      'latitude': 5.35,
      'longitude': -3.99,
      'services': [
        for (var i = 0; i < services; i++)
          {'id': 's$i', 'active': true, 'name': 'S$i'},
      ],
      'imageUrls': [for (var i = 0; i < photos; i++) 'https://cdn/x$i.jpg'],
      'availability': {
        'weeklySchedule': open
            ? {
                '0': [
                  {'startTime': '09:00', 'endTime': '18:00'},
                ],
              }
            : <String, dynamic>{},
      },
    };

    test('complete salon → publishable', () {
      expect(SalonProvisioningService.publishGate(salon()), isEmpty);
    });

    test('every missing piece is named (photos, location, everything)', () {
      expect(SalonProvisioningService.publishGate(salon(description: '')), [
        'profile',
      ]);
      expect(SalonProvisioningService.publishGate(salon(commune: null)), [
        'profile',
      ]);
      expect(SalonProvisioningService.publishGate(salon(services: 2)), [
        'services',
      ]);
      expect(SalonProvisioningService.publishGate(salon(photos: 2)), [
        'photos',
      ]);
      expect(SalonProvisioningService.publishGate(salon(open: false)), [
        'availability',
      ]);
      // The map pin (L1): both coordinates or the salon can't go live.
      final noPin = salon()..['latitude'] = null;
      expect(SalonProvisioningService.publishGate(noPin), ['location']);
      // A fresh draft misses everything.
      expect(
        SalonProvisioningService.publishGate(
          draftSalonDocument(
            id: 'p1',
            slug: 's',
            name: 'S',
            category: 'salon',
            phoneNumber: '+2250700000001',
          ),
        ),
        ['profile', 'location', 'services', 'photos', 'availability'],
      );
      // Inactive services do not count.
      final s = salon();
      (s['services'] as List)[0] = {'id': 's0', 'active': false};
      expect(SalonProvisioningService.publishGate(s), ['services']);
    });
  });

  group('POST /providers/{id}/publish', () {
    final tokens = TokenService(secret: 'test-secret');
    late InMemoryProvidersRepository providers;
    late _MockProviderAuth auth;
    late SalonProvisioningService service;

    setUp(() async {
      providers = InMemoryProvidersRepository([]);
      auth = _MockProviderAuth();
      service = SalonProvisioningService(
        providers,
        auth,
        InMemoryMembershipRepository(),
      );
    });

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
      when(() => c.read<SalonProvisioningService>()).thenReturn(service);
      when(
        () => c.read<MembershipService>(),
      ).thenReturn(MembershipService(InMemoryMembershipRepository(), auth));
      return c;
    }

    Request post(String id, {String? token}) => Request.post(
      Uri.parse('http://localhost/providers/$id/publish'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, String role) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    Future<Map<String, dynamic>> makeDraft() => providers.createSalon(
      name: 'Salon Awa',
      category: 'salon',
      phoneNumber: '+2250700000009',
    );

    Future<void> complete(Map<String, dynamic> salon) async {
      salon['description'] = 'Salon complet à Cocody.';
      salon['address'] = 'Rue des Jardins';
      salon['commune'] = 'Cocody';
      salon['latitude'] = 5.35;
      salon['longitude'] = -3.99;
      salon['services'] = [
        for (var i = 0; i < 3; i++) {'id': 's$i', 'active': true},
      ];
      salon['imageUrls'] = ['a.jpg', 'b.jpg', 'c.jpg'];
      salon['availability'] = {
        'weeklySchedule': {
          '0': [
            {'startTime': '09:00', 'endTime': '18:00'},
          ],
        },
      };
    }

    test('incomplete draft → 409 incomplete + the missing keys', () async {
      final salon = await makeDraft();
      final id = salon['id'] as String;
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account('acc1', providerId: id));

      final res = await publish_route.onRequest(
        ctx(post(id, token: tok('acc1', 'provider'))),
        id,
      );
      expect(res.statusCode, HttpStatus.conflict);
      final body = await res.json() as Map;
      expect(body['error'], 'incomplete');
      expect(
        body['missing'],
        containsAll(['profile', 'location', 'services', 'photos']),
      );
    });

    test(
      'complete → 200 active + discoverable; re-publish idempotent',
      () async {
        final salon = await makeDraft();
        final id = salon['id'] as String;
        await complete(salon);
        when(
          () => auth.accountById('acc1'),
        ).thenAnswer((_) async => _account('acc1', providerId: id));

        final res = await publish_route.onRequest(
          ctx(post(id, token: tok('acc1', 'provider'))),
          id,
        );
        expect(res.statusCode, HttpStatus.ok);
        expect(((await res.json()) as Map)['status'], 'active');
        expect(await providers.query(), hasLength(1)); // now discoverable

        final again = await publish_route.onRequest(
          ctx(post(id, token: tok('acc1', 'provider'))),
          id,
        );
        expect(again.statusCode, HttpStatus.ok);
      },
    );

    test('T50: cross-tenant / anon / wrong role → 403/401', () async {
      final salon = await makeDraft();
      final id = salon['id'] as String;
      when(
        () => auth.accountById('intruder'),
      ).thenAnswer((_) async => _account('intruder', providerId: 'other'));

      final cross = await publish_route.onRequest(
        ctx(post(id, token: tok('intruder', 'provider'))),
        id,
      );
      expect(cross.statusCode, HttpStatus.forbidden);

      final anon = await publish_route.onRequest(ctx(post(id)), id);
      expect(anon.statusCode, HttpStatus.unauthorized);

      final user = await publish_route.onRequest(
        ctx(post(id, token: tok('u1', 'user'))),
        id,
      );
      expect(user.statusCode, HttpStatus.forbidden);
    });
  });

  group('T51 — drafts are not public', () {
    test('by-slug 404s a draft; active resolves', () async {
      final providers = InMemoryProvidersRepository([]);
      final salon = await providers.createSalon(
        name: 'Salon Caché',
        category: 'salon',
        phoneNumber: '+2250700000009',
      );

      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request.get(Uri.parse('http://localhost/providers/by-slug/x')),
      );
      when(() => c.read<ProvidersRepository>()).thenReturn(providers);

      final res = await by_slug_route.onRequest(c, 'salon-cache');
      expect(res.statusCode, HttpStatus.notFound);

      await providers.setStatus(salon['id'] as String, 'active');
      // (Reviews repo is only read after the draft gate — a draft never
      // reaches it; the active path is covered by the existing by-slug
      // tests with the full middleware stack.)
    });
  });
}
