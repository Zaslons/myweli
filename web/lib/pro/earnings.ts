/// Pure helpers for the pro « Revenus » page (parity 9.1). Unit-tested.
/// Periods mirror the app's earnings_screen: today · Monday-start week ·
/// calendar month · all time (no range).

export type PeriodKey = 'today' | 'week' | 'month' | 'all';

export const PERIODS: { key: PeriodKey; label: string }[] = [
  { key: 'today', label: 'Aujourd’hui' },
  { key: 'week', label: 'Semaine' },
  { key: 'month', label: 'Mois' },
  { key: 'all', label: 'Tout' },
];

export type EarningsData = {
  totalEarnings: number;
  transactions: {
    id: string;
    appointmentId: string;
    amount: number;
    date: string;
    status: string;
  }[];
};

/// Inclusive-start/exclusive-end range for a period, or null for all time.
export function periodRange(
  key: PeriodKey,
  now: Date = new Date(),
): { startDate: string; endDate: string } | null {
  const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (key === 'today') {
    const end = new Date(dayStart);
    end.setDate(end.getDate() + 1);
    return { startDate: dayStart.toISOString(), endDate: end.toISOString() };
  }
  if (key === 'week') {
    // Monday-start (getDay(): Sunday = 0), same as the app's weekday - 1.
    const start = new Date(dayStart);
    start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
    const end = new Date(start);
    end.setDate(end.getDate() + 7);
    return { startDate: start.toISOString(), endDate: end.toISOString() };
  }
  if (key === 'month') {
    const start = new Date(now.getFullYear(), now.getMonth(), 1);
    const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    return { startDate: start.toISOString(), endDate: end.toISOString() };
  }
  return null;
}
