import { countFr } from '../format';
import { salonFormatter } from '../time';
import { WEEKDAYS_SHORT, addDays, anchorKey } from './agenda';
import type { JournalDay } from './journal';
import { apptDayKey, type ProAppointment } from './today';

/// The week above the Journée (docs/design/web-pro-week-strip.md) — the app's
/// `_WeekStrip` (`pro_journal_screen.dart`): Monday → Sunday of the shown day,
/// each with a dot that grows with its load. Pure; unit-tested. Day keys are
/// SALON days; the Dates here are midday-UTC anchors used as day identifiers
/// (the agenda's own convention), never instants.

const anchor = (key: string) => new Date(`${key}T12:00:00.000Z`);

/// Monday → Sunday of the week containing [key].
export function weekOf(key: string): string[] {
  const d = anchor(key);
  const monday = addDays(d, -((d.getUTCDay() + 6) % 7));
  return Array.from({ length: 7 }, (_, i) => anchorKey(addDays(monday, i)));
}

/// Bookings per day of [week], cancelled ones left out (owner Q2: the dot is
/// the load, and the Journée hides them by default). A day the page has
/// loaded counts from its journal day — the one re-read after every action of
/// the grid; the others from the salon's list, read once with the page.
export function weekCounts(
  items: ProAppointment[],
  week: string[],
  tz?: string,
  loaded?: JournalDay | null,
): Record<string, number> {
  const counts: Record<string, number> = Object.fromEntries(week.map((k) => [k, 0]));
  const live = (a: ProAppointment) => a.status !== 'cancelled';
  for (const a of items) {
    const k = apptDayKey(a, tz);
    if (k in counts && k !== loaded?.date && live(a)) counts[k] += 1;
  }
  if (loaded && loaded.date in counts) {
    counts[loaded.date] = loaded.appointments.filter(live).length;
  }
  return counts;
}

/// The dot's width: none at 0, one step longer per booking up to five — the
/// app's `3 + count.clamp(0, 5)`, on the web's sizing scale.
const DOT_WIDTHS = ['w-1', 'w-2', 'w-3', 'w-4', 'w-5'];
export function loadDotClass(n: number): string | null {
  if (n <= 0) return null;
  return DOT_WIDTHS[Math.min(n, DOT_WIDTHS.length) - 1];
}

/// The group's name: « Semaine du 20 octobre » (its Monday).
export function weekStripLabel(week: string[], tz?: string): string {
  const monday = salonFormatter({ day: 'numeric', month: 'long' }, tz).format(
    anchor(week[0]),
  );
  return `Semaine du ${monday}`;
}

/// One day's words: what it shows (« Lun », « 20 ») and what its name goes on
/// to say for a screen reader — so the name STARTS with what is seen (WCAG
/// 2.5.3): « Lun 20 octobre, 3 rendez-vous[, aujourd’hui] ».
export function weekStripDay(
  key: string,
  count: number,
  isToday: boolean,
  tz?: string,
): { short: string; day: string; rest: string } {
  const d = anchor(key);
  const month = salonFormatter({ month: 'long' }, tz).format(d);
  const load = count === 0 ? 'aucun rendez-vous' : countFr(count, 'rendez-vous', 'rendez-vous');
  return {
    short: WEEKDAYS_SHORT[(d.getUTCDay() + 6) % 7],
    day: String(d.getUTCDate()),
    rest: `${month}, ${load}${isToday ? ', aujourd’hui' : ''}`,
  };
}
