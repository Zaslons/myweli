import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:test/test.dart';

import '../routes/me/provider/reviews.dart' as me_reviews;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockProviderAuth extends Mock implements ProviderAuthRepository {}

class _MockProviders extends Mock implements ProvidersRepository {}

ProviderAccount _account({String? providerId}) => ProviderAccount(
  id: 'acc1',
  phoneNumber: '+2250700000009',
  businessName: 'Salon Awa',
  businessType: 'salon',
  createdAt: DateTime.utc(2026),
)..providerId = providerId;

/// The pro reads its OWN reviews by account (`GET /me/provider/reviews`).
///
/// **This is PR1b's miss, one file over.** PR1b moved four pro surfaces off the
/// anonymous `GET /providers/{id}`, and its source pin forbade
/// `serviceLocator.providerService` / `getProviderById` / `loadProviderById`.
/// Both « Avis » surfaces named none of those: mobile went through the
/// **consumer** review service (`api_review_service.dart`, commented
/// `// public`, no token) and web through `/api/pro/reviews` → the public
/// `/providers/{id}/reviews`. A directory-scoped pin is blind to a defect that
/// crosses its boundary, and this one crossed a *service* boundary instead of a
/// directory one — same shape, different axis.
///
/// It matters because a `draft` salon **can** have reviews: T53 (account
/// erasure) and T54 (billing unpublish) both write `status → draft` over a
/// salon with history. Closing the public reviews route would 404 the « Avis »
/// page of exactly the owner being asked to pay.
void main() {
  group('GET /me/provider/reviews', () {
    final tokens = TokenService(secret: 'test-secret');
    late _MockProviderAuth auth;
    late _MockProviders providers;
    late InMemoryMembershipRepository memberships;
    late InMemoryReviewsRepository reviews;

    setUp(() {
      auth = _MockProviderAuth();
      providers = _MockProviders();
      memberships = InMemoryMembershipRepository();
      reviews = InMemoryReviewsRepository();
    });

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
      when(() => c.read<ProvidersRepository>()).thenReturn(providers);
      when(
        () => c.read<MembershipService>(),
      ).thenReturn(MembershipService(memberships, auth));
      when(() => c.read<ReviewsService>()).thenReturn(
        ReviewsService(
          reviews,
          InMemoryAppointmentRepository(),
          providers,
          InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
        ),
      );
      return c;
    }

    Request req(String method, {String? token, String? salonId}) => Request(
      method,
      Uri.parse(
        'http://localhost/me/provider/reviews'
        '${salonId == null ? '' : '?salonId=$salonId'}',
      ),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub, String role) =>
        tokens.issueAccessToken(subject: sub, role: role).token;

    Future<void> seedReview(String providerId, {String id = 'r1'}) async {
      await reviews.upsertByAppointment({
        'id': id,
        'providerId': providerId,
        'userId': 'u1',
        'appointmentId': 'a1',
        'rating': 5,
        'comment': 'Superbe',
        'authorName': 'Awa',
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'hidden': false,
      });
    }

    test('a DRAFT salon still reads its own reviews', () async {
      // THE assertion. The public route will 404 this salon; the owner's
      // « Avis » page must not go with it.
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'p1'));
      when(() => providers.byId('p1')).thenAnswer(
        (_) async => {'id': 'p1', 'name': 'Salon Awa', 'status': 'draft'},
      );
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: 'acc1',
        email: 'a@b.ci',
      );
      await seedReview('p1');

      final res = await me_reviews.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect((m['items'] as List), hasLength(1));
      expect(((m['items'] as List).first as Map)['comment'], 'Superbe');
      expect(m['total'], 1);
    });

    // docs/design/salon-reviews-summary.md — the « Avis » card's numbers are
    // the WHOLE salon's, not the page's: web averaged the 50 it had loaded
    // beside the server's total, and the app the first 50 it ever loaded.
    group('summary — the whole salon, never the page', () {
      Future<void> owner() async {
        when(
          () => auth.accountById('acc1'),
        ).thenAnswer((_) async => _account(providerId: 'p1'));
        when(() => providers.byId('p1')).thenAnswer(
          (_) async => {'id': 'p1', 'name': 'Salon Awa', 'status': 'active'},
        );
        await memberships.ensureOwner(
          providerId: 'p1',
          accountId: 'acc1',
          email: 'a@b.ci',
        );
      }

      Future<void> review(int n, int rating, {bool hidden = false}) =>
          reviews.upsertByAppointment({
            'id': 'r$n',
            'providerId': 'p1',
            'userId': 'u$n',
            'appointmentId': 'a$n',
            'rating': rating,
            'createdAt': DateTime.utc(2026, 1, 1, 0, n).toIso8601String(),
            if (hidden) 'moderationStatus': 'hidden',
          });

      Future<Map<String, dynamic>> summary({int page = 1}) async {
        final res = await me_reviews.onRequest(
          ctx(
            Request(
              'GET',
              Uri.parse('http://localhost/me/provider/reviews?page=$page'),
              headers: {'Authorization': 'Bearer ${tok('acc1', 'provider')}'},
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.ok);
        return ((await res.json() as Map)['summary'] as Map)
            .cast<String, dynamic>();
      }

      test('60 reviews, a page of 20: the summary counts the 60', () async {
        await owner();
        // 30 × 5★, 20 × 4★, 10 × 1★ → (150 + 80 + 10) / 60 = 4.0
        for (var i = 0; i < 60; i++) {
          await review(i, i < 30 ? 5 : (i < 50 ? 4 : 1));
        }
        for (final page in [1, 3]) {
          final s = await summary(page: page);
          expect(s['count'], 60);
          expect(s['average'], 4.0);
          expect(s['distribution'], {
            '5': 30,
            '4': 20,
            '3': 0,
            '2': 0,
            '1': 10,
          });
        }
      });

      test('the average is the one clients see: one decimal', () async {
        await owner();
        await review(1, 5);
        await review(2, 4);
        await review(3, 4); // 13 / 3 = 4.333…
        expect((await summary())['average'], 4.3);
      });

      test('a hidden review counts nowhere — as on the salon page', () async {
        await owner();
        await review(1, 5);
        await review(2, 1, hidden: true);
        final s = await summary();
        expect(s['count'], 1);
        expect(s['average'], 5.0);
        expect((s['distribution'] as Map)['1'], 0);
      });

      test('no review yet: zeros, never null', () async {
        await owner();
        final s = await summary();
        expect(s['count'], 0);
        expect(s['average'], 0);
        expect(s['distribution'], {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0});
      });
    });

    test('anonymous → 401', () async {
      final res = await me_reviews.onRequest(ctx(req('GET')));
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('a consumer token → 403, never the salon it names', () async {
      final res = await me_reviews.onRequest(
        ctx(req('GET', token: tok('u1', 'user'))),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('a pro who is not a member of the named salon → 403', () async {
      // Cross-tenant: the whole reason this replaces a route that took the
      // salon id from the CLIENT. `/api/pro/reviews` forwarded whatever
      // providerId the browser sent, to an endpoint that checked nothing.
      when(
        () => auth.accountById('acc1'),
      ).thenAnswer((_) async => _account(providerId: 'p1'));
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: 'acc1',
        email: 'a@b.ci',
      );
      await seedReview('p2');

      final res = await me_reviews.onRequest(
        ctx(req('GET', token: tok('acc1', 'provider'), salonId: 'p2')),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test(
      'R6: an explicit salonId the caller IS a member of is honoured',
      () async {
        // The pair for the 403 above — without it, « always 403 » would pass.
        when(
          () => auth.accountById('acc1'),
        ).thenAnswer((_) async => _account(providerId: 'p1'));
        when(
          () => providers.byId('p2'),
        ).thenAnswer((_) async => {'id': 'p2', 'name': 'Salon Deux'});
        await memberships.ensureOwner(
          providerId: 'p1',
          accountId: 'acc1',
          email: 'a@b.ci',
        );
        await memberships.ensureOwner(
          providerId: 'p2',
          accountId: 'acc1',
          email: 'a@b.ci',
        );
        await seedReview('p2', id: 'r2');

        final res = await me_reviews.onRequest(
          ctx(req('GET', token: tok('acc1', 'provider'), salonId: 'p2')),
        );
        expect(res.statusCode, HttpStatus.ok);
        expect(((await res.json() as Map)['items'] as List), hasLength(1));
      },
    );

    test('a non-GET verb → 405', () async {
      final res = await me_reviews.onRequest(
        ctx(req('POST', token: tok('acc1', 'provider'))),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
