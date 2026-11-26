import '../../core/constants/app_constants.dart';
import '../../core/constants/failure_messages.dart';
import '../../core/utils/salon_id.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/search_text.dart';
import '../../models/api_response.dart';
import '../../models/provider.dart';
import '../../models/provider_page.dart';
import '../interfaces/provider_service_interface.dart';
import 'mock_data.dart';
import 'mock_search_fold.dart';

class MockProviderService implements ProviderServiceInterface {
  /// [salons]: the salons this mock serves — [MockData.providers] by default;
  /// `const []` is the launch's « no salon is public yet » (§2.10).
  /// [failSearches]: every list read answers « Pas de connexion », for the
  /// error states.
  MockProviderService({this._salons, this.failSearches = false});

  final List<Provider>? _salons;
  final bool failSearches;

  List<Provider> get _source => _salons ?? MockData.providers;

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
    final res = await searchProviders(
      ProviderQuery(
        text: searchQuery ?? '',
        category: category,
        commune: commune,
        sort: sort,
        availableToday: availableToday,
        page: page,
        pageSize: limit,
      ),
    );
    final data = res.data;
    if (res.success && data != null) return ApiResponse.success(data.items);
    return ApiResponse(success: false, error: res.error, code: res.code);
  }

  /// `GET /providers` as A4-api answers it (docs/design/consumer-search.md
  /// §3): the text matched in the name, the description, the address, the
  /// commune and the active services' names, each on its own, case and
  /// accents ignored ([kMockSearchFold] is the server's `unaccent` over
  /// Latin), white space collapsed on both sides; the page and the page size
  /// clamped as the server clamps them; every order ending on the id.
  @override
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query) async {
    await Future.delayed(AppConstants.mockDelay);
    if (failSearches) {
      return ApiResponse.error(kNoConnectionMessage, code: 'network');
    }

    var providers = List<Provider>.from(_source);

    final category = query.category;
    if (category != null && category.isNotEmpty) {
      providers = providers.where((p) => p.category == category).toList();
    }

    final commune = query.commune;
    if (commune != null && commune.isNotEmpty) {
      providers = providers.where((p) => p.commune == commune).toList();
    }

    final needle = mockFoldSearchText(cleanSearchText(query.text));
    if (needle.isNotEmpty) {
      providers = providers.where((p) => _matches(p, needle)).toList();
    }

    // Filter: available today (FR-DISC-007). Cheap proxy for the slot engine —
    // open on today's weekday and not blocked today.
    if (query.availableToday) {
      providers = providers.where(_openToday).toList();
    }

    // Sort (FR-DISC-007). « Mieux notés » and « Prix » end on the id, as the
    // server's `sortProviders` does. Relevance is the SEED order: the server's
    // is `featured DESC, rating DESC, id`, and a `Provider` carries no
    // `featured` flag to reproduce it with — the seed order is at least
    // stable between two pages.
    int byId(Provider a, Provider b) => a.id.compareTo(b.id);
    switch (query.sort) {
      case ProviderSort.rating:
        providers.sort((a, b) {
          final r = b.rating.compareTo(a.rating);
          return r != 0 ? r : byId(a, b);
        });
      case ProviderSort.price:
        providers.sort((a, b) {
          final r = _minPrice(a).compareTo(_minPrice(b));
          return r != 0 ? r : byId(a, b);
        });
      case ProviderSort.relevance:
        break;
    }

    // Pagination, clamped as `backend/routes/providers/index.dart` clamps.
    final page = query.page.clamp(1, 100000);
    final pageSize = query.pageSize.clamp(1, kMapSalonPageSize);
    final start = (page - 1) * pageSize;
    final items = providers.length > start
        ? providers.sublist(
            start,
            (start + pageSize).clamp(0, providers.length),
          )
        : <Provider>[];

    return ApiResponse.success(
      ProviderPage(
        items: items,
        page: page,
        pageSize: pageSize,
        total: providers.length,
      ),
    );
  }

  bool _matches(Provider p, String needle) {
    bool holds(String? field) =>
        field != null && mockFoldSearchText(field).contains(needle);
    return holds(p.name) ||
        holds(p.description) ||
        holds(p.address) ||
        holds(p.commune) ||
        p.services.any((s) => s.active && holds(s.name));
  }

  /// Cheap "open today" proxy for the mock: open on THIS salon's today
  /// (weekday 0=Mon, in its own timezone) and not blocked today. (The API
  /// uses the real slot engine.)
  bool _openToday(Provider p) {
    final today = salonToday(tz: p.timezone);
    final blocked = p.availability.blockedDates.any(
      (d) =>
          d.year == today.year && d.month == today.month && d.day == today.day,
    );
    if (blocked) return false;
    final slots = p.availability.weeklySchedule[today.weekday - 1] ?? const [];
    return slots.any((s) => s.isAvailable);
  }

  /// Lowest active service price; `infinity` when none (sorts such salons last).
  double _minPrice(Provider p) {
    final prices = p.services.where((s) => s.active).map((s) => s.price);
    return prices.isEmpty
        ? double.infinity
        : prices.reduce((a, b) => a < b ? a : b);
  }

  @override
  Future<ApiResponse<Provider>> getProviderById(SalonId id) async {
    await Future.delayed(AppConstants.mockDelay);

    try {
      final provider = _source.firstWhere((p) => p.id == id);
      final providerReviews =
          MockData.reviews.where((r) => r.providerId == id).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ApiResponse.success(provider.copyWith(reviews: providerReviews));
    } catch (e) {
      return ApiResponse.error(
        'Ce salon n’est plus disponible sur MyWeli.',
        code: 'not_found',
      );
    }
  }

  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() async {
    await Future.delayed(AppConstants.mockDelay);

    // Return top 3 rated providers
    final featured = List<Provider>.from(_source)
      ..sort((a, b) => b.rating.compareTo(a.rating));

    return ApiResponse.success(featured.take(3).toList());
  }

  @override
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  }) async {
    await Future.delayed(AppConstants.mockDelay);

    // For mock, just return all providers
    // In real app, would calculate distance and sort
    return ApiResponse.success(_source);
  }
}

/// [text] folded as the server's `lower(unaccent(…))` folds it (the mock's
/// table is the server's, over Latin): white space collapsed, each character
/// through [kMockSearchFold], then lower case — in that order, the
/// database's.
String mockFoldSearchText(String text) {
  final collapsed = text.replaceAll(_mockSpaces, ' ');
  final out = StringBuffer();
  for (final rune in collapsed.runes) {
    final folded = kMockSearchFold[rune];
    if (folded == null) {
      out.writeCharCode(rune);
    } else {
      out.write(folded);
    }
  }
  return out.toString().toLowerCase();
}

final _mockSpaces = RegExp(
  r'[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+',
);
