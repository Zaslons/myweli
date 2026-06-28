import type { ProAppointment } from './today';

/// Pure helpers for the pro « Rendez-vous » views (Calendrier + Liste).
/// Unit-tested. Mirrors the app's appointment screen filters.

export type ListTab = 'today' | 'upcoming' | 'pending' | 'all';

export const LIST_TABS: { key: ListTab; label: string }[] = [
  { key: 'today', label: "Aujourd'hui" },
  { key: 'upcoming', label: 'À venir' },
  { key: 'pending', label: 'En attente' },
  { key: 'all', label: 'Tous' },
];

export function dateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
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

export function appointmentsOnDate(
  items: ProAppointment[],
  key: string,
): ProAppointment[] {
  return items
    .filter((a) => a.appointmentDate.slice(0, 10) === key)
    .sort((a, b) => a.appointmentDate.localeCompare(b.appointmentDate));
}

export function daysWithBookings(items: ProAppointment[]): Set<string> {
  return new Set(items.map((a) => a.appointmentDate.slice(0, 10)));
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

export function monthLabelFr(d: Date): string {
  return new Intl.DateTimeFormat('fr-FR', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(d);
}

/// Liste sub-tab filters, mirroring the app (Aujourd'hui/À venir/En attente/Tous).
export function filterList(
  items: ProAppointment[],
  tab: ListTab,
  now: Date = new Date(),
): ProAppointment[] {
  const k = dateKey(now);
  const sorted = [...items].sort((a, b) =>
    a.appointmentDate.localeCompare(b.appointmentDate),
  );
  switch (tab) {
    case 'today':
      return sorted.filter((a) => a.appointmentDate.slice(0, 10) === k);
    case 'upcoming':
      return sorted.filter(
        (a) =>
          a.appointmentDate.slice(0, 10) >= k &&
          (a.status === 'pending' || a.status === 'confirmed'),
      );
    case 'pending':
      return sorted.filter((a) => a.status === 'pending');
    case 'all':
      return sorted;
  }
}
