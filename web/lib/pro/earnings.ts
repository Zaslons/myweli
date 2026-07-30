/// Pure helpers for the pro « Revenus » page (parity 9.1). Unit-tested.
/// Periods mirror the app's earnings_screen: today · Monday-start week ·
/// calendar month · all time (no range).

import { salonDayRange } from '../time';

export type PeriodKey = 'today' | 'week' | 'month' | 'all';

export const PERIODS: { key: PeriodKey; label: string }[] = [
  { key: 'today', label: 'Aujourd’hui' },
  { key: 'week', label: 'Semaine' },
  { key: 'month', label: 'Mois' },
  { key: 'all', label: 'Tout' },
];

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

/// Inclusive-start/exclusive-end range for a period, or null for all time.
/// Boundaries are SALON days (lib/time.ts) — the old device-local midnight
/// math put « Aujourd'hui » in the viewer's day, not the salon's.
export function periodRange(
  key: PeriodKey,
  now: Date = new Date(),
  tz?: string,
): { startDate: string; endDate: string } | null {
  return salonDayRange(key, now, tz);
}
