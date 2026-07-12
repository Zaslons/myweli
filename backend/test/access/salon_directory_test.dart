import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/salon_directory_service.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

import '../../routes/me/salons/index.dart' as me_salons;

class _MockRequestContext extends Mock implements RequestContext {}

/// Module `access` R6 — the « Mes salons » directory + « Ajouter un salon »
/// (docs/design/team-access-r6-multi-salons.md §3): the picker payload, the
/// server-computed Réseau gate, the creation effects (draft + owner row +
/// badge inheritance + untouched scalar), and the abuse cap.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository memberships;
  late InMemoryProvidersRepository providers;
  late MembershipService resolver;
  late SalonSubscriptionService subscriptions;
  late SalonDirectoryService directory;
  late String ownerId;

  setUp(() async {
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    memberships = InMemoryMembershipRepository();
    providers = InMemoryProvidersRepository([
      {
        'id': 'p1',
        'name': 'Chez Awa',
        'status': 'active',
        'verified': true,
        'imageUrls': ['https://cdn.test/p1.jpg'],
      },
      {'id': 'p2', 'name': 'Beauté Zen', 'status': 'draft'},
    ]);
    resolver = MembershipService(memberships, auth);
    subscriptions = SalonSubscriptionService(
      InMemorySalonSubscriptionRepository(),
      resolver,
      memberships,
      providers,
      auth,
    );
    directory = SalonDirectoryService(
      memberships,
      resolver,
      providers,
      subscriptions,
      auth,
    );

    final reg = await auth.register(
      businessName: 'Chez Awa',
      businessType: 'salon',
      phoneNumber: '+2250500000081',
      email: 'owner@dir.pro',
      authProvider: 'google',
      googleSub: 'sub-dir-owner',
      providerId: 'p1',
    );
    ownerId = reg.provider!.id;
  });

  Future<void> makeReseau(String salonId) async {
    await memberships.ensureOwner(
      providerId: salonId,
      accountId: ownerId,
      email: 'owner@dir.pro',
    );
    final r = await subscriptions.chooseOffer(ownerId, salonId, 'reseau');
    expect(r.ok, isTrue, reason: 'seed reseau failed: ${r.error}');
  }

  group('listForAccount', () {
    test('the scalar-linked owner self-heals into the list (shape + '
        'badge + thumb)', () async {
      // No membership row seeded — the heal must surface p1 anyway.
      final items = await directory.listForAccount(ownerId);
      expect(items, hasLength(1));
      final e = items.first;
      expect(e['salonId'], 'p1');
      expect(e['salonName'], 'Chez Awa');
      expect(e['role'], 'owner');
      expect(e['salonStatus'], 'active');
      expect(e['verified'], isTrue);
      expect(e['imageUrl'], 'https://cdn.test/p1.jpg');
    });

    test('owned first, then salonName case-insensitively', () async {
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: ownerId,
        email: 'owner@dir.pro',
      );
      // A member row elsewhere (manager in p2) sorts after the owned salon.
      final inv = await memberships.invite(
        providerId: 'p2',
        email: 'owner@dir.pro',
        role: 'manager',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(inv.id, ownerId);

      final items = await directory.listForAccount(ownerId);
      expect(items.map((e) => e['salonId']).toList(), ['p1', 'p2']);
      expect(items[1]['role'], 'manager');
      expect(items[1]['salonStatus'], 'draft');
      expect(items[1]['verified'], isFalse);
    });

    test('revoked and pending-invited rows are excluded', () async {
      final bare = await auth.register(
        businessName: 'Z',
        businessType: 'salon',
        phoneNumber: '+2250500000082',
        email: 'bare@dir.pro',
        authProvider: 'google',
        googleSub: 'sub-bare',
      );
      final bareId = bare.provider!.id;
      // Pending invitation (not activated).
      await memberships.invite(
        providerId: 'p1',
        email: 'bare@dir.pro',
        role: 'reception',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      expect(await directory.listForAccount(bareId), isEmpty);

      // Activated then revoked.
      final inv2 = await memberships.invite(
        providerId: 'p2',
        email: 'bare@dir.pro',
        role: 'staff',
        artistId: 'a1',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(inv2.id, bareId);
      await memberships.revokeAllForAccount(bareId);
      expect(await directory.listForAccount(bareId), isEmpty);
    });
  });

  group('canAddSalon (the Réseau gate)', () {
    test('no offer anywhere → false', () async {
      expect(await directory.canAddSalon(ownerId), isFalse);
    });

    test('a live PRO offer → false (Réseau only)', () async {
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: ownerId,
        email: 'owner@dir.pro',
      );
      await subscriptions.chooseOffer(ownerId, 'p1', 'pro');
      expect(await directory.canAddSalon(ownerId), isFalse);
    });

    test('a live Réseau offer on an OWNED salon → true', () async {
      await makeReseau('p1');
      expect(await directory.canAddSalon(ownerId), isTrue);
    });

    test('Réseau on a salon the caller only MANAGES → false', () async {
      // p2 is Réseau'd by its own owner; our caller is just a manager there.
      final other = await auth.register(
        businessName: 'Other',
        businessType: 'salon',
        phoneNumber: '+2250500000083',
        email: 'other@dir.pro',
        authProvider: 'google',
        googleSub: 'sub-other',
        providerId: 'p2',
      );
      final otherId = other.provider!.id;
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: otherId,
        email: 'other@dir.pro',
      );
      await subscriptions.chooseOffer(otherId, 'p2', 'reseau');

      final bare = await auth.register(
        businessName: 'M',
        businessType: 'salon',
        phoneNumber: '+2250500000084',
        email: 'mgr@dir.pro',
        authProvider: 'google',
        googleSub: 'sub-mgr',
      );
      final mgrId = bare.provider!.id;
      final inv = await memberships.invite(
        providerId: 'p2',
        email: 'mgr@dir.pro',
        role: 'manager',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(inv.id, mgrId);
      expect(await directory.canAddSalon(mgrId), isFalse);
    });
  });

  group('addSalon (« Ajouter un salon »)', () {
    test('201 effects: draft + owner row + slug-unique + scalar '
        'untouched + fresh SETUP', () async {
      await makeReseau('p1');
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Chez Awa', // same name → the slug must dedupe
        businessType: 'barber',
      );
      expect(r.ok, isTrue);
      final entry = r.data! as Map;
      final newId = entry['salonId'] as String;
      expect(entry['role'], 'owner');
      expect(entry['salonStatus'], 'draft');

      final salon = (await providers.byId(newId))!;
      expect(salon['status'], 'draft');
      expect(salon['slug'], isNot((await providers.byId('p1'))!['slug']));
      // The owner membership row exists; the scalar link is untouched.
      expect(await memberships.activeMember(ownerId, newId), isNotNull);
      expect((await auth.accountById(ownerId))!.providerId, 'p1');
      // Fresh SETUP: no offer yet → publishing demands one.
      expect(await subscriptions.stateFor(newId), isNull);
      expect(await subscriptions.hasLiveOffer(newId), isFalse);
    });

    test('badge inheritance: a VERIFIED account stamps the new salon; a '
        'pending one does not', () async {
      await makeReseau('p1');
      await auth.setVerification(ownerId, status: 'verified');
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Salon Deux',
        businessType: 'spa',
      );
      final id = (r.data! as Map)['salonId'] as String;
      expect((await providers.byId(id))!['verified'], isTrue);

      await auth.setVerification(ownerId, status: 'pending');
      final r2 = await directory.addSalon(
        ownerId,
        businessName: 'Salon Trois',
        businessType: 'spa',
      );
      final id2 = (r2.data! as Map)['salonId'] as String;
      expect((await providers.byId(id2))!['verified'], isNot(isTrue));
    });

    test('no live Réseau anywhere → reseau_required (even with a live '
        'Pro offer)', () async {
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: ownerId,
        email: 'owner@dir.pro',
      );
      await subscriptions.chooseOffer(ownerId, 'p1', 'pro');
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Bloqué',
        businessType: 'salon',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'reseau_required');
    });

    test('the 20-salon cap → salon_limit', () async {
      await makeReseau('p1');
      // Owner rows up to the cap (p1 + 19 fakes = 20 owned).
      for (var i = 0; i < SalonDirectoryService.maxOwnedSalons - 1; i++) {
        await memberships.ensureOwner(
          providerId: 'cap$i',
          accountId: ownerId,
          email: 'owner@dir.pro',
        );
      }
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Un de trop',
        businessType: 'salon',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'salon_limit');
    });

    test('validation: empty name / unknown type → invalid_input', () async {
      await makeReseau('p1');
      expect(
        (await directory.addSalon(
          ownerId,
          businessName: '  ',
          businessType: 'salon',
        )).error,
        'invalid_input',
      );
      expect(
        (await directory.addSalon(
          ownerId,
          businessName: 'X',
          businessType: 'bank',
        )).error,
        'invalid_input',
      );
    });

    test('a fresh trial starts on salon 2 even when salon 1 chose long '
        'ago (per-salon clocks)', () async {
      await makeReseau('p1');
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Deux',
        businessType: 'salon',
      );
      final newId = ((r.data!) as Map)['salonId'] as String;
      final chosen = await subscriptions.chooseOffer(ownerId, newId, 'pro');
      expect(chosen.ok, isTrue, reason: '${chosen.error}');
      final state = (await subscriptions.stateFor(newId))!;
      expect(state['status'], 'trial');
      expect(state['tier'], 'pro');
    });
  });

  group('GET/POST /me/salons (the route)', () {
    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<SalonDirectoryService>()).thenReturn(directory);
      return c;
    }

    Request req(String method, {String? token, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/me/salons'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    );

    String tok(String sub, {String role = 'provider'}) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    test('401 anonymous · 403 consumer · 405 bad verb', () async {
      expect(
        (await me_salons.onRequest(ctx(req('GET')))).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await me_salons.onRequest(
          ctx(req('GET', token: tok('u1', role: 'user'))),
        )).statusCode,
        HttpStatus.forbidden,
      );
      expect(
        (await me_salons.onRequest(
          ctx(req('PUT', token: tok(ownerId))),
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
    });

    test('GET → items + the computed gate', () async {
      await makeReseau('p1');
      final res = await me_salons.onRequest(
        ctx(req('GET', token: tok(ownerId))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect((m['items'] as List), hasLength(1));
      expect(m['canAddSalon'], isTrue);
    });

    test('POST happy path → 201 {salon}; gates map to their codes', () async {
      // Gate first: no Réseau yet.
      final blocked = await me_salons.onRequest(
        ctx(
          req(
            'POST',
            token: tok(ownerId),
            body: {'businessName': 'Deux', 'businessType': 'salon'},
          ),
        ),
      );
      expect(blocked.statusCode, HttpStatus.forbidden);
      expect((await blocked.json() as Map)['error'], 'reseau_required');

      await makeReseau('p1');
      final res = await me_salons.onRequest(
        ctx(
          req(
            'POST',
            token: tok(ownerId),
            body: {'businessName': 'Deux', 'businessType': 'salon'},
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.created);
      final salon = (await res.json() as Map)['salon'] as Map;
      expect(salon['salonName'], 'Deux');
      expect(salon['salonStatus'], 'draft');

      final bad = await me_salons.onRequest(
        ctx(req('POST', token: tok(ownerId), body: {'businessName': ''})),
      );
      expect(bad.statusCode, HttpStatus.badRequest);
    });
  });

  group('seats independence (per-salon caps)', () {
    test('an invite into salon 2 never consumes salon 1 seats', () async {
      await makeReseau('p1');
      final r = await directory.addSalon(
        ownerId,
        businessName: 'Deux',
        businessType: 'salon',
      );
      final p2Id = ((r.data!) as Map)['salonId'] as String;
      await subscriptions.chooseOffer(ownerId, p2Id, 'pro');

      final before = (await subscriptions.stateFor('p1'))!;
      final beforeUsed = (before['seats'] as Map)['used'] as int;

      // Seed a member row in salon 2 only.
      await memberships.invite(
        providerId: p2Id,
        email: 'x@dir.pro',
        role: 'reception',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      final after = (await subscriptions.stateFor('p1'))!;
      expect((after['seats'] as Map)['used'], beforeUsed);
      final p2State = (await subscriptions.stateFor(p2Id))!;
      expect((p2State['seats'] as Map)['used'], greaterThanOrEqualTo(2));
    });
  });
}
