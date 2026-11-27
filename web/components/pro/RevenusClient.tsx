'use client';

import { RevenueAnalyticsView } from './revenue/RevenueAnalyticsView';

/// « Revenus » — the salon's revenue analytics on the website
/// (docs/design/pro-revenue-analytics.md §5, R4): one period and its
/// comparison, the figures, « Évolution », the revenue by collaborateur,
/// prestation and canal (each row opening its detail), the latest completed
/// bookings. Owner only (`finances.view`, checked by the server). The app's
/// twin is `revenue_screen.dart`.
export function RevenusClient() {
  return <RevenueAnalyticsView />;
}
