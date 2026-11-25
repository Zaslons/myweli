import 'package:equatable/equatable.dart';

import 'provider.dart';

/// One page of `GET /providers`: `{items, page, pageSize, total}`
/// (docs/design/consumer-search.md §3). `total` counts every salon the
/// search matches, not the ones on this page — the count a person reads
/// (« 42 salons »), and what says whether « Afficher plus » has more.
class ProviderPage extends Equatable {
  const ProviderPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<Provider> items;
  final int page;
  final int pageSize;
  final int total;

  /// More salons than the pages up to this one hold (§2.6).
  bool get hasMore => page * pageSize < total;

  @override
  List<Object?> get props => [items, page, pageSize, total];
}
