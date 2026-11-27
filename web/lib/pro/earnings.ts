/// The salon's realized-earnings ledger as `GET /providers/{id}/earnings`
/// answers it — read by the salon's data export (« Exporter mes données »,
/// lib/pro/export.ts). The « Revenus » page reads the analytics endpoints
/// instead (docs/design/pro-revenue-analytics.md §5, R4), and with it the
/// old period chips and « Tout » left (Q8).

export type EarningsData = {
  totalEarnings: number;
  /// ISO-4217, stamped by the backend from the salon's market (multi-pays
  /// MP1); absent on pre-MP1 payloads → the formatter's XOF fallback.
  currency?: string | null;
  transactions: {
    id: string;
    appointmentId: string;
    amount: number;
    date: string;
    status: string;
    currency?: string | null;
  }[];
};
