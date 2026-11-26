import 'package:equatable/equatable.dart';

import '../../core/utils/salon_id.dart';
import '../../models/api_response.dart';
import '../../models/provider.dart';
import '../../models/provider_page.dart';

/// Discovery sort options (FR-DISC-007). `relevance` = featured + rating (the
/// default); `name` is the wire value sent to `GET /providers?sort=`.
enum ProviderSort {
  relevance('relevance', 'Pertinence'),
  rating('rating', 'Mieux notés'),
  price('price', 'Prix croissant');

  const ProviderSort(this.query, this.label);
  final String query;
  final String label;
}

/// Salons per page on the list (§2.6): the server's default.
const kSalonPageSize = 20;

/// Salons on the map (§2.8): the server's largest page.
const kMapSalonPageSize = 50;

/// One search over the public salons (docs/design/consumer-search.md §3):
/// what `GET /providers` is asked. [text] goes as `q`, already cleaned
/// (`cleanSearchText`); empty is no text.
class ProviderQuery extends Equatable {
  const ProviderQuery({
    this.text = '',
    this.category,
    this.commune,
    this.sort = ProviderSort.relevance,
    this.availableToday = false,
    this.page = 1,
    this.pageSize = kSalonPageSize,
  });

  final String text;
  final String? category;
  final String? commune;
  final ProviderSort sort;
  final bool availableToday;
  final int page;
  final int pageSize;

  /// The same search, one page further.
  ProviderQuery nextPage() => ProviderQuery(
    text: text,
    category: category,
    commune: commune,
    sort: sort,
    availableToday: availableToday,
    page: page + 1,
    pageSize: pageSize,
  );

  @override
  List<Object?> get props => [
    text,
    category,
    commune,
    sort,
    availableToday,
    page,
    pageSize,
  ];
}

abstract class ProviderServiceInterface {
  /// The featured carousel and the home's « Près de vous » (§3: « stays …
  /// until a later cleanup »). The page's `total` is dropped here.
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  });

  /// The salon list and the map (§3): one page, with the server's `total`.
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query);
  Future<ApiResponse<Provider>> getProviderById(SalonId id);
  Future<ApiResponse<List<Provider>>> getFeaturedProviders();
  Future<ApiResponse<List<Provider>>> getNearbyProviders({
    double? latitude,
    double? longitude,
  });
}
