import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/appointments/[id]/deposit-screenshot.dart' as view_route;
import '../routes/appointments/[id]/deposit.dart' as deposit_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockNotifier extends Mock implements BookingNotifier {}

class _MockSalonNotifier extends Mock implements SalonNotifier {}

void main() {
  setUpAll(() {
    registerFallbackValue(MessageTemplate.bookingConfirmed);
    registerFallbackValue(SalonEvent.newBooking);
  });
  late InMemoryAppointmentRepository appts;
  late InMemoryProviderAuthRepository providerAuth;
  late DepositService service;
  final tokens = TokenService(secret: 'test-secret');
  final accessA = tokens
      .issueAccessToken(subject: 'user_A', role: 'user')
      .token;
  final accessB = tokens
      .issueAccessToken(subject: 'user_B', role: 'user')
      .token;
  late String salonToken; // provider managing provider1
  late String salonAccountId; // provider1's account id
  late String otherSalonToken; // provider managing provider2

  DepositService svcWith(FakeStorageService store) => DepositService(
    appts,
    MembershipService(InMemoryMembershipRepository(), providerAuth),
    store,
  );

  Future<void> seed(
    String id, {
    String userId = 'user_A',
    String status = 'pending',
    String? screenshot,
  }) => appts.create({
    'id': id,
    'userId': userId,
    'providerId': 'provider1',
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
    'durationMinutes': 60,
    'status': status,
    'totalPrice': 15000,
    'depositAmount': 4500,
    'balanceDue': 10500,
    'depositScreenshotUrl': screenshot,
    'createdAt': DateTime.utc(2030).toIso8601String(),
  });

  setUp(() async {
    appts = InMemoryAppointmentRepository();
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      isProd: false,
    );
    service = DepositService(
      appts,
      MembershipService(InMemoryMembershipRepository(), providerAuth),
      FakeStorageService(),
    );
    final p1 = await providerAuth.register(
      email: 'reg8@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-8',
      phoneNumber: '+2250500000080',
      businessName: 'S1',
      businessType: 'salon',
      providerId: 'provider1',
    );
    final p2 = await providerAuth.register(
      email: 'reg9@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-9',
      phoneNumber: '+2250500000081',
      businessName: 'S2',
      businessType: 'salon',
      providerId: 'provider2',
    );
    salonAccountId = p1.provider!.id;
    salonToken = tokens
        .issueAccessToken(subject: salonAccountId, role: 'provider')
        .token;
    otherSalonToken = tokens
        .issueAccessToken(subject: p2.provider!.id, role: 'provider')
        .token;
  });

  group('DepositService.submit', () {
    test('owner attaches a screenshot key under their own prefix', () async {
      await seed('a1');
      final r = await service.submit(
        'user_A',
        'a1',
        'pending/deposit/user_A/x.jpg',
      );
      expect(r.ok, isTrue);
      expect((r.data! as Map)['depositScreenshotUrl'], 'deposit/user_A/x.jpg');
    });

    test('rejects foreign key / non-owner / non-pending / unknown', () async {
      await seed('a1');
      expect(
        (await service.submit(
          'user_A',
          'a1',
          'pending/deposit/user_B/x.jpg',
        )).error,
        'invalid_input', // not under the caller's prefix
      );
      expect(
        (await service.submit(
          'user_B',
          'a1',
          'pending/deposit/user_B/x.jpg',
        )).error,
        'forbidden', // not the owner
      );
      await seed('done', status: 'completed');
      expect(
        (await service.submit(
          'user_A',
          'done',
          'pending/deposit/user_A/x.jpg',
        )).error,
        'invalid_state',
      );
      expect(
        (await service.submit(
          'user_A',
          'nope',
          'pending/deposit/user_A/x.jpg',
        )).error,
        'not_found',
      );
    });
  });

  group('DepositService.screenshotUrl', () {
    test('owner consumer + owning salon can view; a stranger cannot', () async {
      await seed('a1', screenshot: 'deposit/user_A/x.jpg');
      expect(
        (await service.screenshotUrl('a1', sub: 'user_A', role: 'user')).ok,
        isTrue,
      );
      // The salon that owns provider1.
      expect(
        (await service.screenshotUrl(
          'a1',
          sub: salonAccountId,
          role: 'provider',
        )).ok,
        isTrue,
      );
      // Another consumer → forbidden.
      expect(
        (await service.screenshotUrl('a1', sub: 'user_B', role: 'user')).error,
        'forbidden',
      );
    });

    test('404 when there is no screenshot', () async {
      await seed('a1'); // no screenshot
      expect(
        (await service.screenshotUrl('a1', sub: 'user_A', role: 'user')).error,
        'not_found',
      );
    });
  });

  group('routes', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<DepositService>()).thenReturn(service);
      final notifier = _MockNotifier();
      // The salon team also hears about an attached justificatif (design §10).
      final salonNotifier = _MockSalonNotifier();
      when(() => salonNotifier.notify(any(), any())).thenAnswer((_) async {});
      when(() => context.read<SalonNotifier>()).thenReturn(salonNotifier);
      when(() => notifier.notify(any(), any())).thenAnswer((_) async {});
      when(() => context.read<BookingNotifier>()).thenReturn(notifier);
      return context;
    }

    Request req(String method, {String? bearer, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/appointments/a1/deposit'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null
          ? null
          : '{"screenshotKey":"pending/deposit/user_A/x.jpg"}',
    );

    test(
      'POST deposit: 200 owner; 403 other; 401 none; provider → 403; 405',
      () async {
        await seed('a1');
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: accessA, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: accessB, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.forbidden, // not the owner
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', body: {})),
            'a1',
          )).statusCode,
          HttpStatus.unauthorized,
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('POST', bearer: salonToken, body: {})),
            'a1',
          )).statusCode,
          HttpStatus.forbidden, // provider can't submit a deposit
        );
        expect(
          (await deposit_route.onRequest(
            ctx(req('GET', bearer: accessA)),
            'a1',
          )).statusCode,
          HttpStatus.methodNotAllowed,
        );
      },
    );

    test(
      'GET deposit-screenshot: consumer + salon 200; other salon 403; 404',
      () async {
        await seed('a1', screenshot: 'deposit/user_A/x.jpg');
        Request get(String? bearer) => Request.get(
          Uri.parse('http://localhost/appointments/a1/deposit-screenshot'),
          headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
        );
        expect(
          (await view_route.onRequest(ctx(get(accessA)), 'a1')).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await view_route.onRequest(ctx(get(salonToken)), 'a1')).statusCode,
          HttpStatus.ok,
        );
        expect(
          (await view_route.onRequest(
            ctx(get(otherSalonToken)),
            'a1',
          )).statusCode,
          HttpStatus.forbidden,
        );
      },
    );
  });

  group('claim-time size verification (T61)', () {
    // R2 accepts a body larger than the signed content-length — measured
    // against the live bucket — so ownership passing is NOT enough. This is
    // the only layer that bounds what a consumer can put in the deposit
    // bucket at our expense.
    test('an oversized screenshot is refused AND deleted', () async {
      final store = FakeStorageService(
        sizes: {'pending/deposit/user1/huge.jpg': 50 * 1024 * 1024},
      );
      final svc = DepositService(
        appts,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        store,
      );
      await seed('a-big', userId: 'user1');
      final r = await svc.submit(
        'user1',
        'a-big',
        'pending/deposit/user1/huge.jpg',
      );

      expect(r.ok, isFalse);
      expect(r.error, 'upload_too_large');
      expect(
        store.deleted,
        ['pending/deposit/user1/huge.jpg'],
        reason: 'refusing the claim must not leave the bytes we pay for',
      );
      // And the booking must be untouched — a rejected claim is not a
      // half-applied one.
      final after = await appts.byId('a-big');
      expect(
        after!['depositScreenshotUrl'],
        isNull,
        reason:
            'was `isNot(the pending key)`, which passed for any OTHER wrong '
            'value too — a refused claim must write nothing at all',
      );
    });

    test('a REPLACE deletes the object it supersedes', () async {
      // The superseded object sits at its PROMOTED path, outside `pending/`,
      // so no lifecycle rule collects it — and `anonymizeUser` hands erasure
      // only the key each row CURRENTLY holds, so an abandoned proof outlived
      // `DELETE /me` with nothing pointing at it. That, not the storage bill,
      // is why this matters.
      final store = _RealisticStorage();
      final svc = svcWith(store);
      await seed('a-rep', userId: 'user1', screenshot: 'deposit/user1/old.jpg');
      final r = await svc.submit(
        'user1',
        'a-rep',
        'pending/deposit/user1/new.jpg',
      );
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      expect(
        (await appts.byId('a-rep'))!['depositScreenshotUrl'],
        'deposit/user1/new.jpg',
      );
      // containsAll, not an exact list: promotion deletes the pending source
      // too, and that is a different delete.
      expect(
        store.deleted,
        containsAll(<String>[
          'pending/deposit/user1/new.jpg',
          'deposit/user1/old.jpg',
        ]),
      );
    });

    test('a REFUSED replace leaves the old screenshot alone', () async {
      // The delete must hang off a successful update, not off reaching the
      // function. Wired one line higher, an oversized replacement would take
      // the proof the booking still depends on.
      final store = _RealisticStorage(
        sizes: {'pending/deposit/user1/big.jpg': 50 * 1024 * 1024},
      );
      final svc = svcWith(store);
      await seed('a-ref', userId: 'user1', screenshot: 'deposit/user1/old.jpg');
      final r = await svc.submit(
        'user1',
        'a-ref',
        'pending/deposit/user1/big.jpg',
      );
      expect(r.error, 'upload_too_large');
      expect(
        store.deleted,
        ['pending/deposit/user1/big.jpg'],
        reason: 'exactly the offending upload — never the live proof',
      );
      expect(
        (await appts.byId('a-ref'))!['depositScreenshotUrl'],
        'deposit/user1/old.jpg',
      );
    });

    test(
      "a prior key outside the caller's own prefix is NOT deleted",
      () async {
        // The column is bare text and the booking-time writer's verifier is
        // nullable, so "always promoted, always ours" is a property of the
        // writers rather than the schema. A value that fails the guard is
        // skipped — never deleted, never an error.
        final store = _RealisticStorage();
        final svc = svcWith(store);
        await seed(
          'a-for',
          userId: 'user1',
          screenshot: 'deposit/user_OTHER/theirs.jpg',
        );
        final r = await svc.submit(
          'user1',
          'a-for',
          'pending/deposit/user1/mine.jpg',
        );
        expect(r.ok, isTrue, reason: 'error was ${r.error}');
        expect(
          store.deleted,
          isNot(contains('deposit/user_OTHER/theirs.jpg')),
          reason: 'erasure takes the same posture — skip what is not ours',
        );
      },
    );

    test('re-sending the same key is idempotent, not a 400', () async {
      // A dropped response was unrecoverable: claiming deletes the pending
      // source, so the retry HEADed an object we deleted ourselves. The app
      // keeps the key across a failure, so this IS its retry path.
      final store = _RealisticStorage();
      final svc = svcWith(store);
      await seed('a-rep2', userId: 'user1');
      final first = await svc.submit(
        'user1',
        'a-rep2',
        'pending/deposit/user1/x.jpg',
      );
      expect(first.ok, isTrue);
      expect(first.replayed, isFalse);

      final second = await svc.submit(
        'user1',
        'a-rep2',
        'pending/deposit/user1/x.jpg',
      );
      expect(second.ok, isTrue, reason: 'error was ${second.error}');
      expect(second.replayed, isTrue);
      expect(
        (second.data! as Map)['depositScreenshotUrl'],
        'deposit/user1/x.jpg',
      );
      // And the booking still holds exactly one key.
      expect(
        (await appts.byId('a-rep2'))!['depositScreenshotUrl'],
        'deposit/user1/x.jpg',
      );
    });

    test('a replay does NOT delete the live screenshot', () async {
      // The cross-defect hazard: making the replay succeed is what first makes
      // `prior == promoted` reachable inside submit, and an unguarded delete
      // would then destroy the very screenshot it just re-confirmed.
      //
      // What this test pins is the FIRST defence — the replay returns before
      // any delete. It does not force the second (`prior != promoted` on the
      // delete), which stays unreachable while the branch above holds; that
      // guard is there so moving or removing the branch cannot turn a replay
      // into a self-destruct. Said plainly rather than claimed.
      final store = _RealisticStorage();
      final svc = svcWith(store);
      await seed('a-rep3', userId: 'user1');
      await svc.submit('user1', 'a-rep3', 'pending/deposit/user1/y.jpg');
      store.deleted.clear();
      await svc.submit('user1', 'a-rep3', 'pending/deposit/user1/y.jpg');
      expect(
        store.deleted,
        isEmpty,
        reason: 'a replay must destroy nothing at all',
      );
    });

    test('a replay after the salon accepted is still a conflict', () async {
      // The replay check sits BELOW the status gate on purpose: re-confirming
      // a key on a settled booking is a different act from retrying a lost
      // reply, and lifting it above the gate would be a contract change.
      final store = _RealisticStorage();
      final svc = svcWith(store);
      await seed('a-rep4', userId: 'user1');
      await svc.submit('user1', 'a-rep4', 'pending/deposit/user1/z.jpg');
      await appts.update('a-rep4', {'status': 'confirmed'});
      final r = await svc.submit(
        'user1',
        'a-rep4',
        'pending/deposit/user1/z.jpg',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_state');
    });

    test('a claimed key with no object behind it is refused', () async {
      final store = FakeStorageService(
        missing: {'pending/deposit/user1/ghost.jpg'},
      );
      final svc = DepositService(
        appts,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        store,
      );
      await seed('a-ghost', userId: 'user1');
      final r = await svc.submit(
        'user1',
        'a-ghost',
        'pending/deposit/user1/ghost.jpg',
      );
      expect(r.ok, isFalse);
      expect(r.error, 'upload_not_found');
    });
  });
}

/// A fake where deleting actually deletes.
///
/// [FakeStorageService.objectSize] consults `sizes`/`missing`/`defaultSize` and
/// **ignores `deleted`**, so an object stays visible after it has been removed.
/// That is fine for the claim tests — and fatal for these: a replay test built
/// on it passes against the very code it is meant to catch, because the second
/// `verify` still finds the pending source the first claim deleted.
///
/// Modelling the delete is what makes « re-sending the same key » mean what it
/// means in production.
class _RealisticStorage extends FakeStorageService {
  _RealisticStorage({super.sizes});

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) async {
    await super.deleteObject(key: key, bucket: bucket);
    missing.add(key);
  }
}
