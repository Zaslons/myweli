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

/// ONE range per day — the breaks (« Pauses ») and the per-artist hours,
/// which are one range in the app too (`WeeklyHoursEditor`).
export type DayForm = {
  key: string;
  label: string;
  open: boolean;
  start: string;
  end: string;
};

/// A range of the salon's day, `HH:mm`.
export type Range = { start: string; end: string };

/// The salon's opening hours: EVERY range of a day
/// (docs/design/web-pro-availability-ranges.md). The web used to edit the
/// first range only and carry the others unseen (`slice(1)`); a salon closed
/// at noon saw its morning and nothing else. `ranges` survive `open: false`,
/// so unticking and reticking « Ouvert » gives them back.
export type DayRanges = {
  key: string;
  label: string;
  open: boolean;
  ranges: Range[];
};

/// What a newly opened day starts with — unchanged from the one-range editor.
export const DEFAULT_RANGE: Range = { start: "09:00", end: "18:00" };

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

/// Wire date-time → `HH:mm` for `<input type="time">` — hosted in the neutral
/// `lib/time-of-day.ts` since the PUBLIC page reads it too; re-exported here
/// so the editor's call sites did not churn.
import { timeOfDay } from "../time-of-day";
import { countFr } from "../format";
import { salonDayKey, salonWallClockToUtc } from "../time";

export { timeOfDay };

/// `HH:mm` → the wire date-time. The inverse of [timeOfDay], and the reason a
/// web-onboarded salon can set its hours at all: the server validates with
/// `DateTime.tryParse` (`provider_catalog_service.dart:713`), which answers
/// null to `'09:00'` and earns a 400 `invalid_input`.
export function wireTime(hhmm: string): string {
  return /^\d{2}:\d{2}$/.test(hhmm) ? `${WIRE_DATE}T${hhmm}:00.000Z` : hhmm;
}

/// Every range of every day (Monday first); closed = no slots.
export function toEditable(a?: Availability): DayRanges[] {
  const ws = a?.weeklySchedule ?? {};
  return DAY_KEYS.map((key, i) => {
    const slots = ws[key] ?? [];
    return {
      key,
      label: DAY_LABELS[i],
      open: slots.length > 0,
      ranges: slots.map((s) => ({
        start: timeOfDay(s.startTime) || DEFAULT_RANGE.start,
        end: timeOfDay(s.endTime) || DEFAULT_RANGE.end,
      })),
    };
  });
}

/// « Ouvert » ticked: the day opens with its remembered ranges, or the
/// default one if it has none — never an open day without a range.
export function openDay(d: DayRanges): DayRanges {
  return {
    ...d,
    open: true,
    ranges: d.ranges.length > 0 ? d.ranges : [{ ...DEFAULT_RANGE }],
  };
}

function minutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

function hhmm(total: number): string {
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

const LAST_MINUTE = 23 * 60 + 59;

/// What « Ajouter une plage » proposes: one hour after the last range ends,
/// four hours long, never past 23:59; with less than an hour left it starts
/// where the last one ends; with nothing left, null (the button goes
/// inactive). The first range is [DEFAULT_RANGE].
export function nextRange(ranges: Range[]): Range | null {
  if (ranges.length === 0) return { ...DEFAULT_RANGE };
  const lastEnd = Math.max(...ranges.map((r) => minutes(r.end)));
  if (lastEnd >= LAST_MINUTE) return null;
  const start = lastEnd + 60 >= LAST_MINUTE ? lastEnd : lastEnd + 60;
  return { start: hhmm(start), end: hhmm(Math.min(start + 240, LAST_MINUTE)) };
}

const byStart = (a: Range, b: Range) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0);

/// Every range ends after it starts, and — since 2026-10-19 — no two ranges
/// of a day overlap (H4; the app refuses the same since then). Ranges that
/// TOUCH (one ends at 12:00, the next starts at 12:00) are fine.
export function validateHours(days: DayRanges[]): string | null {
  for (const d of days) {
    if (!d.open) continue;
    if (d.ranges.some((r) => !(r.start < r.end))) {
      return `${d.label} : l’heure de fin doit être après le début.`;
    }
    const sorted = [...d.ranges].sort(byStart);
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i].start < sorted[i - 1].end) {
        return `${d.label} : deux plages se chevauchent.`;
      }
    }
  }
  return null;
}

/// Rebuild the full Availability for PUT: every open day's ranges, sorted by
/// start, in the wire format; closed days empty; every other field of
/// [base] untouched.
export function toApi(days: DayRanges[], base: Availability): Availability {
  const ws: WeeklySchedule = {};
  for (const d of days) {
    ws[d.key] = d.open
      ? [...d.ranges].sort(byStart).map((r) => ({
          startTime: wireTime(r.start),
          endTime: wireTime(r.end),
          isAvailable: true,
        }))
      : [];
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

/// One « Horaires » starting point a salon applies in a click and edits
/// afterwards (docs/design/availability-presets.md).
export type SchedulePreset = {
  label: string;
  /// 0 = Lundi .. 6 = Dimanche, the `weeklySchedule` convention.
  days: number[];
  start: string;
  end: string;
};

/// The web mirror of mobile's `WeeklySchedulePresets` — labels pinned
/// character-for-character (identical French on both surfaces is the product
/// rule). « – » is the en dash and « · » the middot, the chip-label idiom.
export const SCHEDULE_PRESETS: SchedulePreset[] = [
  {
    label: "Mar–Sam · 9h–18h",
    days: [1, 2, 3, 4, 5],
    start: "09:00",
    end: "18:00",
  },
  {
    label: "Lun–Sam · 8h–17h",
    days: [0, 1, 2, 3, 4, 5],
    start: "08:00",
    end: "17:00",
  },
  {
    label: "Tous les jours · 9h–19h",
    days: [0, 1, 2, 3, 4, 5, 6],
    start: "09:00",
    end: "19:00",
  },
];

/// The créneaux explainer under both platforms' hours headings — identical to
/// mobile's `kCreneauxCopy`, pinned.
export const CRENEAUX_COPY =
  "Vos créneaux de réservation sont calculés automatiquement à partir de " +
  "ces horaires et de la durée de chaque prestation.";

/// Apply [preset] to the staged rows: preset days open at its hours, every
/// other day CLOSED — a model is the whole week, and « Mar–Sam » silently
/// keeping an old Sunday would misname the chip it lights. Staged only;
/// nothing is written until « Enregistrer ».
export function applyPreset(
  days: DayRanges[],
  preset: SchedulePreset,
): DayRanges[] {
  return days.map((d, i) =>
    preset.days.includes(i)
      ? { ...d, open: true, ranges: [{ start: preset.start, end: preset.end }] }
      : { ...d, open: false },
  );
}

/// Honest chip state: selected iff the staged rows ARE exactly the model —
/// any manual edit unlights every chip.
export function presetMatches(
  days: DayRanges[],
  preset: SchedulePreset,
): boolean {
  return days.every((d, i) =>
    preset.days.includes(i)
      ? d.open &&
        d.ranges.length === 1 &&
        d.ranges[0].start === preset.start &&
        d.ranges[0].end === preset.end
      : !d.open,
  );
}

/// Row [i]'s {open, ranges} onto every row — « Copier sur les autres jours »,
/// EVERY range, as the app copies them; independent copies, so editing one
/// day afterwards does not move the others.
export function copyDayToAll(days: DayRanges[], i: number): DayRanges[] {
  const src = days[i];
  return days.map((d) => ({
    ...d,
    open: src.open,
    ranges: src.ranges.map((r) => ({ ...r })),
  }));
}

/// [copyDayToAll] for the ONE-range editors (the per-artist hours, whose app
/// twin has one range per day too): row [i]'s {open, start, end} onto every
/// row; each day's extra ranges (`daysToSchedule`'s `slice(1)`) still ride
/// the save, as before.
export function copyFormDayToAll(days: DayForm[], i: number): DayForm[] {
  const src = days[i];
  return days.map((d) => ({
    ...d,
    open: src.open,
    start: src.start,
    end: src.end,
  }));
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

// ---- Blocked dates (web-pro-availability-ranges.md §2.2) --------------------

export type BlockedChange = { added: string[]; removed: string[] };

const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;

/// The SALON day a stored blocked date names. Two formats live in the same
/// list: the web wrote « 2026-12-25 », the app writes the salon's midnight as
/// an instant (« 2026-12-24T23:00:00.000Z » for a UTC+1 salon). The page used
/// to splice « T12:00:00.000Z » onto both, and the app's form became an
/// invalid date that threw on render — the page would not open. Unreadable
/// → null, never a throw.
export function blockedDayKey(stored: string, tz?: string): string | null {
  if (DAY_KEY.test(stored)) return stored;
  const d = new Date(stored);
  return Number.isNaN(d.getTime()) ? null : salonDayKey(d, tz);
}

/// The stored list after [change]: entries not removed stay BYTE-IDENTICAL
/// (no rewrite of what the pro did not touch); an added day is written as the
/// app writes it — the salon's midnight, as a UTC instant — unless that day is
/// already there.
export function applyBlockedChange(
  current: string[],
  change: BlockedChange,
  tz?: string,
): string[] {
  const removed = new Set(change.removed);
  const kept = current.filter((s) => {
    const k = blockedDayKey(s, tz);
    return k === null || !removed.has(k);
  });
  const have = new Set(kept.map((s) => blockedDayKey(s, tz)));
  const added = [...new Set(change.added)]
    .filter((k) => !have.has(k))
    .sort()
    .map((k) => salonWallClockToUtc(k, 0, tz).toISOString());
  return [...kept, ...added];
}

/// What a picker session adds and removes, sorted.
export function blockedChange(
  initial: ReadonlySet<string>,
  selected: ReadonlySet<string>,
): BlockedChange {
  return {
    added: [...selected].filter((k) => !initial.has(k)).sort(),
    removed: [...initial].filter((k) => !selected.has(k)).sort(),
  };
}

/// The picker's live summary — the app's words (D3).
export function blockedPickerSummary(
  selected: number,
  change: BlockedChange,
): { state: string; delta: string } {
  const state =
    selected === 0 && change.removed.length > 0
      ? "Toutes vos dates bloquées seront retirées."
      : selected === 0
        ? "Touchez les jours à bloquer."
        : countFr(selected, "date bloquée", "dates bloquées");
  const delta = [
    change.added.length > 0 ? countFr(change.added.length, "ajoutée", "ajoutées") : "",
    change.removed.length > 0 ? countFr(change.removed.length, "retirée", "retirées") : "",
  ]
    .filter(Boolean)
    .join(" · ");
  return { state, delta };
}

/// The confirmation, naming the direction — the app's words (D6). [fmt]
/// names a day key (« 25 décembre 2026 »).
export function blockedConfirm(
  change: BlockedChange,
  fmt: (dayKey: string) => string,
): { title: string; lines: string[]; confirm: string; destructive: boolean } {
  const adds = change.added.length;
  const removes = change.removed.length;
  if (removes === 0) {
    return adds === 1
      ? {
          title: "Bloquer cette date ?",
          lines: [`Le ${fmt(change.added[0])}, votre salon n’acceptera aucune réservation.`],
          confirm: "Bloquer",
          destructive: true,
        }
      : {
          title: "Bloquer ces dates ?",
          lines: [
            `Votre salon n’acceptera aucune réservation pendant ces ${countFr(adds, "journée", "journées")}.`,
          ],
          confirm: `Bloquer ${countFr(adds, "date", "dates")}`,
          destructive: true,
        };
  }
  if (adds === 0) {
    // Opening your calendar destroys nothing (the app passes
    // isDestructive: false here).
    return removes === 1
      ? {
          title: "Débloquer cette date ?",
          lines: [`Le ${fmt(change.removed[0])}, votre salon acceptera de nouveau des réservations.`],
          confirm: "Débloquer",
          destructive: false,
        }
      : {
          title: "Débloquer ces dates ?",
          lines: [
            `Votre salon acceptera de nouveau des réservations pendant ces ${countFr(removes, "journée", "journées")}.`,
          ],
          confirm: `Débloquer ${countFr(removes, "date", "dates")}`,
          destructive: false,
        };
  }
  return {
    title: "Modifier vos dates bloquées ?",
    lines: [
      countFr(adds, "date sera bloquée", "dates seront bloquées"),
      countFr(removes, "date sera débloquée", "dates seront débloquées"),
    ],
    confirm: "Enregistrer",
    destructive: true,
  };
}

/// The line after a write — the app's snackbar (D7).
export function blockedSavedSummary(change: BlockedChange): string {
  return [
    change.added.length > 0 ? countFr(change.added.length, "date bloquée", "dates bloquées") : "",
    change.removed.length > 0
      ? countFr(change.removed.length, "date débloquée", "dates débloquées")
      : "",
  ]
    .filter(Boolean)
    .join(" · ");
}

