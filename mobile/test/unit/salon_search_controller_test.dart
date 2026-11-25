import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_page.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/providers/salon_search_controller.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// docs/design/consumer-search.md §8, « A4 (app) — Unit »: the list's own
/// search state.
class _Scripted implements ProviderServiceInterface {
  final asked = <ProviderQuery>[];
  final answers = <Completer<ApiResponse<ProviderPage>>>[];
  final nearby =
      <
        ({
          String? category,
          String? searchQuery,
          String? commune,
          ProviderSort sort,
          bool availableToday,
        })
      >[];
  List<Provider> nearbySalons = const [];

  /// Answers the [i]-th search asked.
  void answer(int i, ApiResponse<ProviderPage> res) => answers[i].complete(res);

  @override
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query) {
    asked.add(query);
    final c = Completer<ApiResponse<ProviderPage>>();
    answers.add(c);
    return c.future;
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
  }) async {
    nearby.add((
      category: category,
      searchQuery: searchQuery,
      commune: commune,
      sort: sort,
      availableToday: availableToday,
    ));
    return ApiResponse.success(nearbySalons);
  }

  @override
  Future<ApiResponse<Provider>> getProviderById(SalonId id) async =>
      ApiResponse.error('gone', code: 'not_found');
  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() async =>
      ApiResponse.success(const []);
  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) async => ApiResponse.success(const []);
}

Provider _salon(String id, {double rating = 4, int reviewCount = 2}) =>
    MockData.providers.first.copyWith(
      id: SalonId(id),
      name: 'Salon $id',
      rating: rating,
      reviewCount: reviewCount,
    );

ApiResponse<ProviderPage> _page(
  List<String> ids, {
  int page = 1,
  int pageSize = 20,
  int? total,
}) => ApiResponse.success(
  ProviderPage(
    items: [for (final id in ids) _salon(id)],
    page: page,
    pageSize: pageSize,
    total: total ?? ids.length,
  ),
);

List<String> _ids(SalonSearchController c) => [
  for (final p in c.items ?? const <Provider>[]) p.id,
];

void main() {
  // `providerService` is a `late final`: set once for the file, emptied
  // before each test.
  final service = _Scripted();
  late ProviderProvider providers;
  late SalonSearchController c;

  setUpAll(() => serviceLocator.providerService = service);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service
      ..asked.clear()
      ..answers.clear()
      ..nearby.clear()
      ..nearbySalons = const [];
    providers = ProviderProvider();
  });

  SalonSearchController open({String? category}) =>
      c = SalonSearchController(providers: providers, category: category);

  /// Opened, its first search answered with [ids].
  Future<SalonSearchController> opened(
    WidgetTester tester, {
    List<String> ids = const ['a', 'b'],
    String? category,
  }) async {
    open(category: category);
    service.answer(0, _page(ids));
    await tester.pump();
    return c;
  }

  tearDown(() {
    try {
      c.dispose();
    } catch (_) {
      // already disposed by the test
    }
  });

  group('the first search', () {
    testWidgets('one, at once: no text, the screen\'s category, the '
        'shared commune, page 1', (tester) async {
      await providers.setCommune('Cocody');
      open(category: 'nails');
      expect(
        service.asked.single,
        const ProviderQuery(category: 'nails', commune: 'Cocody'),
      );
      expect(c.isLoading, isTrue);
      expect(c.items, isNull, reason: 'null until the first answer');
      service.answer(0, _page(['a']));
      await tester.pump();
      expect(_ids(c), ['a']);
      expect(c.isLoading, isFalse);
      expect(c.answers, 1);
    });
  });

  group('typing (§2.3)', () {
    testWidgets('350 ms after the last key, not before', (tester) async {
      await opened(tester);
      c.onTextChanged('tr');
      await tester.pump(const Duration(milliseconds: 349));
      expect(service.asked, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(service.asked, hasLength(2));
      expect(service.asked.last.text, 'tr');
    });

    testWidgets('each key restarts the wait: one request per pause', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tr');
      await tester.pump(const Duration(milliseconds: 200));
      c.onTextChanged('tre');
      await tester.pump(const Duration(milliseconds: 200));
      c.onTextChanged('tres');
      await tester.pump(const Duration(milliseconds: 349));
      expect(service.asked, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect([for (final q in service.asked) q.text], ['', 'tres']);
    });

    testWidgets('one letter asks nothing, says why, and keeps the results', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged(' t ');
      expect(c.needsMoreLetters, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(service.asked, hasLength(1));
      expect(_ids(c), ['a', 'b']);
      await c.submit();
      expect(service.asked, hasLength(1), reason: 'not even « Rechercher »');
    });

    testWidgets('the keyboard\'s « Rechercher » searches at once', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      unawaited(c.submit());
      expect(service.asked.last.text, 'tresses');
      await tester.pump(const Duration(seconds: 1));
      expect(service.asked, hasLength(2), reason: 'the wait was cancelled');
    });

    testWidgets('emptying the field searches at once, without text', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      service.answer(1, _page(['t']));
      await tester.pump();
      c.onTextChanged('');
      expect(service.asked, hasLength(3));
      expect(service.asked.last.text, '');
    });

    testWidgets('emptying a field that never searched asks nothing', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('t');
      c.onTextChanged('');
      await tester.pump(const Duration(seconds: 1));
      expect(service.asked, hasLength(1));
    });

    testWidgets('the text is cleaned before it is sent', (tester) async {
      await opened(tester);
      c.onTextChanged('  tresses\t\u0001cocody  ');
      await tester.pump(kSearchDebounce);
      expect(service.asked.last.text, 'tresses cocody');
    });

    testWidgets('only the latest search writes the list', (tester) async {
      await opened(tester);
      c.onTextChanged('tre');
      await tester.pump(kSearchDebounce);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      service.answer(2, _page(['tresses']));
      await tester.pump();
      service.answer(1, _page(['tre']));
      await tester.pump();
      expect(_ids(c), ['tresses']);
      expect(c.shown!.text, 'tresses');
      expect(c.isLoading, isFalse);
    });

    testWidgets('the results stay while a new search is out', (tester) async {
      await opened(tester);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      expect(c.isLoading, isTrue);
      expect(c.isSearchingAgain, isTrue);
      expect(_ids(c), ['a', 'b']);
    });
  });

  group('« Afficher plus de salons » (§2.6)', () {
    testWidgets('page × 20 < total, appended without a salon twice', (
      tester,
    ) async {
      open();
      service.answer(0, _page([for (var i = 0; i < 20; i++) 's$i'], total: 25));
      await tester.pump();
      expect(c.hasMore, isTrue);
      expect(c.canLoadMore, isTrue);

      unawaited(c.loadMore());
      expect(c.isLoadingMore, isTrue);
      expect(service.asked.last.page, 2);
      service.answer(
        1,
        _page(['s19', 's20', 's21', 's22', 's23', 's24'], page: 2, total: 25),
      );
      await tester.pump();
      expect(c.items, hasLength(25), reason: 's19 is not shown twice');
      expect(c.hasMore, isFalse);
      expect(c.total, 25);
    });

    testWidgets('the next page carries the same search', (tester) async {
      await providers.setCommune('Marcory');
      open(category: 'spa');
      service.answer(0, _page(['a'], total: 30));
      await tester.pump();
      unawaited(c.setSort(ProviderSort.rating));
      service.answer(1, _page(['a'], total: 30));
      await tester.pump();
      unawaited(c.loadMore());
      expect(
        service.asked.last,
        const ProviderQuery(
          category: 'spa',
          commune: 'Marcory',
          sort: ProviderSort.rating,
          page: 2,
        ),
      );
    });

    testWidgets('a failed page keeps the salons shown and says so', (
      tester,
    ) async {
      open();
      service.answer(0, _page(['a', 'b'], total: 30));
      await tester.pump();
      unawaited(c.loadMore());
      service.answer(1, ApiResponse.error(kNoConnectionMessage));
      await tester.pump();
      expect(_ids(c), ['a', 'b']);
      expect(c.moreError, kNoConnectionMessage);
      expect(c.error, isNull);
      expect(c.isLoadingMore, isFalse);
      expect(c.canLoadMore, isTrue, reason: '« Réessayer » asks again');
    });

    testWidgets('a page answered for an older search is dropped', (
      tester,
    ) async {
      open();
      service.answer(0, _page(['a', 'b'], total: 30));
      await tester.pump();
      unawaited(c.loadMore());
      unawaited(c.selectCategory('nails'));
      expect(c.isLoadingMore, isFalse, reason: 'the new search owns the list');
      expect(c.canLoadMore, isFalse, reason: 'off while a new search is out');
      service.answer(1, _page(['old'], page: 2, total: 30));
      await tester.pump();
      expect(_ids(c), ['a', 'b']);
      service.answer(2, _page(['n']));
      await tester.pump();
      expect(_ids(c), ['n']);
    });
  });

  group('chips and filters narrow the same search', () {
    testWidgets('the text stays; the lit chip again removes it', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      unawaited(c.selectCategory('nails'));
      expect(service.asked.last.text, 'tresses');
      expect(service.asked.last.category, 'nails');
      unawaited(c.selectCategory('nails'));
      expect(service.asked.last.category, isNull);
      unawaited(c.selectCategory('spa'));
      unawaited(c.selectCategory(null));
      expect(service.asked.last.category, isNull, reason: '« Tous »');
    });

    testWidgets('a chip during the wait searches the field, not the old text', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      unawaited(c.selectCategory('salon'));
      expect(service.asked.last.text, 'tresses');
      await tester.pump(const Duration(seconds: 1));
      expect(service.asked, hasLength(2), reason: 'the wait was cancelled');
    });

    testWidgets('sort and « Disponible aujourd’hui » last the session, on the '
        'list only (decision 236)', (tester) async {
      await opened(tester);
      unawaited(c.setSort(ProviderSort.price));
      unawaited(c.setAvailableToday(true));
      expect(service.asked.last.sort, ProviderSort.price);
      expect(service.asked.last.availableToday, isTrue);
      c.dispose();

      final again = SalonSearchController(providers: providers);
      addTearDown(again.dispose);
      expect(service.asked.last.sort, ProviderSort.price);
      expect(service.asked.last.availableToday, isTrue);
      expect(again.sort, ProviderSort.price);
    });

    testWidgets('a pull during the wait cancels it and searches the field', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('manucure');
      unawaited(c.refresh());
      expect(service.asked.last.text, 'manucure');
      await tester.pump(const Duration(seconds: 1));
      expect(service.asked, hasLength(2));
    });
  });

  group('failures', () {
    testWidgets('a new search that failed does not leave the old salons', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      service.answer(1, ApiResponse.error(kNoConnectionMessage));
      await tester.pump();
      expect(c.error, kNoConnectionMessage);
      expect(c.items, isEmpty);
      expect(c.total, 0);
    });

    testWidgets('the same search pulled again and failed keeps them', (
      tester,
    ) async {
      await opened(tester);
      unawaited(c.refresh());
      service.answer(1, ApiResponse.error(kNoConnectionMessage));
      await tester.pump();
      expect(_ids(c), ['a', 'b']);
    });

    testWidgets('a thrown read is the generic sentence', (tester) async {
      open();
      service.answers[0].completeError(StateError('boom'));
      await tester.pump();
      expect(c.error, kGenericErrorMessage);
    });
  });

  group('the shared commune (§2.7)', () {
    testWidgets('a commune change searches again, the text kept', (
      tester,
    ) async {
      await opened(tester);
      c.onTextChanged('tresses');
      await tester.pump(kSearchDebounce);
      service.answer(1, _page(['t']));
      await tester.pump();
      await providers.setCommune('Yopougon');
      expect(service.asked.last.commune, 'Yopougon');
      expect(service.asked.last.text, 'tresses');
    });

    testWidgets('a salon read — a notification, the commune unchanged — '
        'does NOT', (tester) async {
      await opened(tester);
      await providers.loadProviderById(SalonId('a'));
      await providers.loadProviders();
      providers.clearSelectedProvider();
      expect(service.asked, hasLength(1));
    });
  });

  group('the other copies of a salon (§2.7)', () {
    testWidgets('providerForMap finds a salon held only by the search', (
      tester,
    ) async {
      await opened(tester, ids: ['only-here']);
      final found = await providers.providerForMap(SalonId('only-here'));
      expect(found?.id, 'only-here');
    });

    testWidgets('a review\'s figures reach a card in an open search', (
      tester,
    ) async {
      await opened(tester, ids: ['a']);
      var notified = 0;
      c.addListener(() => notified++);
      providers.addReviewLocally(
        Review(
          id: 'r1',
          providerId: SalonId('a'),
          userId: 'u1',
          userName: 'Awa',
          rating: 5,
          text: 'Très bien',
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      final card = c.items!.single;
      expect(card.reviewCount, 3);
      expect(card.rating, greaterThan(4));
      expect(notified, 1);
    });

    testWidgets('closed, it is no longer a copy', (tester) async {
      await opened(tester, ids: ['gone-with-it']);
      c.dispose();
      final found = await providers.providerForMap(SalonId('gone-with-it'));
      expect(found, isNull, reason: 'the network read answered 404');
    });
  });

  group('closed while a read is out', () {
    testWidgets('the answer is dropped, nothing notifies, no wait fires', (
      tester,
    ) async {
      open();
      c.onTextChanged('tresses');
      var notified = 0;
      c.addListener(() => notified++);
      c.dispose();
      service.answer(0, _page(['a']));
      await tester.pump(const Duration(seconds: 1));
      expect(notified, 0);
      expect(service.asked, hasLength(1));
      await providers.setCommune('Cocody');
      expect(service.asked, hasLength(1), reason: 'no longer listening');
    });
  });

  group('ProviderProvider, once the list has its own state', () {
    testWidgets('the home\'s « Près de vous » never takes the list\'s '
        'category, sort or filter', (tester) async {
      await providers.setCommune('Cocody');
      await opened(tester, category: 'barber');
      unawaited(c.setSort(ProviderSort.rating));
      unawaited(c.setAvailableToday(true));
      await providers.loadProviders();
      final last = service.nearby.last;
      expect(last.category, isNull);
      expect(last.searchQuery, isNull);
      expect(last.sort, ProviderSort.relevance);
      expect(last.availableToday, isFalse);
      expect(last.commune, 'Cocody');
    });

    testWidgets('no list read writes the salon page\'s isLoading or error', (
      tester,
    ) async {
      service.nearbySalons = const [];
      await providers.loadProviderById(SalonId('missing'));
      expect(providers.error, isNotNull);
      final pageError = providers.error;
      await providers.loadProviders();
      await providers.loadFeaturedProviders();
      expect(providers.error, pageError);
      expect(providers.isLoading, isFalse);

      providers.beginProviderLoad();
      await providers.loadProviders();
      await providers.loadFeaturedProviders();
      expect(providers.isLoading, isTrue, reason: 'the page\'s read is out');
    });

    testWidgets('noPublicSalon: the featured read answered with nothing', (
      tester,
    ) async {
      expect(providers.noPublicSalon, isFalse, reason: 'not answered yet');
      await providers.loadFeaturedProviders();
      expect(providers.noPublicSalon, isTrue);
    });

    testWidgets('the map reads 50 of the commune, with the total', (
      tester,
    ) async {
      await providers.setCommune('Cocody');
      unawaited(providers.loadMapSalons());
      expect(
        service.asked.last,
        const ProviderQuery(commune: 'Cocody', pageSize: 50),
      );
      expect(providers.mapLoading, isTrue);
      service.answer(0, _page(['m1', 'm2'], pageSize: 50, total: 63));
      await tester.pump();
      expect([for (final p in providers.mapSalons!) p.id], ['m1', 'm2']);
      expect(providers.mapTotal, 63);
      expect(providers.mapCommune, 'Cocody');
    });

    testWidgets('a failed map read empties the map, and says so', (
      tester,
    ) async {
      unawaited(providers.loadMapSalons());
      service.answer(0, _page(['m1'], pageSize: 50));
      await tester.pump();
      unawaited(providers.loadMapSalons());
      service.answer(1, ApiResponse.error(kNoConnectionMessage));
      await tester.pump();
      expect(providers.mapSalons, isEmpty);
      expect(providers.mapError, kNoConnectionMessage);
    });

    testWidgets('only the last map read is shown', (tester) async {
      unawaited(providers.loadMapSalons());
      unawaited(providers.loadMapSalons());
      service.answer(1, _page(['new'], pageSize: 50));
      await tester.pump();
      service.answer(0, _page(['old'], pageSize: 50));
      await tester.pump();
      expect([for (final p in providers.mapSalons!) p.id], ['new']);
    });
  });
}
