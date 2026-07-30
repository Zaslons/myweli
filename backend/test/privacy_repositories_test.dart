import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/favorites_repository.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/privacy/anonymized_identity.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:test/test.dart';

/// L1 — the erasure verbs, one repository at a time
/// (docs/design/account-deletion-erasure.md §4).
///
/// **Why this exists beside `me_erasure_test.dart`.** That file drives the route,
/// so while the wiring is missing it is red for *every* table and tells you
/// nothing about whether any individual method works. These tests call the
/// repositories directly, so the two failures are separable: a red here is a
/// broken verb, a red there with these green is broken wiring.
///
/// Every test carries a **bystander**. A predicate that forgets its `WHERE`
/// satisfies every victim assertion ever written.
void main() {
  const victim = 'A';
  const bystander = 'B';

  group('deleteForUser', () {
    test('device tokens — the live bug', () async {
      final r = InMemoryDeviceTokenRepository();
      for (final u in [victim, bystander]) {
        await r.upsert(
          token: 'tok-$u-1',
          userId: u,
          role: 'user',
          platform: 'android',
        );
        await r.upsert(
          token: 'tok-$u-2',
          userId: u,
          role: 'user',
          platform: 'ios',
        );
      }
      await r.deleteForUser(victim);
      expect(await r.tokensForUser(victim), isEmpty);
      expect(await r.tokensForUser(bystander), hasLength(2));
    });

    test('notifications', () async {
      final r = InMemoryNotificationsRepository();
      for (final u in [victim, bystander]) {
        await r.add(userId: u, type: 't', title: 'Titre', body: 'Corps');
      }
      await r.deleteForUser(victim);
      expect(await r.listForUser(victim, limit: 10), isEmpty);
      expect(await r.listForUser(bystander, limit: 10), hasLength(1));
    });

    test('notification preferences fall back to defaults', () async {
      final r = InMemoryNotificationPrefsRepository();
      // The model is **opt-out** — every flag defaults to TRUE
      // (`notification_prefs_repository.dart:4-8`). So the distinguishing value
      // is `false`: setting `true` would have asserted nothing, because a
      // deleted row reads `true` too. The first draft did exactly that and went
      // red for the right reason.
      await r.update(victim, marketing: false);
      await r.update(bystander, marketing: false);
      await r.deleteForUser(victim);
      expect(
        (await r.get(victim)).marketing,
        isTrue,
        reason: 'back to default',
      );
      expect((await r.get(bystander)).marketing, isFalse);
    });

    test('favourites', () async {
      final r = InMemoryFavoritesRepository();
      for (final u in [victim, bystander]) {
        await r.add(u, 'provider1');
        await r.add(u, 'provider2');
      }
      await r.deleteForUser(victim);
      expect(await r.listForUser(victim), isEmpty);
      expect(await r.listForUser(bystander), hasLength(2));
    });
  });

  group('anonymizeUser', () {
    test('reviews keep their rating and lose their author', () async {
      final r = InMemoryReviewsRepository();
      for (final u in [victim, bystander]) {
        await r.upsertByAppointment({
          'id': 'review-$u',
          'appointmentId': 'appt-$u',
          'userId': u,
          'userName': 'Awa $u',
          'providerId': 'p1',
          'rating': 5,
          'text': 'Très bien',
          'createdAt': '2026-03-1${u == victim ? 1 : 2}T10:00:00.000Z',
        });
      }

      final before = await r.aggregateProvider('p1');
      await r.anonymizeUser(victim);
      final after = await r.aggregateProvider('p1');

      expect(
        after.count,
        before.count,
        reason:
            'the rating is a public aggregate the salon EARNED — erasing '
            'the person must not re-score the business',
      );
      expect(after.rating, before.rating);

      final page = await r.listForProvider('p1', page: 1, pageSize: 10);
      final v = page.items.firstWhere((x) => x['id'] == 'review-$victim');
      final b = page.items.firstWhere((x) => x['id'] == 'review-$bystander');
      expect(v['userName'], anonymousClientLabel);
      expect(
        v['userId'],
        deletedUserId,
        reason:
            'a tombstone, never NULL: the column is NOT NULL and the '
            'shipped mobile model types it non-nullable',
      );
      expect(b['userName'], 'Awa $bystander');
      expect(b['userId'], bystander);
    });

    test(
      'reports filed by the erased user are deleted, not tombstoned',
      () async {
        final r = InMemoryReviewsRepository();
        await r.upsertByAppointment({
          'id': 'target',
          'appointmentId': 'a0',
          'userId': 'someone',
          'userName': 'Kouassi',
          'providerId': 'p1',
          'rating': 1,
          'text': 'Bof',
          'createdAt': '2026-03-10T10:00:00.000Z',
        });
        await r.addReport('target', victim, 'spam');
        await r.addReport('target', bystander, 'spam');

        await r.anonymizeUser(victim);

        final reported = await r.listReportedReviews(page: 1, pageSize: 10);
        final row = reported.items.firstWhere((x) => x['reviewId'] == 'target');
        expect(
          row['reportCount'],
          1,
          reason:
              'UNIQUE (review_id, reporter_user_id) means two erased users '
              'who reported the same review would COLLIDE on a shared tombstone '
              '— so this is the one row that cannot be anonymised',
        );
      },
    );

    test(
      'appointments are stripped and hand back their deposit keys',
      () async {
        final r = InMemoryAppointmentRepository();
        for (final u in [victim, bystander]) {
          await r.create({
            'id': 'appt-$u',
            'userId': u,
            'providerId': 'p1',
            'clientName': 'Awa $u',
            'clientPhone': '+22507000000',
            'notes': 'Allergique',
            'depositScreenshotUrl': 'deposit/$u/proof.jpg',
            'status': 'completed',
          });
        }

        final keys = await r.anonymizeUser(victim);
        expect(
          keys,
          ['deposit/$victim/proof.jpg'],
          reason:
              'the caller needs these to erase the objects, and it can only '
              'get them from the statement that cleared the column',
        );

        final v = await r.byId('appt-$victim');
        expect(v!['clientName'], isNull);
        expect(v['clientPhone'], isNull);
        expect(v['notes'], isNull);
        expect(v['depositScreenshotUrl'], isNull);
        expect(v['status'], 'completed', reason: 'the booking itself survives');

        final b = await r.byId('appt-$bystander');
        expect(b!['clientName'], 'Awa $bystander');
        expect(b['depositScreenshotUrl'], 'deposit/$bystander/proof.jpg');
      },
    );

    test('an appointment with no deposit returns no key', () async {
      final r = InMemoryAppointmentRepository();
      await r.create({
        'id': 'a1',
        'userId': victim,
        'providerId': 'p1',
        'clientName': 'Awa',
        'status': 'pending',
      });
      expect(await r.anonymizeUser(victim), isEmpty);
    });
  });

  test('the salon-clients label comes from the same constant', () async {
    // The mutation hook: change `anonymousClientLabel` and THIS assertion and
    // the reviews one above fail together. Two literals that happen to be
    // spelled the same would not.
    final r = InMemoryClientsRepository();
    await r.create({
      'id': 'sc1',
      'providerId': 'p1',
      'userId': victim,
      'displayName': 'Awa',
      'phone': '+2250700000001',
      'tags': <String>[],
    });
    await r.anonymizeUser(victim);
    final page = await r.list('p1', page: 1, pageSize: 10);
    expect(page.items.single['displayName'], anonymousClientLabel);
    expect(page.items.single['userId'], isNull);
    expect(page.items.single['phone'], isNull);
  });
}
