'use client';

import type { RevenueAxis } from '../../lib/pro/revenue';
import { RevenueAnalyticsView } from './revenue/RevenueAnalyticsView';

/// One row of « Revenus » — a collaborateur, a prestation or a canal
/// (docs/design/pro-revenue-analytics.md §4.8, §5.2, §5.4): the same figures,
/// chart and breakdowns for that row only, with the other axes as tabs.
export function RevenueDetailClient({
  axis,
  filterKey,
}: {
  axis: RevenueAxis;
  filterKey: string;
}) {
  // Another row is another page: nothing of the last one carries over.
  return <RevenueAnalyticsView key={`${axis}:${filterKey}`} axis={axis} filterKey={filterKey} />;
}
