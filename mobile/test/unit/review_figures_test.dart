import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_figures.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/services/interfaces/favorites_service_interface.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/interfaces/review_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// The figures of a salon after one of its reviews is published
/// (docs/design/amounts-that-fit.md §1.4, §2 « Reviews », §5).
///
/// The server keeps ONE review per appointment and replaces it; the app added
/// one to the count each time, blended the average and showed both tiles —
/// and only on the open salon page: the list, the featured list and the
/// favourites kept the old figures until a reload.
void main() {
  final salons = _Salons();
  final reviews = _Reviews();
  final hearts = _Favorites();

  setUpAll(() {
    serviceLocator.providerService = salons;
    serviceLocator.reviewService = reviews;
    serviceLocator.favoritesService = hearts;
  });

  setUp(() {
    salons
      ..list = const []
      ..featured = const []
      ..onById = null
      ..byIdCalls = 0;
    reviews.refuse = false;
    hearts.salons = const [];
  });

  group('the arithmetic', () {
    (double, int) after(
      double rating,
      int count, {
      required int stars,
      int? replaced,
    }) {
      final f = figuresAfterReview(
        rating: rating,
        reviewCount: count,
        stars: stars,
        replacedStars: replaced,
      );
      return (f.rating, f.reviewCount);
    }

    test('a first review is the salon’s rating', () {
      expect(after(0, 0, stars: 4), (4.0, 1));
    });

    test('a new visit adds one, rounded to one decimal', () {
      expect(after(4.5, 2, stars: 5), (4.7, 3)); // 4,666…
    });

    test('a visit reviewed again keeps the count', () {
      expect(after(4.0, 4, stars: 1, replaced: 5), (3.0, 4));
      expect(after(4.0, 1, stars: 2, replaced: 4), (2.0, 1));
    });

    test('it is an estimate: 0,1 under the server’s figure here', () {
      // 4, 4 and 5 are stored « 4,3 »; with a fourth review of 4 the server
      // says 17 / 4 = 4,25, « 4,3 ». From the rounded figure: « 4,2 ». The
      // re-read is what closes this — this test is why it exists.
      expect(after(4.3, 3, stars: 4), (4.2, 4));
    });

    test('never more than five, never less than one', () {
      expect(after(5.0, 20, stars: 5, replaced: 4), (5.0, 20)); // 5,05
      expect(after(1.0, 2, stars: 1, replaced: 5), (1.0, 2)); // −1
    });

    test('nothing to replace in a salon that counts no review', () {
      expect(after(0, 0, stars: 3, replaced: 5), (3.0, 1));
    });
  });

  group('on the salon page', () {
    test('sent again for the same appointment, a review replaces the first: '
        'one tile, the count steady', () {
      final p = ProviderProvider()
        ..showPreloaded(
          _salon(
            'A',
            rating: 4.0,
            reviewCount: 1,
            reviews: [_review(4, appointment: 'a1', id: 'stored')],
          ),
        );

      // The 201 of a resubmit carries a NEW id — the stored row keeps its
      // own —, so the appointment is the only key there is.
      p.addReviewLocally(_review(2, appointment: 'a1', id: 'minted-again'));

      expect(p.selectedProvider!.reviewCount, 1);
      expect(p.selectedProvider!.rating, 2.0);
      expect(p.selectedProvider!.reviews, hasLength(1));
      expect(p.selectedProvider!.reviews.single.rating, 2);
    });

    test('a replacement among several moves the average by the difference', () {
      final p = ProviderProvider()
        ..showPreloaded(
          _salon(
            'A',
            rating: 4.0,
            reviewCount: 4,
            reviews: [
              _review(5, appointment: 'a1'),
              _review(4, appointment: 'a2'),
              _review(4, appointment: 'a3'),
              _review(3, appointment: 'a4'),
            ],
          ),
        );

      p.addReviewLocally(_review(1, appointment: 'a1'));

      expect(p.selectedProvider!.reviewCount, 4);
      expect(p.selectedProvider!.rating, 3.0); // (16 − 5 + 1) / 4
      expect(p.selectedProvider!.reviews, hasLength(4));
    });

    test('a replacement never shows more than five stars', () {
      // 19 fives and a four are stored as « 5,0 » (4,95 rounded); the four
      // turned into a five is (5,0 × 20 − 4 + 5) / 20 = 5,05 on the rounded
      // figure — the estimate's ceiling is the scale's.
      final p = ProviderProvider()
        ..showPreloaded(
          _salon(
            'A',
            rating: 5.0,
            reviewCount: 20,
            reviews: [_review(4, appointment: 'a1')],
          ),
        );

      p.addReviewLocally(_review(5, appointment: 'a1'));

      expect(p.selectedProvider!.reviewCount, 20);
      expect(p.selectedProvider!.rating, 5.0);
    });

    test('reviews that name no appointment never replace each other', () {
      // Seed data and old payloads carry `appointmentId: ''`: an empty key is
      // not a key, or every one of them would collapse into one review.
      final p = ProviderProvider()
        ..showPreloaded(
          _salon('A', rating: 4.0, reviewCount: 1, reviews: [_review(4)]),
        );

      p.addReviewLocally(_review(2));

      expect(p.selectedProvider!.reviewCount, 2);
      expect(p.selectedProvider!.rating, 3.0);
      expect(p.selectedProvider!.reviews, hasLength(2));
    });

    test('it is the first tile — the page shows the five newest', () {
      final p = ProviderProvider()
        ..showPreloaded(
          _salon(
            'A',
            rating: 4.0,
            reviewCount: 5,
            reviews: [
              for (var i = 1; i <= 5; i++)
                _review(4, appointment: 'old$i', id: 'old$i'),
            ],
          ),
        );

      p.addReviewLocally(_review(5, appointment: 'a1', id: 'mine'));

      expect(p.selectedProvider!.reviews.first.id, 'mine');
      expect(
        p.selectedProvider!.reviews.take(5).map((r) => r.id),
        contains('mine'),
        reason: 'provider_detail_screen renders reviews.take(5)',
      );
      expect(p.selectedProvider!.reviewCount, 6);
    });
  });

  group('on every copy of the salon', () {
    test('the list, the featured list and the map’s lookup carry the same '
        'figures as the page', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      final b = _salon('B', rating: 3.9, reviewCount: 7);
      salons
        ..list = [a, b]
        ..featured = [b, a];
      final p = ProviderProvider();
      await p.loadProviders();
      await p.loadFeaturedProviders();
      p.showPreloaded(a);

      p.addReviewLocally(_review(5, appointment: 'a1'));

      // (4,5 × 2 + 5) / 3 = 4,666…
      expect(_figures(p.selectedProvider!), (4.7, 3));
      expect(_figures(p.providers.first), (4.7, 3));
      expect(_figures(p.featuredProviders.last), (4.7, 3));
      expect(_figures((await p.providerForMap('A'))!), (4.7, 3));
      // In place: the same rows, and the other salon untouched.
      expect(p.providers.map((s) => s.id), ['A', 'B']);
      expect(p.featuredProviders.map((s) => s.id), ['B', 'A']);
      expect(p.providers.last, same(b));
      expect(p.featuredProviders.first, same(b));
      expect(salons.byIdCalls, 0, reason: 'a local update reads nothing');
    });

    test('with ANOTHER salon’s page open, the lists still move — and that '
        'page does not', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      final b = _salon('B', rating: 3.9, reviewCount: 7);
      salons
        ..list = [a, b]
        ..featured = [a];
      final p = ProviderProvider();
      await p.loadProviders();
      await p.loadFeaturedProviders();
      p.showPreloaded(b);

      // « Donner mon avis » on the appointment screen: no salon page of A.
      p.addReviewLocally(_review(5, appointment: 'a1'));

      expect(_figures(p.providers.first), (4.7, 3));
      expect(_figures(p.featuredProviders.single), (4.7, 3));
      expect(p.selectedProvider, same(b));
      expect(p.selectedProviderId, 'B');
    });

    test('with NO salon page open, the lists still move', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      salons
        ..list = [a]
        ..featured = [a];
      final p = ProviderProvider();
      await p.loadProviders();
      await p.loadFeaturedProviders();
      var notified = 0;
      p.addListener(() => notified++);

      p.addReviewLocally(_review(5, appointment: 'a1'));

      expect(_figures(p.providers.single), (4.7, 3));
      expect(_figures(p.featuredProviders.single), (4.7, 3));
      expect(p.selectedProvider, isNull);
      expect(p.selectedProviderId, isNull);
      expect(notified, 1, reason: 'the home cards are told to rebuild');
    });

    test('sent again with no salon page open — the list rows carry no '
        'reviews to look in — it is still one review', () async {
      salons.list = [_salon('A')];
      final p = ProviderProvider();
      await p.loadProviders();

      p.addReviewLocally(_review(5, appointment: 'a1'));
      expect(_figures(p.providers.single), (5.0, 1));

      p.addReviewLocally(_review(1, appointment: 'a1'));
      expect(_figures(p.providers.single), (1.0, 1));
    });
  });

  group('the favourites', () {
    test(
      'patchSalonFigures moves the favourite in place and says so once',
      () async {
        final a = _salon('A', rating: 4.5, reviewCount: 2);
        final b = _salon('B', rating: 3.9, reviewCount: 7);
        final c = _salon('C');
        hearts.salons = [b, a, c];
        final favorites = FavoritesProvider();
        await favorites.loadFavorites('user1');
        var notified = 0;
        favorites.addListener(() => notified++);

        favorites.patchSalonFigures('A', rating: 4.7, reviewCount: 3);

        expect(favorites.favoriteProviders.map((s) => s.id), ['B', 'A', 'C']);
        expect(_figures(favorites.favoriteProviders[1]), (4.7, 3));
        expect(favorites.favoriteProviders.first, same(b));
        expect(favorites.favoriteProviders.last, same(c));
        expect(favorites.favoriteProviderIds, ['B', 'A', 'C']);
        expect(favorites.isFavorite('A'), isTrue);
        expect(notified, 1);
        // What the home reads (`getFavoriteProviders`) is that same list.
        expect(_figures(favorites.getFavoriteProviders(const [])[1]), (4.7, 3));
      },
    );

    test('a salon that is no favourite, or figures already shown: nothing '
        'moves, nobody is told', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      hearts.salons = [a];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final held = favorites.favoriteProviders;
      var notified = 0;
      favorites.addListener(() => notified++);

      favorites.patchSalonFigures('Z', rating: 4.7, reviewCount: 3);
      favorites.patchSalonFigures('A', rating: 4.5, reviewCount: 2);

      expect(favorites.favoriteProviders, same(held));
      expect(favorites.favoriteProviders.single, same(a));
      expect(notified, 0);
    });

    test('they carry the same figures as the page and the list', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      salons.list = [a];
      hearts.salons = [a];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider();
      await p.loadProviders();
      p.showPreloaded(a);

      p.addReviewLocally(
        _review(5, appointment: 'a1'),
        alsoPatch: favorites.patchSalonFigures,
      );

      expect(_figures(p.selectedProvider!), (4.7, 3));
      expect(_figures(p.providers.single), (4.7, 3));
      expect(_figures(favorites.favoriteProviders.single), (4.7, 3));
    });

    test('with no salon page open, they move with the list', () async {
      final a = _salon('A', rating: 4.5, reviewCount: 2);
      salons.list = [a];
      hearts.salons = [a];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider();
      await p.loadProviders();

      p.addReviewLocally(
        _review(5, appointment: 'a1'),
        alsoPatch: favorites.patchSalonFigures,
      );

      expect(_figures(favorites.favoriteProviders.single), (4.7, 3));
    });
  });

  group('the re-read after « Publier »', () {
    // Three reviews stored 4,3 (4 + 4 + 5 = 13); a fourth, of 4 stars. The
    // server averages the stars — 17 / 4 = 4,25, « 4,3 » —, the app can only
    // start from the rounded « 4,3 »: (4,3 × 3 + 4) / 4 = 4,225, « 4,2 ».
    final before = _salon(
      'A',
      rating: 4.3,
      reviewCount: 3,
      reviews: [
        _review(5, appointment: 'x', id: 'x'),
        _review(4, appointment: 'y', id: 'y'),
        _review(4, appointment: 'z', id: 'z'),
      ],
    );
    final mine = _review(4, appointment: 'a1', id: 'client-uuid');
    final server = _salon(
      'A',
      rating: 4.3,
      reviewCount: 4,
      reviews: [
        _review(4, appointment: 'a1', id: 'stored-id'),
        ...before.reviews,
      ],
    );

    test('the server’s figures replace the estimate, on the page and in the '
        'lists — one read', () async {
      final gate = Completer<ApiResponse<Provider>>();
      salons
        ..list = [before]
        ..featured = [before]
        ..onById = (_) => gate.future;
      hearts.salons = [before];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider();
      await p.loadProviders();
      await p.loadFeaturedProviders();
      p.showPreloaded(before);

      expect(
        await p.submitReview(mine, alsoPatch: favorites.patchSalonFigures),
        isTrue,
      );
      expect(_figures(favorites.favoriteProviders.single), (4.2, 4));
      var notified = 0;
      p.addListener(() => notified++);
      gate.complete(ApiResponse.success(server));
      await pumpEventQueue();

      expect(salons.byIdCalls, 1);
      expect(notified, 1, reason: 'the page and the cards are told once');
      expect(p.selectedProvider, same(server));
      expect(_figures(p.providers.single), (4.3, 4));
      expect(_figures(p.featuredProviders.single), (4.3, 4));
      expect(_figures(favorites.favoriteProviders.single), (4.3, 4));
      // The stored id — the one « Signaler » must send.
      expect(p.selectedProvider!.reviews.first.id, 'stored-id');
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
    });

    test(
      '« Publier » does not wait for it: the estimate is shown first',
      () async {
        final gate = Completer<ApiResponse<Provider>>();
        salons.onById = (_) => gate.future;
        final p = ProviderProvider()..showPreloaded(before);

        final ok = await p
            .submitReview(mine)
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => fail('submitReview waited for the re-read'),
            );

        expect(ok, isTrue);
        expect(p.isSubmittingReview, isFalse);
        expect(salons.byIdCalls, 1, reason: 'the re-read is out');
        expect(_figures(p.selectedProvider!), (4.2, 4));
        expect(p.selectedProvider!.reviews.first.id, 'client-uuid');

        gate.complete(ApiResponse.success(server));
        await pumpEventQueue();
        expect(_figures(p.selectedProvider!), (4.3, 4));
      },
    );

    test('a refused read changes nothing and says nothing', () async {
      // A salon that stopped since: the public route answers 404.
      salons
        ..list = [before]
        ..onById = (_) async => ApiResponse.error(
          'Ce salon n’est plus disponible sur MyWeli.',
          code: 'not_found',
        );
      final p = ProviderProvider();
      await p.loadProviders();
      p.showPreloaded(before);
      final told = <(String, double, int)>[];

      expect(
        await p.submitReview(
          mine,
          alsoPatch: (id, {required rating, required reviewCount}) =>
              told.add((id, rating, reviewCount)),
        ),
        isTrue,
      );
      final shown = p.selectedProvider;
      final listed = p.providers.single;
      var notified = 0;
      p.addListener(() => notified++);
      await pumpEventQueue();

      expect(salons.byIdCalls, 1, reason: 'the re-read was sent');
      expect(p.selectedProvider, same(shown));
      expect(_figures(p.selectedProvider!), (4.2, 4));
      expect(p.providers.single, same(listed));
      expect(told, [('A', 4.2, 4)], reason: 'the estimate, and nothing after');
      expect(p.selectedProviderId, 'A');
      expect(p.error, isNull);
      expect(p.errorCode, isNull);
      expect(p.isLoading, isFalse);
      expect(notified, 0);
    });

    test('a read that throws changes nothing', () async {
      salons.onById = (_) async => throw Exception('SocketException');
      final p = ProviderProvider()..showPreloaded(before);

      expect(await p.submitReview(mine), isTrue);
      final shown = p.selectedProvider;
      await pumpEventQueue();

      expect(salons.byIdCalls, 1, reason: 'the re-read was sent');
      expect(p.selectedProvider, same(shown));
      expect(p.error, isNull);
      expect(p.errorCode, isNull);
    });

    test('the user moved to another salon: its page is not touched — the '
        'lists still take the answer', () async {
      final gate = Completer<ApiResponse<Provider>>();
      final other = _salon('B', rating: 3.9, reviewCount: 7);
      salons
        ..list = [before, other]
        ..onById = (_) => gate.future;
      final p = ProviderProvider();
      await p.loadProviders();
      p.showPreloaded(before);
      final told = <(String, double, int)>[];

      expect(
        await p.submitReview(
          mine,
          alsoPatch: (id, {required rating, required reviewCount}) =>
              told.add((id, rating, reviewCount)),
        ),
        isTrue,
      );
      expect(salons.byIdCalls, 1, reason: 'the re-read is out');
      // The map’s « Voir le salon », or any other salon page: the slot is B’s.
      p.showPreloaded(other);
      var notified = 0;
      p.addListener(() => notified++);

      gate.complete(ApiResponse.success(server));
      await pumpEventQueue();

      // A's answer never lands in B's slot…
      expect(p.selectedProvider, same(other));
      expect(p.selectedProviderId, 'B');
      expect(p.providers.last, same(other));
      // …and A's own rows, which are nobody else's, are corrected.
      expect(_figures(p.providers.first), (4.3, 4));
      expect(told, [
        ('A', 4.2, 4),
        ('A', 4.3, 4),
      ], reason: 'the estimate, then the server’s');
      expect(notified, 1, reason: 'the home cards are told to rebuild');
    });

    // Nothing in the app releases the slot (`clearSelectedProvider` has no
    // caller): once a salon page, the booking hub or a booking confirmation
    // was opened, that salon holds it for the rest of the session. A review
    // then published from « Mes rendez-vous » is of ANOTHER salon than the
    // slot's — the ordinary case, not a race.
    test('another salon was opened earlier in the session and still holds '
        'the slot: the lists and the favourites take the server’s '
        'figures', () async {
      final other = _salon('B', rating: 3.9, reviewCount: 7);
      salons
        ..list = [before, other]
        ..featured = [before]
        ..onById = (_) async => ApiResponse.success(server);
      hearts.salons = [before];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider();
      await p.loadProviders();
      await p.loadFeaturedProviders();
      p.showPreloaded(other);

      expect(
        await p.submitReview(mine, alsoPatch: favorites.patchSalonFigures),
        isTrue,
      );
      expect(_figures(p.providers.first), (4.2, 4), reason: 'the estimate');
      await pumpEventQueue();

      expect(salons.byIdCalls, 1);
      expect(_figures(p.providers.first), (4.3, 4));
      expect(_figures(p.featuredProviders.single), (4.3, 4));
      expect(_figures(favorites.favoriteProviders.single), (4.3, 4));
      expect(p.selectedProvider, same(other));
      expect(p.selectedProviderId, 'B');
    });

    test('…and a favourite held nowhere else leaves « Nouveau » on its first '
        'review', () async {
      // Another commune, past page 1 of the list: no copy to estimate from,
      // so the answer is the ONLY thing that can move this card — until the
      // app restarts, the favourites being loaded once per session.
      final unrated = _salon('A');
      salons.onById = (_) async => ApiResponse.success(
        _salon(
          'A',
          rating: 5.0,
          reviewCount: 1,
          reviews: [_review(5, appointment: 'a1', id: 'stored-id')],
        ),
      );
      hearts.salons = [unrated];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider()
        ..showPreloaded(_salon('B', rating: 3.9, reviewCount: 7));

      expect(
        await p.submitReview(
          _review(5, appointment: 'a1', id: 'client-uuid'),
          alsoPatch: favorites.patchSalonFigures,
        ),
        isTrue,
      );
      expect(favorites.favoriteProviders.single, same(unrated));
      await pumpEventQueue();

      expect(salons.byIdCalls, 1);
      expect(_figures(favorites.favoriteProviders.single), (5.0, 1));
      expect(p.selectedProviderId, 'B');
    });

    test('with no salon page open, the answer corrects the lists and takes '
        'no slot', () async {
      salons
        ..list = [before]
        ..onById = (_) async => ApiResponse.success(server);
      final p = ProviderProvider();
      await p.loadProviders();

      expect(await p.submitReview(mine), isTrue);
      await pumpEventQueue();

      expect(salons.byIdCalls, 1);
      expect(_figures(p.providers.single), (4.3, 4));
      expect(p.selectedProvider, isNull);
      expect(p.selectedProviderId, isNull);
    });

    test('a salon held only as a favourite — no page, in no list — gets no '
        'estimate: the answer alone moves it', () async {
      final gate = Completer<ApiResponse<Provider>>();
      salons.onById = (_) => gate.future;
      hearts.salons = [before];
      final favorites = FavoritesProvider();
      await favorites.loadFavorites('user1');
      final p = ProviderProvider();

      expect(
        await p.submitReview(mine, alsoPatch: favorites.patchSalonFigures),
        isTrue,
      );
      // No copy to count from here, so nothing was worked out.
      expect(favorites.favoriteProviders.single, same(before));

      gate.complete(ApiResponse.success(server));
      await pumpEventQueue();

      expect(_figures(favorites.favoriteProviders.single), (4.3, 4));
      expect(p.selectedProvider, isNull);
    });

    test('a second review sent while the first re-read is out: the first '
        'answer, older than what is shown, is dropped', () async {
      final first = Completer<ApiResponse<Provider>>();
      final second = Completer<ApiResponse<Provider>>();
      final gates = [first, second];
      salons.onById = (_) => gates.removeAt(0).future;
      final p = ProviderProvider()..showPreloaded(before);

      expect(await p.submitReview(mine), isTrue); // 4 stars
      expect(
        await p.submitReview(_review(1, appointment: 'a1', id: 'again')),
        isTrue,
      );
      // (4,2 × 4 − 4 + 1) / 4 = 3,45
      expect(p.selectedProvider!.reviews.first.id, 'again');
      expect(p.selectedProvider!.reviewCount, 4);
      final shown = p.selectedProvider;

      // The first read answers with the salon as it was BEFORE the second.
      first.complete(ApiResponse.success(server));
      await pumpEventQueue();
      expect(p.selectedProvider, same(shown));

      final later = server.copyWith(
        rating: 3.5,
        reviews: [
          _review(1, appointment: 'a1', id: 'stored-id'),
          ...before.reviews,
        ],
      );
      second.complete(ApiResponse.success(later));
      await pumpEventQueue();
      expect(p.selectedProvider, same(later));
      expect(salons.byIdCalls, 2);
    });

    test('a review the server refused is neither shown nor re-read', () async {
      reviews.refuse = true;
      final p = ProviderProvider()..showPreloaded(before);

      expect(await p.submitReview(mine), isFalse);
      await pumpEventQueue();

      expect(p.selectedProvider, same(before));
      expect(salons.byIdCalls, 0);
    });

    // The time limit runs on the test clock: `testWidgets` is the fake-async
    // zone this suite already uses.
    const limit = AppConstants.reviewRereadTimeout;

    testWidgets('an answer after the time limit is dropped', (tester) async {
      final gate = Completer<ApiResponse<Provider>>();
      salons.onById = (_) => gate.future;
      final p = ProviderProvider()..showPreloaded(before);

      expect(await p.submitReview(mine), isTrue);
      expect(salons.byIdCalls, 1, reason: 'the re-read is out');
      final shown = p.selectedProvider;
      await tester.pump(limit);

      gate.complete(ApiResponse.success(server));
      await tester.pump();

      expect(p.selectedProvider, same(shown));
      expect(_figures(p.selectedProvider!), (4.2, 4));
    });

    testWidgets('an answer just inside the time limit is taken', (
      tester,
    ) async {
      final gate = Completer<ApiResponse<Provider>>();
      salons.onById = (_) => gate.future;
      final p = ProviderProvider()..showPreloaded(before);

      expect(await p.submitReview(mine), isTrue);
      await tester.pump(limit - const Duration(milliseconds: 1));

      gate.complete(ApiResponse.success(server));
      await tester.pump();

      expect(p.selectedProvider, same(server));
    });
  });
}

(double, int) _figures(Provider salon) => (salon.rating, salon.reviewCount);

/// A salon as the API would send it — `provider1`’s document under another
/// id, with the figures and the embedded reviews a case needs.
Provider _salon(
  String id, {
  double rating = 0,
  int reviewCount = 0,
  List<Review> reviews = const [],
}) => MockData.providers
    .firstWhere((p) => p.id == 'provider1')
    .copyWith(
      id: id,
      rating: rating,
      reviewCount: reviewCount,
      reviews: reviews,
    );

Review _review(
  int stars, {
  String appointment = '',
  String id = 'r',
  String salon = 'A',
}) => Review(
  id: id,
  appointmentId: appointment,
  providerId: salon,
  userId: 'user1',
  userName: 'Awa K.',
  rating: stars,
  text: 'Très bien',
  serviceName: 'Brushing',
  createdAt: DateTime(2026, 10, 13),
);

/// The public salon reads, scripted per test.
class _Salons implements ProviderServiceInterface {
  List<Provider> list = const [];
  List<Provider> featured = const [];

  /// What `GET /providers/{id}` answers. Unset: the salon is unreachable.
  Future<ApiResponse<Provider>> Function(String id)? onById;
  int byIdCalls = 0;

  @override
  Future<ApiResponse<Provider>> getProviderById(String id) {
    byIdCalls++;
    final answer = onById;
    if (answer == null) {
      return Future.value(ApiResponse.error('non scripté', code: 'network'));
    }
    return answer(id);
  }

  @override
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async => ApiResponse.success(List.of(list));

  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() async =>
      ApiResponse.success(List.of(featured));

  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) async => ApiResponse.success(List.of(list));
}

/// `GET /me/favorites`, hydrated.
class _Favorites implements FavoritesServiceInterface {
  List<Provider> salons = const [];

  @override
  Future<ApiResponse<List<Provider>>> getFavoriteProviders(
    String userId,
  ) async => ApiResponse.success(List.of(salons));

  @override
  Future<ApiResponse<List<String>>> getFavoriteProviderIds(
    String userId,
  ) async => ApiResponse.success([for (final s in salons) s.id]);

  @override
  Future<ApiResponse<bool>> addFavorite(
    String userId,
    String providerId,
  ) async => ApiResponse.success(true);

  @override
  Future<ApiResponse<bool>> removeFavorite(
    String userId,
    String providerId,
  ) async => ApiResponse.success(true);

  @override
  Future<ApiResponse<bool>> isFavorite(
    String userId,
    String providerId,
  ) async => ApiResponse.success(salons.any((s) => s.id == providerId));
}

/// `POST /appointments/{id}/review`: the 201 is the review, and nothing of
/// the salon.
class _Reviews implements ReviewServiceInterface {
  bool refuse = false;

  @override
  Future<ApiResponse<Review>> submitReview(Review review) async => refuse
      ? ApiResponse.error('Ce rendez-vous n’est pas terminé.')
      : ApiResponse.success(review);

  @override
  Future<ApiResponse<List<Review>>> getProviderReviews(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async => ApiResponse.success(const []);

  @override
  Future<ApiResponse<void>> reportReview(
    String reviewId, {
    String? reason,
  }) async => ApiResponse.success(null);
}
