import { salonDayKey, salonFormatter } from '../time';
import { apptDayKey, type ProAppointment } from './today';

/// Pure helpers for the pro « Rendez-vous » views (Calendrier + Liste).
/// Unit-tested. Mirrors the app's appointment screen filters. Day identity
/// comes from the salon-time seam (lib/time.ts); the Date objects inside the
/// month grid are midnight-UTC anchors used as day IDENTIFIERS, so their
/// UTC arithmetic is zone-agnostic calendar math, not display logic.

export type ListTab = 'today' | 'upcoming' | 'pending' | 'all';

export const LIST_TABS: { key: ListTab; label: string }[] = [
  { key: 'today', label: "Aujourd'hui" },
  { key: 'upcoming', label: 'À venir' },
  { key: 'pending', label: 'En attente' },
  { key: 'all', label: 'Tous' },
];

export function dateKey(d: Date, tz?: string): string {
  return salonDayKey(d, tz);
}

/// The identity key of a month-grid day ANCHOR (a midnight-UTC Date used as
/// a day identifier — zone-agnostic calendar math, NOT display; never pass a
/// real instant here).
export function anchorKey(d: Date): string {
  const y = String(d.getUTCFullYear()).padStart(4, '0');
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setUTCDate(x.getUTCDate() + n);
  return x;
}

/// First day of the month `n` months from `d`.
export function addMonths(d: Date, n: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, 1));
}

/// Bookings on a SALON day key (multi-pays MP3: the instant's salon day, not
/// the ISO string's UTC prefix).
export function appointmentsOnDate(
  items: ProAppointment[],
  key: string,
  tz?: string,
): ProAppointment[] {
  return items
    .filter((a) => apptDayKey(a, tz) === key)
    .sort((a, b) => a.appointmentDate.localeCompare(b.appointmentDate));
}

export function daysWithBookings(
  items: ProAppointment[],
  tz?: string,
): Set<string> {
  return new Set(items.map((a) => apptDayKey(a, tz)));
}

/// A 6×7 Monday-start matrix of dates for the month containing `focused`.
export function monthMatrix(focused: Date): Date[][] {
  const first = new Date(
    Date.UTC(focused.getUTCFullYear(), focused.getUTCMonth(), 1),
  );
  const mondayOffset = (first.getUTCDay() + 6) % 7; // 0 = Monday
  let cur = addDays(first, -mondayOffset);
  const weeks: Date[][] = [];
  for (let w = 0; w < 6; w++) {
    const row: Date[] = [];
    for (let d = 0; d < 7; d++) {
      row.push(cur);
      cur = addDays(cur, 1);
    }
    weeks.push(row);
  }
  return weeks;
}

export function monthLabelFr(d: Date, tz?: string): string {
  return salonFormatter({ month: 'long', year: 'numeric' }, tz).format(d);
}

/// Liste sub-tab filters, mirroring the app (Aujourd'hui/À venir/En attente/Tous).
export function filterList(
  items: ProAppointment[],
  tab: ListTab,
  now: Date = new Date(),
  tz?: string,
): ProAppointment[] {
  const k = dateKey(now, tz);
  const sorted = [...items].sort((a, b) =>
    a.appointmentDate.localeCompare(b.appointmentDate),
  );
  switch (tab) {
    case 'today':
      return sorted.filter((a) => apptDayKey(a, tz) === k);
    case 'upcoming':
      return sorted.filter(
        (a) =>
          apptDayKey(a, tz) >= k &&
          (a.status === 'pending' || a.status === 'confirmed'),
      );
    case 'pending':
      return sorted.filter((a) => a.status === 'pending');
    case 'all':
      return sorted;
  }
}
