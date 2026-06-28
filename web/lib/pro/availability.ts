/// Pure helpers for the pro Disponibilités editor. Unit-tested.
/// weeklySchedule keys "0".."6" = Lundi..Dimanche (matches the app/backend).

export type TimeSlot = { startTime: string; endTime: string; isAvailable?: boolean };
export type WeeklySchedule = Record<string, TimeSlot[]>;

export type Availability = {
  providerId: string;
  weeklySchedule: WeeklySchedule;
  breaks?: WeeklySchedule;
  blockedDates: string[];
  bufferMinutes: number;
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
