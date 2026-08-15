import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

import '../routes/me/index.dart' as me_route;

/// **Three surfaces that accepted an upload and then let it be deleted.**
///
/// Before/after pairs, artist photos and consumer avatars all went through the
/// presign pipeline — which writes under `pending/` — and none of them ever
/// claimed the object. Production expires that prefix daily, so each image
/// worked for a day and then 404'd forever, with its url still in Postgres.
/// The gallery had the mirror-image bug: it promoted on EVERY save, so the
/// second save re-sent already-promoted urls and was refused.
///
/// Every group below therefore saves **twice**. A first-save-only test passes
/// against both bugs and is the reason neither was caught.
///
/// Design: docs/design/backend-upload-size-verification.md (T61),
/// docs/design/backend-upload-orphans.md §2.
void main() {
  const base = 'https://cdn.myweli.com';
  String url(String key) => '$base/$key';

  group('before/after pairs', () {
    late InMemoryProvidersRepository providers;
    late InMemoryProviderAuthRepository providerAuth;
    late _PublicStorage store;
    late ProviderCatalogService catalog;
    late String accountId;
    final tokens = TokenService(secret: 'test-secret');

    setUp(() async {
      providers = InMemoryProvidersRepository(_freshSeed());
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      store = _PublicStorage();
      catalog = ProviderCatalogService(
        providers,
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        allowedImageOrigins: const [base],
        verifier: UploadVerificationService(storage: store),
        publicBaseUrl: base,
      );
      final reg = await providerAuth.register(
        email: 'ba@test.pro',
        authProvider: 'google',
        googleSub: 'ba-sub',
        phoneNumber: '+2250500000021',
        businessName: 'X',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    Future<CatalogResult> save(List<Map<String, dynamic>> pairs) => catalog
        .updateBeforeAfters(accountId, 'provider1', {'beforeAfters': pairs});

    test('the pair is promoted out of pending/ on the first save', () async {
      final r = await save([
        {
          'before': url('pending/ba/p1/b1.jpg'),
          'after': url('pending/ba/p1/a1.jpg'),
          'caption': 'Braids',
        },
      ]);
      expect(r.ok, isTrue);
      final saved = (r.data! as Map)['beforeAfters'] as List;
      expect((saved.first as Map)['before'], url('ba/p1/b1.jpg'));
      expect((saved.first as Map)['after'], url('ba/p1/a1.jpg'));
      expect((saved.first as Map)['caption'], 'Braids');
      expect(store.copied, [
        'pending/ba/p1/b1.jpg -> ba/p1/b1.jpg',
        'pending/ba/p1/a1.jpg -> ba/p1/a1.jpg',
      ]);
      expect(
        store.deleted,
        ['pending/ba/p1/b1.jpg', 'pending/ba/p1/a1.jpg'],
        reason: 'the object must LEAVE pending/, or the expiry still gets it',
      );
    });

    test(
      'a second save keeps the old pair and promotes only the new',
      () async {
        await save([
          {
            'before': url('pending/ba/p1/b1.jpg'),
            'after': url('pending/ba/p1/a1.jpg'),
          },
        ]);
        store.copied.clear();

        // Exactly what the pro app sends: the pair it was just handed back,
        // plus one it has only now uploaded.
        final r = await save([
          {'before': url('ba/p1/b1.jpg'), 'after': url('ba/p1/a1.jpg')},
          {
            'before': url('pending/ba/p1/b2.jpg'),
            'after': url('pending/ba/p1/a2.jpg'),
          },
        ]);
        expect(r.ok, isTrue, reason: 'error was ${r.error}');
        final saved = (r.data! as Map)['beforeAfters'] as List;
        expect((saved[0] as Map)['before'], url('ba/p1/b1.jpg'));
        expect((saved[1] as Map)['after'], url('ba/p1/a2.jpg'));
        expect(store.copied, [
          'pending/ba/p1/b2.jpg -> ba/p1/b2.jpg',
          'pending/ba/p1/a2.jpg -> ba/p1/a2.jpg',
        ]);
      },
    );

    test('before and after do not get swapped', () async {
      // The pairs are rebuilt positionally out of one flattened list
      // (`urls[i * 2]` / `urls[i * 2 + 1]`). Mixing a stored url with a pending
      // one inside a single pair is the case where a partition bug shows.
      final first = await save([
        {
          'before': url('pending/ba/p1/before.jpg'),
          'after': url('pending/ba/p1/after.jpg'),
        },
      ]);
      expect(first.ok, isTrue);
      final r = await save([
        {
          'before': url('ba/p1/before.jpg'), // unchanged
          'after': url('pending/ba/p1/after-v2.jpg'), // replaced
        },
      ]);
      final pair = ((r.data! as Map)['beforeAfters'] as List).first as Map;
      expect(pair['before'], url('ba/p1/before.jpg'));
      expect(pair['after'], url('ba/p1/after-v2.jpg'));
    });

    test('a url we never issued is refused', () async {
      // Not pending, and not one of this salon's stored urls — so it is either
      // another tenant's object or a string the client made up.
      final r = await save([
        {'before': url('ba/other-salon/b.jpg'), 'after': url('ba/p1/x.jpg')},
      ]);
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
      expect(store.copied, isEmpty);
    });

    test('clearing the showcase still works', () async {
      await save([
        {
          'before': url('pending/ba/p1/b1.jpg'),
          'after': url('pending/ba/p1/a1.jpg'),
        },
      ]);
      final r = await save([]);
      expect(r.ok, isTrue);
      expect((r.data! as Map)['beforeAfters'], isEmpty);
    });
  });

  group('artist photos', () {
    late InMemoryProvidersRepository providers;
    late InMemoryProviderAuthRepository providerAuth;
    late _PublicStorage store;
    late ProviderCatalogService catalog;
    late String accountId;
    final tokens = TokenService(secret: 'test-secret');

    setUp(() async {
      providers = InMemoryProvidersRepository(_freshSeed());
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      store = _PublicStorage();
      catalog = ProviderCatalogService(
        providers,
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        allowedImageOrigins: const [base],
        verifier: UploadVerificationService(storage: store),
        publicBaseUrl: base,
      );
      final reg = await providerAuth.register(
        email: 'art@test.pro',
        authProvider: 'google',
        googleSub: 'art-sub',
        phoneNumber: '+2250500000022',
        businessName: 'X',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    Future<Map<String, dynamic>> create(String name, {String? imageUrl}) async {
      final r = await catalog.createArtist(accountId, 'provider1', {
        'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
      });
      expect(r.ok, isTrue, reason: 'create failed: ${r.error}');
      return r.data! as Map<String, dynamic>;
    }

    String idOf(Map<String, dynamic> artist) => artist['id']! as String;

    test('the photo is promoted on create', () async {
      final a = await create('Awa', imageUrl: url('pending/staff/p1/awa.jpg'));
      expect(a['imageUrl'], url('staff/p1/awa.jpg'));
      expect(store.copied, ['pending/staff/p1/awa.jpg -> staff/p1/awa.jpg']);
    });

    test('an edit that leaves the photo alone still works', () async {
      // The second-save case for this surface: the pro app PATCHes the whole
      // artist, so the url it re-sends is the promoted one it was given.
      final a = await create('Awa', imageUrl: url('pending/staff/p1/awa.jpg'));
      store.copied.clear();
      final r = await catalog.updateArtist(accountId, 'provider1', idOf(a), {
        'name': 'Awa K.',
        'imageUrl': url('staff/p1/awa.jpg'),
      });
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      final updated = r.data! as Map;
      expect(updated['name'], 'Awa K.');
      expect(updated['imageUrl'], url('staff/p1/awa.jpg'));
      expect(store.copied, isEmpty, reason: 'nothing new was uploaded');
    });

    test('replacing the photo promotes the new one', () async {
      final a = await create('Awa', imageUrl: url('pending/staff/p1/awa.jpg'));
      final r = await catalog.updateArtist(accountId, 'provider1', idOf(a), {
        'imageUrl': url('pending/staff/p1/awa-v2.jpg'),
      });
      expect((r.data! as Map)['imageUrl'], url('staff/p1/awa-v2.jpg'));
    });

    test(
      "one artist cannot be pointed at another artist's stored photo",
      () async {
        // `alreadyStored` is scoped to the artist being edited, not to the
        // salon. Widening it to "any url we hold" would make this pass — and
        // would be the same trust-the-shape mistake this fix removes.
        final awa = await create(
          'Awa',
          imageUrl: url('pending/staff/p1/awa.jpg'),
        );
        final ama = await create(
          'Ama',
          imageUrl: url('pending/staff/p1/ama.jpg'),
        );
        final r = await catalog.updateArtist(
          accountId,
          'provider1',
          idOf(ama),
          {'imageUrl': url('staff/p1/awa.jpg')},
        );
        expect(r.ok, isFalse);
        expect(r.error, 'invalid_input');
        // Read back rather than trusting the create response: Awa still owns it.
        final listed =
            (await catalog.listArtists(accountId, 'provider1')).data! as List;
        final stored = listed.whereType<Map<String, dynamic>>().firstWhere(
          (x) => x['id'] == idOf(awa),
        );
        expect(stored['imageUrl'], url('staff/p1/awa.jpg'));
      },
    );

    test('a foreign origin is refused — there was NO check here at all', () {
      // `imageUrl` used to be `(body['imageUrl'] as String?)?.trim()`, so any
      // string became an artist photo and was served back from our own domain.
      return catalog
          .createArtist(accountId, 'provider1', {
            'name': 'Mallory',
            'imageUrl': 'https://evil.example/x.jpg',
          })
          .then((r) {
            expect(r.ok, isFalse);
            expect(r.error, 'invalid_input');
          });
    });

    test('an artist with no photo is unaffected', () async {
      final a = await create('Sans photo');
      expect(a['imageUrl'], isNull);
      final r = await catalog.updateArtist(accountId, 'provider1', idOf(a), {
        'specialization': 'Coloriste',
      });
      expect(r.ok, isTrue);
      expect(store.copied, isEmpty);
    });
  });

  group('the salon gallery was WRITE-ONCE', () {
    late InMemoryProvidersRepository providers;
    late InMemoryProviderAuthRepository providerAuth;
    late _PublicStorage store;
    late ProviderCatalogService catalog;
    late String accountId;
    final tokens = TokenService(secret: 'test-secret');

    setUp(() async {
      providers = InMemoryProvidersRepository(_freshSeed());
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      store = _PublicStorage();
      catalog = ProviderCatalogService(
        providers,
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        allowedImageOrigins: const [base, 'asset:'],
        verifier: UploadVerificationService(storage: store),
        publicBaseUrl: base,
      );
      final reg = await providerAuth.register(
        email: 'gal@test.pro',
        authProvider: 'google',
        googleSub: 'gal-sub',
        phoneNumber: '+2250500000023',
        businessName: 'X',
        businessType: 'salon',
        providerId: 'provider1',
      );
      accountId = reg.provider!.id;
    });

    Future<CatalogResult> save(List<String> urls) =>
        catalog.updateGallery(accountId, 'provider1', {'imageUrls': urls});

    Future<List<String>> stored() async =>
        ((await providers.byId('provider1'))!['imageUrls'] as List)
            .cast<String>();

    /// The first save, which was the only one that ever worked.
    Future<void> seedOne() async {
      final r = await save([url('pending/gallery/provider1/a.jpg')]);
      expect(r.ok, isTrue, reason: 'first save: ${r.error}');
      expect(await stored(), [url('gallery/provider1/a.jpg')]);
      store.copied.clear();
      store.deleted.clear();
    }

    test('a SECOND save adds a photo instead of 400ing', () async {
      await seedOne();
      final r = await save([
        url('gallery/provider1/a.jpg'), // what the server just handed back
        url('pending/gallery/provider1/b.jpg'), // and one just uploaded
      ]);
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(await stored(), [
        url('gallery/provider1/a.jpg'),
        url('gallery/provider1/b.jpg'),
      ]);
      expect(store.copied, [
        'pending/gallery/provider1/b.jpg -> gallery/provider1/b.jpg',
      ]);
    });

    test('DELETING a photo works — it PUTs the whole list too', () async {
      // The case an "adding a second photo" framing misses. Both clients send
      // the full remaining list on remove, so delete was refused as well.
      await seedOne();
      final two = await save([
        url('gallery/provider1/a.jpg'),
        url('pending/gallery/provider1/b.jpg'),
      ]);
      expect(two.ok, isTrue);
      final r = await save([url('gallery/provider1/b.jpg')]);
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(await stored(), [url('gallery/provider1/b.jpg')]);
    });

    test('REORDERING works, and the new cover is what is stored', () async {
      // `photos[0]` is the listing cover, so order is not cosmetic here.
      await seedOne();
      await save([
        url('gallery/provider1/a.jpg'),
        url('pending/gallery/provider1/b.jpg'),
      ]);
      store.copied.clear();
      final r = await save([
        url('gallery/provider1/b.jpg'),
        url('gallery/provider1/a.jpg'),
      ]);
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(await stored(), [
        url('gallery/provider1/b.jpg'),
        url('gallery/provider1/a.jpg'),
      ]);
      expect(store.copied, isEmpty, reason: 'nothing new was uploaded');
    });

    test("another salon's stored url is refused", () async {
      await seedOne();
      expect(
        (await save([url('gallery/provider2/theirs.jpg')])).error,
        'invalid_input',
      );
      expect(store.copied, isEmpty);
    });

    test('an INVENTED asset: url no longer disables the controls', () async {
      // The all-or-nothing bypass. `asset:` passes the origin allowlist but
      // does not derive to a key, and the old `keys.length == urls.length`
      // guard then skipped verification AND promotion for the WHOLE request —
      // so every other photo in it was stored unverified and still pending:
      // 200 now, gone tomorrow, with no T61 cap on any of it.
      final before = await stored();
      final r = await save([
        'asset:assets/images/invented.png',
        url('pending/gallery/provider1/c.jpg'),
      ]);
      expect(r.ok, isFalse, reason: 'it must not 200 with nothing promoted');
      expect(r.error, 'invalid_input');
      expect(await stored(), before, reason: 'and nothing may be written');
      expect(store.copied, isEmpty);
    });

    test(
      'a SEEDED asset: url still passes through — the deliberate half',
      () async {
        // The other side of that decision, pinned so it is not lost to a later
        // "tidy-up". `asset:` stays in the origin allowlist: `promoteNewUrls`
        // already refuses a NEW one, so removing it would change nothing for new
        // data and would only break a placeholder that is already stored.
        // Membership is what lets this one through.
        final seeded = (await stored()).firstWhere(
          (u) => u.startsWith('asset:'),
        );
        final r = await save([seeded, url('pending/gallery/provider1/d.jpg')]);
        expect(r.ok, isTrue, reason: 'error was ${r.error}');
        expect(await stored(), [seeded, url('gallery/provider1/d.jpg')]);
      },
    );

    test('clearing the gallery still works', () async {
      await seedOne();
      final r = await save([]);
      expect(r.ok, isTrue);
      expect(await stored(), isEmpty);
    });
  });

  group('KYC could not be PARTIALLY resubmitted', () {
    late InMemoryProviderAuthRepository providerAuth;
    late FakeStorageService store;
    late KycService kyc;
    late String accountId;
    final tokens = TokenService(secret: 'test-secret');

    String pending(String name) => 'pending/kyc/$accountId/$name';
    String promoted(String name) => 'kyc/$accountId/$name';

    setUp(() async {
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      store = FakeStorageService(defaultSize: 10);
      // WITH a verifier. `kyc_test.dart` constructs `KycService(providerAuth)`
      // without one, which is why its "resubmit clears a prior rejection" test
      // passed against a service that could not promote — and why this bug
      // shipped green.
      kyc = KycService(
        providerAuth,
        verifier: UploadVerificationService(storage: store),
      );
      final reg = await providerAuth.register(
        email: 'kyc@test.pro',
        authProvider: 'google',
        googleSub: 'kyc-sub',
        phoneNumber: '+2250500000024',
        businessName: 'X',
        businessType: 'salon',
      );
      accountId = reg.provider!.id;
    });

    Future<KycResult> submit(List<Map<String, String>> docs) =>
        kyc.submit(accountId, docs);

    Future<void> reject() async {
      (await providerAuth.accountById(accountId))!
        ..verificationStatus = 'rejected'
        ..rejectionReason = 'Blurry ID';
    }

    Future<void> seed() async {
      final r = await submit([
        {'type': 'idCard', 'key': pending('id.jpg')},
        {'type': 'selfie', 'key': pending('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: 'first submit: ${r.error}');
      final docs = r.data!['documents']! as List;
      expect((docs.first as Map)['key'], promoted('id.jpg'));
      store.copied.clear();
    }

    test('replacing ONLY the flagged document now works', () async {
      // The action the rejection banner literally invites: « Veuillez renvoyer
      // vos documents. » It re-sent one promoted key beside one new pending
      // one, and the whole submission 400'd.
      await seed();
      await reject();
      final r = await submit([
        {'type': 'idCard', 'key': pending('id-v2.jpg')},
        {'type': 'selfie', 'key': promoted('selfie.jpg')}, // untouched
      ]);
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(r.data!['status'], 'pending');
      expect(r.data!['rejectionReason'], isNull);
      final docs = r.data!['documents']! as List;
      expect((docs[0] as Map)['key'], promoted('id-v2.jpg'));
      expect((docs[1] as Map)['key'], promoted('selfie.jpg'));
      expect(store.copied, [
        '${pending('id-v2.jpg')} -> ${promoted('id-v2.jpg')}',
      ]);
    });

    test(
      'a bare resubmit with nothing changed works and copies nothing',
      () async {
        await seed();
        await reject();
        final r = await submit([
          {'type': 'idCard', 'key': promoted('id.jpg')},
          {'type': 'selfie', 'key': promoted('selfie.jpg')},
        ]);
        expect(r.ok, isTrue, reason: 'error was ${r.error}');
        expect(r.data!['status'], 'pending');
        expect(store.copied, isEmpty);
      },
    );

    test('a promoted key belonging to ANOTHER account is refused', () async {
      // The shape-vs-membership assertion. `kyc/{someone}/a.jpg` looks exactly
      // as promoted as our own; only the stored set separates them.
      await seed();
      expect(
        (await submit([
          {'type': 'idCard', 'key': 'kyc/someone_else/a.jpg'},
        ])).error,
        'invalid_input',
      );
      expect(
        (await submit([
          {'type': 'idCard', 'key': 'pending/kyc/someone_else/a.jpg'},
        ])).error,
        'invalid_input',
      );
    });

    test(
      'a promoted key this account once had, and no longer has, is refused',
      () async {
        await seed();
        // Replace both, so `id.jpg` leaves the stored set entirely.
        final replaced = await submit([
          {'type': 'idCard', 'key': pending('id-v2.jpg')},
          {'type': 'selfie', 'key': pending('selfie-v2.jpg')},
        ]);
        expect(replaced.ok, isTrue);
        expect(
          (await submit([
            {'type': 'idCard', 'key': promoted('id.jpg')},
          ])).error,
          'invalid_input',
          reason: 'membership is CURRENT membership, not "ever ours"',
        );
      },
    );

    test('an unbounded document list is refused', () async {
      expect(
        (await submit([
          for (var i = 0; i < 9; i++)
            {'type': 'idCard', 'key': pending('d$i.jpg')},
        ])).error,
        'invalid_input',
      );
      expect(store.copied, isEmpty);
    });
  });

  group('PATCH /me avatar', () {
    late InMemoryAuthRepository auth;
    late _PublicStorage store;
    late UploadVerificationService verifier;
    late String userId;
    late String token;
    final tokens = TokenService(secret: 'test-secret');

    setUp(() async {
      auth = InMemoryAuthRepository(tokens: tokens, isProd: false);
      store = _PublicStorage();
      verifier = UploadVerificationService(storage: store);
      const phone = '+2250700000055';
      final otp = await auth.requestOtp(phone);
      final login = await auth.verifyOtp(phone, otp.devCode!);
      userId = login.user!.id;
      token = tokens.issueAccessToken(subject: userId, role: 'user').token;
    });

    Future<Response> patch(Map<String, dynamic> body) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          'PATCH',
          Uri.parse('http://localhost/me'),
          headers: {'Authorization': 'Bearer $token'},
          body: jsonEncode(body),
        ),
      );
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<AuthRepository>()).thenReturn(auth);
      when(() => c.read<UploadVerificationService>()).thenReturn(verifier);
      return me_route.onRequest(c);
    }

    Future<Map<String, dynamic>> json(Response r) async =>
        jsonDecode(await r.body()) as Map<String, dynamic>;

    test(
      'a new avatar is promoted, and the response carries the promoted url',
      () async {
        final res = await patch({'avatarUrl': url('pending/avatars/u1/a.jpg')});
        expect(res.statusCode, HttpStatus.ok);
        expect((await json(res))['avatarUrl'], url('avatars/u1/a.jpg'));
        expect(store.copied, ['pending/avatars/u1/a.jpg -> avatars/u1/a.jpg']);
        expect(store.deleted, ['pending/avatars/u1/a.jpg']);
        // And it is what was actually stored, not just what was echoed back.
        expect(
          (await auth.userById(userId))!.avatarUrl,
          url('avatars/u1/a.jpg'),
        );
      },
    );

    test('editing the NAME re-sends the avatar and must not 400', () async {
      // The app PATCHes the whole profile. Promoting unconditionally would
      // reject every subsequent edit; rejecting non-pending urls outright
      // would do the same.
      await patch({'avatarUrl': url('pending/avatars/u1/a.jpg')});
      store.copied.clear();
      final res = await patch({
        'name': 'Awa K.',
        'avatarUrl': url('avatars/u1/a.jpg'),
      });
      expect(res.statusCode, HttpStatus.ok);
      final body = await json(res);
      expect(body['name'], 'Awa K.');
      expect(body['avatarUrl'], url('avatars/u1/a.jpg'));
      expect(store.copied, isEmpty);
    });

    test('replacing the avatar promotes the new one', () async {
      await patch({'avatarUrl': url('pending/avatars/u1/a.jpg')});
      final res = await patch({'avatarUrl': url('pending/avatars/u1/b.jpg')});
      expect((await json(res))['avatarUrl'], url('avatars/u1/b.jpg'));
    });

    test(
      'an arbitrary url is refused — it used to be stored verbatim',
      () async {
        // The avatar was written straight through with no origin check, so any
        // string was served back from our own domain as this user's photo.
        for (final bad in [
          'https://evil.example/x.jpg',
          'javascript:alert(1)',
          url('kyc/someone-else/passport.jpg'), // ours, but not theirs
        ]) {
          final res = await patch({'avatarUrl': bad});
          expect(
            res.statusCode,
            HttpStatus.badRequest,
            reason: '$bad must not become an avatar',
          );
          expect((await json(res))['error'], 'invalid_input');
        }
        expect((await auth.userById(userId))!.avatarUrl, isNull);
      },
    );

    test(
      'a PATCH that does not touch the avatar leaves storage alone',
      () async {
        final res = await patch({'name': 'Awa'});
        expect(res.statusCode, HttpStatus.ok);
        expect(store.copied, isEmpty);
        expect(store.deleted, isEmpty);
      },
    );
  });
}

class _MockRequestContext extends Mock implements RequestContext {}

/// A private deep copy of the provider seed.
///
/// `InMemoryProvidersRepository()` defaults to the **shared top-level**
/// `seedProviders` list and mutates its maps IN PLACE, so two repositories
/// built in the same test file are effectively the same repository — a save in
/// one test is visible in the next. That was harmless while nothing read prior
/// state; `alreadyStored` reads exactly that, so these tests must not share it.
List<Map<String, dynamic>> _freshSeed() =>
    (jsonDecode(jsonEncode(seedProviders)) as List)
        .cast<Map<String, dynamic>>();

/// A fake with a real delivery origin.
///
/// [FakeStorageService] reports a null [publicBaseUrl] on purpose — that is
/// what dev means, and it is the switch every promotion path uses to no-op.
/// These tests need the opposite: a configured origin, so the promotion
/// actually runs.
class _PublicStorage extends FakeStorageService {
  _PublicStorage() : super(defaultSize: 10);

  @override
  String? get publicBaseUrl => 'https://cdn.myweli.com';
}
