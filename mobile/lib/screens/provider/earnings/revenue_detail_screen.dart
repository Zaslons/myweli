import 'package:flutter/widgets.dart';

import '../../../models/revenue_analytics.dart';
import 'revenue_screen.dart';

/// One row of « Répartition », opened (docs/design/pro-revenue-analytics.md
/// §4.8): the same period bar (inherited from the link, then free), the
/// figures, « Évolution » and « Répartition » for that row only — the OTHER
/// axes, whose rows do not drill further (one level on a phone) — and its
/// bookings.
///
/// Routes: `/pro/earnings/collaborateur/:artistId` (`none` = « Sans
/// collaborateur attribué »), `/pro/earnings/prestation/:serviceId`,
/// `/pro/earnings/canal/:channel` — the period in the query, so Back returns
/// to the same period.
class RevenueDetailScreen extends StatelessWidget {
  const RevenueDetailScreen({
    super.key,
    required this.axis,
    required this.rowKey,
    this.routeQuery = const {},
  });

  final RevenueAxis axis;

  /// The artistId (or `none`), serviceId or channel.
  final String rowKey;
  final Map<String, String> routeQuery;

  @override
  Widget build(BuildContext context) => RevenueAnalyticsPage(
    viewKey: '${axis.name}:$rowKey',
    routeQuery: routeQuery,
    filterAxis: axis,
    filterKey: rowKey,
    // The bar names the kind of row; its name is the page's heading.
    fallbackTitle: switch (axis) {
      RevenueAxis.artist => 'Collaborateur',
      RevenueAxis.service => 'Prestation',
      RevenueAxis.channel => 'Canal',
    },
  );
}
