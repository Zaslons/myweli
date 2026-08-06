import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/favorites_repository.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/privacy/user_erasure_service.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/me/index.dart' as me_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockAuth extends Mock implements AuthRepository {}

/// Fails the FIRST step of the cascade, so the ordering invariant is
/// observable: the identity must still be there afterwards.
class _ThrowingDevices extends InMemoryDeviceTokenRepository {
  @override
  Future<void> deleteForUser(String userId) async =>
      throw StateError('storage down');
}

/// L1 — `DELETE /me` must erase what the privacy policy says it erases
/// (docs/design/account-deletion-erasure.md; docs/design/legal-l1.md).
///
/// **Why this file exists at all.** `DELETE /me` has returned 204 since it
/// shipped, and left most of the person behind. Every table below stores
/// `user_id` as a plain `text` column with **no foreign key**, so nothing
/// cascades: reviews keep the display name, appointments keep name/phone/notes,
/// favourites and notifications and preferences survive, deposit screenshots are
/// never touched — and `device_tokens` survives, so **a deleted user's phone keeps
/// receiving push**. That last one is a live bug, not a wording problem.
///
/// **Bystander B is the whole design.** Every assertion has a twin: the victim
/// changed, and a second user with the identical shape did not. An over-broad
/// predicate — `DELETE FROM favorites` with the `WHERE` forgotten, a
/// `startsWith('deposit/')` that reaches another user's bucket prefix — passes
/// every victim assertion in this file and fails B. Without B the suite would
/// certify a cascade that erases the database.
///
/// **What this file drives is the ROUTE**, so every red is behavioural rather than
/// a missing symbol. Two assertions were deferred to the service commit because
/// they need `UserErasureService` to be observable at all — the **storage**
/// DELETEs, and the **ordering invariant** that a failing child step leaves the
/// `users` row alive to retry. They are the two sharpest in the slice, and they
/// are at the bottom of this file.
void main() {
  group('DELETE /me — the erasure cascade', () {
    final tokens = TokenService(secret: 'test-secret');

    late _MockAuth auth;
    late InMemoryDeviceTokenRepository devices;
    late InMemoryNotificationsRepository notifications;
    late InMemoryNotificationPrefsRepository prefs;
    late InMemoryFavoritesRepository favorites;
    late InMemoryReviewsRepository reviews;
    late InMemoryAppointmentRepository appointments;
    late InMemoryClientsRepository clients;

    /// Every storage object the cascade asked to erase, in order.
    late List<String> erasedObjects;

    const victim = 'A';
    const bystander = 'B';

    AuthUser userRow(String id) => AuthUser(
      id: id,
      phoneNumber: '+225070000000$id',
      name: 'Awa $id',
      createdAt: DateTime.utc(2026),
    );

    /// One person's full footprint, seeded identically for the victim and the
    /// bystander — so any assertion that passes for A and B alike is proving
    /// nothing.
    Future<void> seed(String uid) async {
      await devices.upsert(
        token: 'tok-$uid-1',
        userId: uid,
        role: 'user',
        platform: 'android',
      );
      await devices.upsert(
        token: 'tok-$uid-2',
        userId: uid,
        role: 'user',
        platform: 'ios',
      );
      for (var i = 0; i < 3; i++) {
        await notifications.add(
          userId: uid,
          type: 'booking_confirmed',
          title: 'Rendez-vous confirmé',
          body: 'Salon Excellence',
        );
      }
      // Opt-out model: every flag defaults to TRUE, so `false` is the only
      // value that distinguishes a live row from a deleted one.
      await prefs.update(uid, reminders: false, marketing: false);
      await favorites.add(uid, 'provider1');
      await favorites.add(uid, 'provider2');
      await appointments.create({
        'id': 'appt-$uid',
        'userId': uid,
        'providerId': 'provider1',
        'clientName': 'Awa $uid',
        'clientPhone': '+225070000000$uid',
        'notes': 'Allergique à l’ammoniaque',
        'depositScreenshotUrl': 'deposit/$uid/proof.jpg',
        // `appointment_date` is NOT NULL in the schema (migrations.dart:72) and
        // `listForUser` sorts on it — a seed without one throws in the sort,
        // which is how this fixture gap surfaced rather than staying latent.
        'appointmentDate': '2026-03-09T10:00:00.000Z',
        'status': 'completed',
      });
      await reviews.upsertByAppointment({
        'id': 'review-$uid',
        'appointmentId': 'appt-$uid',
        'userId': uid,
        'userName': 'Awa $uid',
        'providerId': 'provider1',
        'rating': 5,
        'text': 'Très bien',
        'createdAt': '2026-03-11T10:00:00.000Z',
        'photoUrls': ['https://cdn.myweli.com/review/$uid/before.jpg'],
      });
      // Both A and B report the SAME real review, so the grouped
      // `reportCount` is an observable 2 that must fall to 1 — see the report
      // test for why this shape, and not the obvious one, is the honest gate.
      await reviews.addReport('review-target', uid, 'spam');
    }

    /// The review A and B both report. Real, so it survives the grouping join.
    Future<void> seedReportTarget() => reviews.upsertByAppointment({
      'id': 'review-target',
      'appointmentId': 'appt-target',
      'userId': 'someone-else',
      'userName': 'Kouassi',
      'providerId': 'provider1',
      'rating': 1,
      'text': 'Bof',
      'createdAt': '2026-03-10T10:00:00.000Z',
    });

    setUp(() async {
      auth = _MockAuth();
      devices = InMemoryDeviceTokenRepository();
      notifications = InMemoryNotificationsRepository();
      prefs = InMemoryNotificationPrefsRepository();
      favorites = InMemoryFavoritesRepository();
      reviews = InMemoryReviewsRepository();
      appointments = InMemoryAppointmentRepository();
      clients = InMemoryClientsRepository();
      erasedObjects = <String>[];

      when(
        () => auth.userById(victim),
      ).thenAnswer((_) async => userRow(victim));
      when(
        () => auth.userById(bystander),
      ).thenAnswer((_) async => userRow(bystander));
      when(() => auth.userById('ghost')).thenAnswer((_) async => null);
      when(() => auth.deleteUser(any())).thenAnswer((_) async => true);
      when(() => auth.deleteUser('ghost')).thenAnswer((_) async => false);

      await seedReportTarget();
      await seed(victim);
      await seed(bystander);
    });

    ClientsService clientsService() {
      final providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
      return ClientsService(
        providerAuth,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        auth,
        clients,
        appointments,
        InMemoryProviderAuditLogRepository(),
      );
    }

    /// Set to a table name to make that repository throw — the ordering gate.
    UserErasureService erasureService({http.Client? client}) =>
        UserErasureService(
          auth,
          devices,
          notifications,
          prefs,
          favorites,
          reviews,
          appointments,
          clientsService(),
          FakeStorageService(),
          client:
              client ??
              MockClient((req) async {
                expect(req.method, 'DELETE');
                erasedObjects.add(req.url.path);
                return http.Response('', 204);
              }),
        );

    RequestContext ctx(Request request, {UserErasureService? erasure}) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<AuthRepository>()).thenReturn(auth);
      when(() => c.read<ClientsService>()).thenReturn(clientsService());
      when(() => c.read<DeviceTokenRepository>()).thenReturn(devices);
      when(() => c.read<NotificationsRepository>()).thenReturn(notifications);
      when(() => c.read<NotificationPrefsRepository>()).thenReturn(prefs);
      when(() => c.read<FavoritesRepository>()).thenReturn(favorites);
      when(() => c.read<ReviewsRepository>()).thenReturn(reviews);
      when(() => c.read<AppointmentRepository>()).thenReturn(appointments);
      when(
        () => c.read<UserErasureService>(),
      ).thenReturn(erasure ?? erasureService());
      return c;
    }

    Request req(String method, {String? token}) => Request(
      method,
      Uri.parse('http://localhost/me'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, {String role = 'user'}) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    Future<Response> erase(String sub, {String role = 'user'}) =>
        me_route.onRequest(ctx(req('DELETE', token: tok(sub, role: role))));

    Future<Map<String, dynamic>?> apptOf(String uid) =>
        appointments.byId('appt-$uid');

    Future<Map<String, dynamic>?> reviewOf(String uid) async {
      final r = await reviews.listForProvider(
        'provider1',
        page: 1,
        pageSize: 50,
      );
      for (final row in r.items) {
        if (row['id'] == 'review-$uid') return row;
      }
      return null;
    }

    // ---- The cascade -------------------------------------------------------

    test(
      'the deleted user stops receiving push — device tokens are gone',
      () async {
        expect(await devices.tokensForUser(victim), hasLength(2));
        expect((await erase(victim)).statusCode, HttpStatus.noContent);

        expect(
          await devices.tokensForUser(victim),
          isEmpty,
          reason:
              'this is the live bug, not a compliance nicety: delete your '
              'account and keep getting notifications about a salon you no '
              'longer have a relationship with, with no way to stop it because '
              'the account that held the preference is gone',
        );
        expect(
          await devices.tokensForUser(bystander),
          hasLength(2),
          reason:
              'and B keeps both — a DELETE that forgot its WHERE would pass '
              'the assertion above',
        );
      },
    );

    test('the notification feed and its preferences go', () async {
      expect((await erase(victim)).statusCode, HttpStatus.noContent);

      expect(await notifications.listForUser(victim, limit: 50), isEmpty);
      expect(
        await notifications.listForUser(bystander, limit: 50),
        hasLength(3),
      );

      // `get` upserts a default, so absence reads as "back to defaults".
      expect((await prefs.get(victim)).marketing, isTrue);
      expect((await prefs.get(bystander)).marketing, isFalse);
    });

    test('favourites go', () async {
      expect((await erase(victim)).statusCode, HttpStatus.noContent);
      expect(await favorites.listForUser(victim), isEmpty);
      expect(await favorites.listForUser(bystander), hasLength(2));
    });

    test('the review survives, the reviewer does not', () async {
      expect((await erase(victim)).statusCode, HttpStatus.noContent);

      final r = await reviewOf(victim);
      expect(
        r,
        isNotNull,
        reason:
            'the rating is a public aggregate the salon EARNED. Deleting '
            'the row would silently re-score a business because a customer '
            'closed an account',
      );
      expect(r!['rating'], 5);
      expect(r['userName'], isNot('Awa $victim'));
      expect(r['userId'], isNot(victim));

      final b = await reviewOf(bystander);
      expect(b!['userName'], 'Awa $bystander');
      expect(b['userId'], bystander);
    });

    test('the review PHOTOS go — the tombstone is not defeated by a URL', () async {
      // **The hole the adversarial review found, and the sharpest one in the
      // slice.** Anonymising `user_id` hides the id in the column and leaves it
      // in the payload beside it: review photos are uploaded to
      // `review/{userId}/{uuid}.{ext}` in the **public** bucket
      // (`upload_signing_service.dart:98`), so an erased reviewer's URLs still
      // read `…/review/1f3a…/before.jpg`. Anyone could group every review that
      // person ever left, across every salon, by prefix — and the photos are
      // frequently of their own face or hair, served forever.
      expect((await erase(victim)).statusCode, HttpStatus.noContent);

      final r = await reviewOf(victim);
      expect(r!['photoUrls'], isEmpty, reason: 'detached from the review');
      expect(
        erasedObjects.where((p) => p.contains('review/$victim/')),
        hasLength(1),
        reason:
            'and erased from the public bucket, not merely unlinked — an '
            'object nobody links to is still an object anybody can fetch',
      );

      final b = await reviewOf(bystander);
      expect(b!['photoUrls'], hasLength(1));
      expect(
        erasedObjects.where((p) => p.contains('review/$bystander/')),
        isEmpty,
      );
    });

    test('a filed report is deleted, not tombstoned', () async {
      // `UNIQUE (review_id, reporter_user_id)` means two erased users who
      // reported the same review would COLLIDE on a shared tombstone — so this
      // is the one row that cannot be anonymised.
      //
      // **The obvious assertion here was vacuous, and it passed.** The first
      // draft filed a report against a review id that did not exist and then
      // read `reporterUserId` off the result — a key the GROUPED shape does not
      // carry (`reviews_repository.dart:183-192` returns reviewId · providerId ·
      // userName · rating · text · moderationStatus · reportCount · lastReason ·
      // lastReportedAt). It read null, compared null against the victim, and
      // went green on a cascade that had erased nothing. `reportCount` is the
      // one number this API exposes that actually moves.
      Future<int> reportCount() async {
        final r = await reviews.listReportedReviews(page: 1, pageSize: 50);
        for (final row in r.items) {
          if (row['reviewId'] == 'review-target') {
            return row['reportCount'] as int;
          }
        }
        return 0;
      }

      expect(await reportCount(), 2, reason: 'A and B both reported it');
      expect((await erase(victim)).statusCode, HttpStatus.noContent);
      expect(
        await reportCount(),
        1,
        reason:
            'A\'s report is gone and B\'s is untouched. Recorded side '
            'effect: an OPEN, unactioned report loses its count — an already '
            'hidden review stays hidden, because moderation status lives on '
            '`reviews`, not on the report',
      );
    });

    test(
      'the appointment is stripped, not deleted — the salon keeps its book',
      () async {
        expect((await erase(victim)).statusCode, HttpStatus.noContent);

        final a = await apptOf(victim);
        expect(
          a,
          isNotNull,
          reason:
              'once the name, phone and notes are gone a dangling opaque id '
              'is a business record, not an identity — and the salon needs its '
              'booking history to reconcile takings',
        );
        expect(a!['clientName'], isNull);
        expect(a['clientPhone'], isNull);
        expect(a['notes'], isNull);
        expect(a['depositScreenshotUrl'], isNull);

        final b = await apptOf(bystander);
        expect(b!['clientName'], 'Awa $bystander');
        expect(b['clientPhone'], isNotNull);
        expect(b['notes'], isNotNull);
        expect(b['depositScreenshotUrl'], 'deposit/$bystander/proof.jpg');
      },
    );

    test('the identity row goes last, and it goes', () async {
      expect((await erase(victim)).statusCode, HttpStatus.noContent);
      verify(() => auth.deleteUser(victim)).called(1);
      verifyNever(() => auth.deleteUser(bystander));
    });

    // ---- The future-bookings gate ------------------------------------------

    test('a confirmed booking TOMORROW blocks the erasure', () async {
      // **Owner decision, and it matches the provider path.** A salon holds a
      // slot for a named person; if that person can vanish without cancelling,
      // the salon is left with a confirmed appointment it can neither contact
      // nor fill — `booking_notifier` resolves no recipient once the phone is
      // NULL, so even the reminder silently no-ops, and the slot stays blocked
      // by `appointments_slot_unique`. Cancel first, then delete.
      await appointments.create({
        'id': 'appt-$victim-future',
        'userId': victim,
        'providerId': 'provider1',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'status': 'confirmed',
      });

      final res = await erase(victim);
      expect(res.statusCode, HttpStatus.conflict);
      expect((await res.json() as Map)['error'], 'future_bookings');

      // And **nothing** was erased — the gate fires before the first step, so a
      // refusal is not a half-deletion.
      expect(await devices.tokensForUser(victim), hasLength(2));
      expect(await favorites.listForUser(victim), hasLength(2));
      expect((await reviewOf(victim))!['userName'], 'Awa $victim');
      verifyNever(() => auth.deleteUser(any()));
    });

    test('a PAST booking, or a cancelled one, does not block', () async {
      // The seeded appointment is `status: completed` and undated, and the two
      // added here are the cases a naive `status != cancelled` check would trip
      // on. Without this the gate would lock every account that ever booked.
      await appointments.create({
        'id': 'appt-$victim-past',
        'userId': victim,
        'providerId': 'provider1',
        'appointmentDate': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'status': 'confirmed',
      });
      await appointments.create({
        'id': 'appt-$victim-cancelled',
        'userId': victim,
        'providerId': 'provider1',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 2))
            .toIso8601String(),
        'status': 'cancelled',
      });

      expect((await erase(victim)).statusCode, HttpStatus.noContent);
    });

    test('a PENDING request tomorrow blocks too', () async {
      // Pending is a slot the salon is holding while it decides. Letting it
      // become unattributable is the same problem as a confirmed one.
      await appointments.create({
        'id': 'appt-$victim-pending',
        'userId': victim,
        'providerId': 'provider1',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'status': 'pending',
      });
      expect((await erase(victim)).statusCode, HttpStatus.conflict);
    });

    test("a BYSTANDER's future booking does not block me", () async {
      await appointments.create({
        'id': 'appt-$bystander-future',
        'userId': bystander,
        'providerId': 'provider1',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'status': 'confirmed',
      });
      expect((await erase(victim)).statusCode, HttpStatus.noContent);
    });

    // ---- Authz -------------------------------------------------------------

    test('anonymous → 401, and nothing is touched', () async {
      final res = await me_route.onRequest(ctx(req('DELETE')));
      expect(res.statusCode, HttpStatus.unauthorized);
      expect(await devices.tokensForUser(victim), hasLength(2));
      expect(await favorites.listForUser(victim), hasLength(2));
      verifyNever(() => auth.deleteUser(any()));
    });

    test('a PROVIDER token → 403, and its rows survive', () async {
      // `device_tokens` and `notifications` hold provider rows too — `user_id`
      // is whatever the token's `sub` is, with a `role` column beside it. A
      // cascade keyed only on `user_id` reaches across the consumer/pro
      // boundary unless the route refuses the role outright.
      final res = await erase(victim, role: 'provider');
      expect(res.statusCode, HttpStatus.forbidden);
      expect(await devices.tokensForUser(victim), hasLength(2));
      expect(await notifications.listForUser(victim, limit: 50), hasLength(3));
      verifyNever(() => auth.deleteUser(any()));
    });

    // ---- The two that needed the service ----------------------------------

    test('the deposit screenshot is erased, and only this user\'s', () async {
      // A foreign key sitting on the victim's own row must be SKIPPED, not
      // trusted — the same defence in depth the KYC path applies
      // (`provider_account_service.dart:68`). Loosen the prefix check to
      // `'deposit/'` and this is the assertion that goes red.
      await appointments.create({
        'id': 'appt-$victim-2',
        'userId': victim,
        'providerId': 'provider1',
        'depositScreenshotUrl': 'deposit/$bystander/stolen.jpg',
        'appointmentDate': '2026-03-08T10:00:00.000Z',
        'status': 'completed',
      });

      expect((await erase(victim)).statusCode, HttpStatus.noContent);
      // Scoped to the deposit bucket: the same capture list now also holds the
      // review photo the erasure removes from the PUBLIC bucket.
      final deposits = erasedObjects
          .where((p) => p.contains('deposit/'))
          .toList();
      expect(deposits, hasLength(1));
      expect(deposits.single, contains('deposit/$victim/proof.jpg'));
    });

    test('a storage failure never blocks the erasure', () async {
      final c = ctx(
        req('DELETE', token: tok(victim)),
        erasure: erasureService(
          client: MockClient((_) async => throw const SocketException('down')),
        ),
      );

      expect((await me_route.onRequest(c)).statusCode, HttpStatus.noContent);
      verify(() => auth.deleteUser(victim)).called(1);
      expect(
        await devices.tokensForUser(victim),
        isEmpty,
        reason:
            'the objects are uuid-named in a private bucket with the rows '
            'gone, so a survivor is unreachable — blocking on it would leave '
            'the account alive instead',
      );
    });

    test('a failing child step leaves the account RETRYABLE', () async {
      // **The ordering gate.** Move `_auth.deleteUser` to the top of
      // `eraseUser` and this is the only test that changes: the identity would
      // already be gone, the owner would have no token to retry with, and the
      // rows this step failed on would survive forever. Every other assertion
      // in this file would stay green.
      final c = ctx(
        req('DELETE', token: tok(victim)),
        erasure: UserErasureService(
          auth,
          _ThrowingDevices(),
          notifications,
          prefs,
          favorites,
          reviews,
          appointments,
          clientsService(),
          FakeStorageService(),
        ),
      );

      await expectLater(me_route.onRequest(c), throwsA(isA<StateError>()));
      verifyNever(() => auth.deleteUser(any()));
    });

    test('unknown subject → 404, and erasing twice is clean', () async {
      expect((await erase('ghost')).statusCode, HttpStatus.notFound);

      expect((await erase(victim)).statusCode, HttpStatus.noContent);
      when(() => auth.userById(victim)).thenAnswer((_) async => null);
      expect(
        (await erase(victim)).statusCode,
        HttpStatus.notFound,
        reason:
            'every step is idempotent, so a retry after a partial failure '
            'converges rather than throwing',
      );
    });
  });
}
