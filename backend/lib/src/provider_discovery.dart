import 'dart:math';

/// Discovery sort (FR-DISC-007). Pure + repo-agnostic so it's unit-testable and
/// composes in the route over the full matched set. Design:
/// docs/design/discovery-sort-filter.md.
///
/// - `rating` → rating desc.
/// - `price`  → min **active** service price asc; salons with no priced service last.
/// - anything else (incl. `relevance`/null) → unchanged (the repo's
///   featured + rating + id order).
///
/// Every order ends on the id (docs/design/consumer-search.md §3, A4-api):
/// equal salons never swap places between two pages. Dart's sort is not
/// stable, so without it their order is whatever the algorithm leaves.
List<Map<String, dynamic>> sortProviders(
  List<Map<String, dynamic>> providers,
  String? sort,
) {
  switch (sort) {
    case 'rating':
      return [...providers]..sort((a, b) {
        final r = ((b['rating'] as num?) ?? 0).compareTo(
          (a['rating'] as num?) ?? 0,
        );
        return r != 0 ? r : _byId(a, b);
      });
    case 'price':
      return [...providers]..sort((a, b) {
        final p = _minPrice(a).compareTo(_minPrice(b));
        return p != 0 ? p : _byId(a, b);
      });
    default:
      return providers;
  }
}

/// The tiebreak: id order, as Postgres's `id COLLATE "C"`.
int _byId(Map<String, dynamic> a, Map<String, dynamic> b) =>
    ((a['id'] as String?) ?? '').compareTo((b['id'] as String?) ?? '');

/// Lowest active service price for a provider; `infinity` when it has none (so
/// such salons sort last under price-asc).
double _minPrice(Map<String, dynamic> provider) {
  final services = (provider['services'] as List?) ?? const [];
  var best = double.infinity;
  for (final s in services) {
    if (s is! Map) continue;
    if (s['active'] == false) continue;
    final price = (s['price'] as num?)?.toDouble();
    if (price != null) best = min(best, price);
  }
  return best;
}
