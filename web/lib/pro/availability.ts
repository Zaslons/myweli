/// Pure helpers for the pro Disponibilités editor. Unit-tested.
/// weeklySchedule keys "0".."6" = Lundi..Dimanche (matches the app/backend).

export type TimeSlot = { startTime: string; endTime: string; isAvailable?: boolean };
export type WeeklySchedule = Record<string, TimeSlot[]>;

/// ⚠️ **Hand-written, and nothing syncs it with the generated schema.**
/// `npm run gen:api` regenerates `lib/api/schema.ts` only, and `lib/api/pro.ts`
/// imports `Availability` from HERE — so the whole pro dashboard is typed
/// against this shape, and a contract change lands in the generated file
/// without any gate noticing this one drifted. It already differs:
/// `TimeSlot.isAvailable` is required upstream and optional here.
///
/// Recorded rather than fixed in A14d: pointing the dashboard at the generated
/// type is a mechanical but wide change, and it is not what this slice is for.
export type Availability = {
  providerId: string;
  weeklySchedule: WeeklySchedule;
  breaks?: WeeklySchedule;
  blockedDates: string[];
  bufferMinutes: number;
  /// A14d — the bookable window. Optional here (not on the wire) so a payload
  /// from a server that predates A14d still types.
  bookingHorizonDays?: number;
  minimumNoticeMinutes?: number;
};

export type DayForm = {
  key: string;
  label: string;
  open: boolean;
  start: string;
  end: string;
};

export const DAY_KEYS = ['0', '1', '2', '3', '4', '5', '6'];
export const DAY_LABELS = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
export const BUFFER_PRESETS = [0, 5, 10, 15, 30];

/// One editable range per day (the first slot); closed = no slots.
export function toEditable(a?: Availability): DayForm[] {
  const ws = a?.weeklySchedule ?? {};
  return DAY_KEYS.map((key, i) => {
    const slots = ws[key] ?? [];
    const first = slots[0];
    return {
      key,
      label: DAY_LABELS[i],
      open: slots.length > 0,
      start: first?.startTime ?? '09:00',
      end: first?.endTime ?? '18:00',
    };
  });
}

export function validateHours(days: DayForm[]): string | null {
  for (const d of days) {
    if (d.open && !(d.start < d.end)) {
      return `${d.label} : l’heure de fin doit être après le début.`;
    }
  }
  return null;
}

/// Rebuild the full Availability for PUT, preserving `base` fields and any
/// extra per-day slots beyond the first (round-trip, don't wipe).
export function toApi(days: DayForm[], base: Availability): Availability {
  const ws: WeeklySchedule = {};
  for (const d of days) {
    if (!d.open) {
      ws[d.key] = [];
      continue;
    }
    const extra = (base.weeklySchedule?.[d.key] ?? []).slice(1);
    ws[d.key] = [
      { startTime: d.start, endTime: d.end, isAvailable: true },
      ...extra,
    ];
  }
  return { ...base, weeklySchedule: ws };
}

/// Generic WeeklySchedule → DayForm rows (breaks, per-artist hours — audit
/// 3.4/3.8). Same one-range-per-day editing model as the salon hours.
export function scheduleToDays(
  ws: WeeklySchedule | undefined,
  defaults: { start: string; end: string } = { start: '09:00', end: '18:00' },
): DayForm[] {
  return DAY_KEYS.map((key, i) => {
    const slots = ws?.[key] ?? [];
    const first = slots[0];
    return {
      key,
      label: DAY_LABELS[i],
      open: slots.length > 0,
      start: first?.startTime ?? defaults.start,
      end: first?.endTime ?? defaults.end,
    };
  });
}

/// DayForm rows → WeeklySchedule, preserving extra per-day slots from [base]
/// (round-trip, don't wipe). Closed days are OMITTED (an entirely empty map
/// means « none » — e.g. artist hours inheriting the salon's).
export function daysToSchedule(
  days: DayForm[],
  base?: WeeklySchedule,
): WeeklySchedule {
  const ws: WeeklySchedule = {};
  for (const d of days) {
    if (!d.open) continue;
    const extra = (base?.[d.key] ?? []).slice(1);
    ws[d.key] = [
      { startTime: d.start, endTime: d.end, isAvailable: true },
      ...extra,
    ];
  }
  return ws;
}

/// What the pro's « Fenêtre de réservation » card offers — the web mirror of
/// mobile's `BookingWindowPresets`.
///
/// No pair may put the notice past the horizon: the server refuses that as
/// `invalid_input`, and a salon must never be offered a chip that fails.
export const HORIZON_PRESETS = [30, 90, 180, 365];
export const NOTICE_PRESETS = [0, 60, 720, 1440];

export function horizonLabel(days: number): string {
  if (days === 30) return '1 mois';
  if (days === 90) return '3 mois';
  if (days === 180) return '6 mois';
  if (days === 365) return '1 an';
  return `${days} jours`;
}

export function noticeLabel(minutes: number): string {
  if (minutes === 0) return 'Aucun';
  if (minutes < 60) return `${minutes} min`;
  return `${minutes / 60} h`;
}
