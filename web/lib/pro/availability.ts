/// Pure helpers for the pro Disponibilités editor. Unit-tested.
/// weeklySchedule keys "0".."6" = Lundi..Dimanche (matches the app/backend).

export type TimeSlot = {
  startTime: string;
  endTime: string;
  isAvailable?: boolean;
};
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

export const DAY_KEYS = ["0", "1", "2", "3", "4", "5", "6"];
export const DAY_LABELS = [
  "Lundi",
  "Mardi",
  "Mercredi",
  "Jeudi",
  "Vendredi",
  "Samedi",
  "Dimanche",
];
export const BUFFER_PRESETS = [0, 5, 10, 15, 30];

/// The placeholder date the server normalises every time-of-day to
/// (`2024-01-01T09:00:00.000Z`, observed on the wire). `openapi.yaml:4033-4036`
/// types `TimeSlot.startTime` as `format: date-time` and says only the
/// time-of-day is significant — so the date is a carrier, not data.
const WIRE_DATE = "2024-01-01";

/// Wire date-time → `HH:mm` for `<input type="time">`, which accepts nothing
/// else (`DayHoursEditor.tsx:52`).
///
/// **Parsed with a regex, never with `new Date()`.** The instant is meaningless
/// but a `Date` is not: `new Date('2024-01-01T09:00:00.000Z').getHours()` is 10
/// in Abidjan-plus-one and 4 in New York, so a salon's opening hour would move
/// with the browser's timezone. The digits after the `T` are the datum.
export function timeOfDay(wire: string): string {
  const m = /T(\d{2}):(\d{2})/.exec(wire);
  if (m) return `${m[1]}:${m[2]}`;
  // Tolerated on READ only: a bare HH:mm is what this file used to write, so
  // any salon that somehow has one stored still edits cleanly.
  return /^\d{2}:\d{2}$/.test(wire) ? wire : "";
}

/// `HH:mm` → the wire date-time. The inverse of [timeOfDay], and the reason a
/// web-onboarded salon can set its hours at all: the server validates with
/// `DateTime.tryParse` (`provider_catalog_service.dart:713`), which answers
/// null to `'09:00'` and earns a 400 `invalid_input`.
export function wireTime(hhmm: string): string {
  return /^\d{2}:\d{2}$/.test(hhmm) ? `${WIRE_DATE}T${hhmm}:00.000Z` : hhmm;
}

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
      start: timeOfDay(first?.startTime ?? "") || "09:00",
      end: timeOfDay(first?.endTime ?? "") || "18:00",
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
      {
        startTime: wireTime(d.start),
        endTime: wireTime(d.end),
        isAvailable: true,
      },
      ...extra,
    ];
  }
  return { ...base, weeklySchedule: ws };
}

/// Generic WeeklySchedule → DayForm rows (breaks, per-artist hours — audit
/// 3.4/3.8). Same one-range-per-day editing model as the salon hours.
export function scheduleToDays(
  ws: WeeklySchedule | undefined,
  defaults: { start: string; end: string } = { start: "09:00", end: "18:00" },
): DayForm[] {
  return DAY_KEYS.map((key, i) => {
    const slots = ws?.[key] ?? [];
    const first = slots[0];
    return {
      key,
      label: DAY_LABELS[i],
      open: slots.length > 0,
      start: timeOfDay(first?.startTime ?? "") || defaults.start,
      end: timeOfDay(first?.endTime ?? "") || defaults.end,
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
      {
        startTime: wireTime(d.start),
        endTime: wireTime(d.end),
        isAvailable: true,
      },
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
  if (days === 30) return "1 mois";
  if (days === 90) return "3 mois";
  if (days === 180) return "6 mois";
  if (days === 365) return "1 an";
  return `${days} jours`;
}

export function noticeLabel(minutes: number): string {
  if (minutes === 0) return "Aucun";
  if (minutes < 60) return `${minutes} min`;
  return `${minutes / 60} h`;
}
