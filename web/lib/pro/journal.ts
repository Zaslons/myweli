import { salonDayKey, salonMinutesOfDay, salonWallClockToUtc } from '../time';
import type { ProAppointment } from './today';

/// Module `journal` J1 (docs/design/journal-j1-grid.md) — pure geometry +
/// types for the day grid. Unit-tested; no React here. Day identity and
/// minutes-of-day come from the salon-time seam (lib/time.ts).

export type JournalHours = {
  open: string; // 'HH:mm'
  close: string;
  breaks: { start: string; end: string }[];
};

export type JournalArtist = { id: string; name: string; imageUrl?: string | null };

export type JournalDay = {
  date: string; // 'YYYY-MM-DD'
  hours: JournalHours | null;
  artists: JournalArtist[];
  appointments: ProAppointment[];
};

/// Vertical scale + snap grid. 1 px/min keeps a 9 h day ≈ 540 px.
export const PX_PER_MIN = 1;
export const SNAP_MIN = 15;
export const MIN_BLOCK_PX = 24;
/// The neutral axis used when the salon is closed (hours === null).
export const CLOSED_AXIS: JournalHours = { open: '08:00', close: '20:00', breaks: [] };

export function parseHhmm(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

export function hhmm(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/// Minutes past SALON midnight of an ISO instant.
export function minutesOfDay(iso: string, tz?: string): number {
  return salonMinutesOfDay(new Date(iso), tz);
}

export function snapToQuarter(minutes: number): number {
  return Math.round(minutes / SNAP_MIN) * SNAP_MIN;
}

/// Top offset (px) of a minute within the axis, clamped to the day.
export function topFor(minute: number, openMin: number): number {
  return Math.max(0, (minute - openMin) * PX_PER_MIN);
}

/// A block's top + height (px) from its start ISO and duration.
export function blockBox(
  appt: ProAppointment,
  openMin: number,
  tz?: string,
): { top: number; height: number } {
  const start = minutesOfDay(appt.appointmentDate, tz);
  const dur = appt.durationMinutes && appt.durationMinutes > 0 ? appt.durationMinutes : 30;
  return {
    top: topFor(start, openMin),
    height: Math.max(MIN_BLOCK_PX, dur * PX_PER_MIN),
  };
}

/// The « Maintenant » line offset for `now`, or null if outside the axis or
/// not viewing today.
export function nowLineTop(
  now: Date,
  dayKey: string,
  hours: JournalHours,
  tz?: string,
): number | null {
  if (salonDayKey(now, tz) !== dayKey) return null;
  const minute = salonMinutesOfDay(now, tz);
  const openMin = parseHhmm(hours.open);
  const closeMin = parseHhmm(hours.close);
  if (minute < openMin || minute > closeMin) return null;
  return topFor(minute, openMin);
}

/// Hour tick marks (label + top) across the axis.
export function hourTicks(hours: JournalHours): { label: string; top: number }[] {
  const openMin = parseHhmm(hours.open);
  const closeMin = parseHhmm(hours.close);
  const ticks: { label: string; top: number }[] = [];
  const first = Math.ceil(openMin / 60) * 60;
  for (let m = first; m <= closeMin; m += 60) {
    ticks.push({ label: hhmm(m), top: topFor(m, openMin) });
  }
  return ticks;
}

/// Break bands (top + height) across all columns.
export function breakBands(
  hours: JournalHours,
): { top: number; height: number }[] {
  const openMin = parseHhmm(hours.open);
  return hours.breaks.map((b) => {
    const s = parseHhmm(b.start);
    const e = parseHhmm(b.end);
    return { top: topFor(s, openMin), height: Math.max(0, (e - s) * PX_PER_MIN) };
  });
}

/// Total axis height (px).
export function axisHeight(hours: JournalHours): number {
  return (parseHhmm(hours.close) - parseHhmm(hours.open)) * PX_PER_MIN;
}

/// The ISO instant for a snapped drop at [minute] on [dayKey] — a SALON
/// wall-clock, built offset-aware through the seam (multi-pays MP3:
/// salonWallClockToUtc replaced the old hardcoded-Z construction).
export function isoAt(dayKey: string, minute: number, tz?: string): string {
  return salonWallClockToUtc(dayKey, snapToQuarter(minute), tz).toISOString();
}

/// Which artist column an appointment belongs to (or '' = « Sans artiste »).
export function columnOf(appt: ProAppointment): string {
  return appt.artistId ?? '';
}

/// Status → a token-based tint class set { block bg/border, text }.
export const STATUS_STYLE: Record<string, string> = {
  pending: 'bg-warning/10 border-warning/40 text-textPrimary',
  confirmed: 'bg-info/10 border-info/40 text-textPrimary',
  arrived: 'bg-success/10 border-success/50 text-textPrimary',
  completed: 'bg-surface border-border text-textSecondary',
  cancelled: 'bg-surface border-border text-textTertiary line-through opacity-60',
  noShow: 'bg-error/10 border-error/40 text-textPrimary',
};

/// Derived status key incl. the in-day « arrivé » (confirmed + arrivedAt).
export function statusKey(appt: ProAppointment): string {
  if (appt.status === 'confirmed' && appt.arrivedAt) return 'arrived';
  return appt.status;
}

/// A block is draggable only while it can still move (pending/confirmed).
export function isDraggable(appt: ProAppointment): boolean {
  return appt.status === 'pending' || appt.status === 'confirmed';
}

/// The artist columns to render: the salon's artists + a « Sans artiste »
/// column when the day has any unassigned booking.
export function columnsFor(day: JournalDay): JournalArtist[] {
  const cols = [...day.artists];
  if (day.appointments.some((a) => !a.artistId)) {
    cols.push({ id: '', name: 'Sans artiste' });
  }
  return cols.length > 0 ? cols : [{ id: '', name: 'Salon' }];
}
