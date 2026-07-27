import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
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
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:test/test.dart';

import '../routes/me/index.dart' as me_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockAuth extends Mock implements AuthRepository {}

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
/// **What this file drives is the ROUTE**, not a service, so every red below is
/// behavioural rather than a missing symbol. Two assertions cannot be written
/// this way and are deferred to the service commit, stated here rather than
/// discovered later:
///
///   * the **storage** DELETEs (there is no HTTP seam on this path today), and
///   * the **ordering invariant** — that a failing child step leaves the `users`
///     row alive so the owner can retry.
///
/// Both need `UserErasureService` to exist to be observable. They are the two
/// sharpest assertions in the slice, and they arrive with it.
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
      await prefs.update(uid, reminders: false, marketing: true);
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

    RequestContext ctx(Request request) {
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
      expect((await prefs.get(victim)).marketing, isFalse);
      expect((await prefs.get(bystander)).marketing, isTrue);
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
