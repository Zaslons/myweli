/// The « Semaine » grid's pure parts (docs/design/web-pro-week-view.md): one
/// axis for the seven days, what is not open on it, simultaneous bookings in
/// lanes, the artist filter. Unit-tested; no React here. Day identity and
/// minutes come from the salon-time seam (lib/time.ts, via journal.ts).

import {
  CLOSED_AXIS,
  type JournalArtist,
  type JournalDay,
  type JournalHours,
  PX_PER_MIN,
  hhmm,
  minutesOfDay,
  parseHhmm,
} from './journal';
import type { ProAppointment } from './today';

/// From the earliest opening to the latest closing of the open days; the
/// Journée's neutral axis when the salon is closed all week.
export function weekAxis(days: JournalDay[]): JournalHours {
  const open = days.map((d) => d.hours).filter((h): h is JournalHours => h != null);
  if (open.length === 0) return CLOSED_AXIS;
  const start = Math.min(...open.map((h) => parseHhmm(h.open)));
  const end = Math.max(...open.map((h) => parseHhmm(h.close)));
  return { open: hhmm(start), close: hhmm(end), breaks: [] };
}

type Band = { top: number; height: number };

/// What is NOT open in [day], on the week's [axis] (px from its top): before
/// opening, each break, after closing — or the whole axis for a closed day.
export function dayBands(day: JournalDay, axis: JournalHours): Band[] {
  const axisOpen = parseHhmm(axis.open);
  const axisClose = parseHhmm(axis.close);
  const px = (from: number, to: number): Band => ({
    top: (from - axisOpen) * PX_PER_MIN,
    height: Math.max(0, (to - from) * PX_PER_MIN),
  });
  if (!day.hours) return [px(axisOpen, axisClose)];
  const open = parseHhmm(day.hours.open);
  const close = parseHhmm(day.hours.close);
  const bands: Band[] = [];
  if (open > axisOpen) bands.push(px(axisOpen, open));
  for (const b of day.hours.breaks) bands.push(px(parseHhmm(b.start), parseHhmm(b.end)));
  if (close < axisClose) bands.push(px(close, axisClose));
  return bands;
}

const durationOf = (a: ProAppointment) =>
  a.durationMinutes && a.durationMinutes > 0 ? a.durationMinutes : 30;

/// Simultaneous bookings share the day's column side by side: each gets a
/// lane and the number of lanes of its cluster (bookings linked by overlap).
/// Back to back is not simultaneous; a lane freed is reused.
export function lanesFor(
  appts: ProAppointment[],
  tz?: string,
): Map<string, { lane: number; lanes: number }> {
  const items = appts
    .map((a) => {
      const start = minutesOfDay(a.appointmentDate, tz);
      return { id: a.id, start, end: start + durationOf(a) };
    })
    .sort((x, y) => x.start - y.start || x.end - y.end);
  const out = new Map<string, { lane: number; lanes: number }>();
  let cluster: { id: string; lane: number }[] = [];
  let laneEnds: number[] = [];
  let clusterEnd = -Infinity;
  const close = () => {
    for (const c of cluster) out.set(c.id, { lane: c.lane, lanes: laneEnds.length });
    cluster = [];
    laneEnds = [];
  };
  for (const it of items) {
    if (it.start >= clusterEnd) close();
    let lane = laneEnds.findIndex((end) => end <= it.start);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(it.end);
    } else {
      laneEnds[lane] = it.end;
    }
    cluster.push({ id: it.id, lane });
    clusterEnd = Math.max(clusterEnd === -Infinity ? it.end : clusterEnd, it.end);
  }
  close();
  return out;
}

/// The week's artists (every day's, once each) — and « Sans artiste » when a
/// booking has none, as the Journée's columns.
export function weekArtists(days: JournalDay[]): JournalArtist[] {
  const seen = new Map<string, JournalArtist>();
  for (const d of days) for (const a of d.artists) if (!seen.has(a.id)) seen.set(a.id, a);
  const out = [...seen.values()];
  if (days.some((d) => d.appointments.some((a) => !a.artistId))) {
    out.push({ id: '', name: 'Sans artiste' });
  }
  return out;
}

/// « Tous » (null) keeps everything; an artist id keeps theirs; '' keeps the
/// bookings with no artist.
export function filterArtist(
  appts: ProAppointment[],
  artistId: string | null,
): ProAppointment[] {
  if (artistId === null) return appts;
  return appts.filter((a) => (a.artistId ?? '') === artistId);
}
