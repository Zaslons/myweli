/// Pure helpers for the consumer account bookings view. Unit-tested.

import { formatFcfa } from '../format';
import { SALON_TZ, salonDayKey, salonFormatter } from '../time';

export type Appointment = {
  id: string;
  status: string;
  appointmentDate: string;
  durationMinutes?: number;
  totalPrice?: number;
  depositAmount?: number;
  depositScreenshotUrl?: string | null;
  balanceDue?: number;
  cancellationWindowHours?: number;
  providerId: string;
  providerName?: string;
  providerSlug?: string;
  providerPhone?: string | null;
  providerWhatsapp?: string | null;
  notes?: string | null;
  artistName?: string | null;
  // K2: rebook prefill + the detail's deposit-attach block.
  serviceIds?: string[];
  artistId?: string | null;
  depositMobileMoneyOperator?: string | null;
  depositMobileMoneyNumber?: string | null;
  serviceNames?: string[];
  salonEntered?: boolean;
  /// Multi-pays carriers: `currency` is stamped at booking creation (MP1 —
  /// immutable, the Fresha rule); the provider* fields ride the enrichment
  /// so the account renders the SALON's clock, money and country label.
  currency?: string | null;
  providerTimezone?: string | null;
  providerCurrency?: string | null;
  providerCountryCode?: string | null;
  providerAddress?: string | null;
  /// The salon's lifecycle state, enriched onto the caller's OWN booking
  /// (`salon-state-and-refusals.md` §5, Decision C).
  ///
  /// Absent means live: a salon with no stored status is active, and a
  /// pre-enrichment payload has no field. `salonIsLive` is the one place that
  /// decides — spelling it `=== 'active'` at a call site would hide
  /// « Réserver à nouveau » on every seeded salon.
  providerStatus?: 'draft' | 'active' | 'suspended' | null;
  /// The salon's own booking window (A14d), so the reschedule pane asks the
  /// salon's rule rather than falling back to a year. The server substitutes
  /// the documented defaults, so a stopped salon cannot silently widen it.
  providerBookingHorizonDays?: number;
  providerMinimumNoticeMinutes?: number;
};

/// Is this booking's salon still taking appointments?
export function salonIsLive(a: Appointment): boolean {
  return !a.providerStatus || a.providerStatus === 'active';
}

/// What to tell a client whose salon has stopped, from a STATUS.
///
/// **The tense carries the distinction** (§6): « pas encore » for a salon that
/// has never published, « ne … plus » for one that has been stopped. These are
/// the same two sentences `conflictMessage` returns for the booking refusals —
/// one product fact reached from two directions, so it must be one wording.
///
/// Null for a live salon, for an absent status (which means live), and for any
/// status this build does not know: it fails OPEN, exactly as `isPublicSalon`
/// does on the server, so a lifecycle state invented later cannot start
/// telling clients a salon has stopped.
export function salonStoppedMessageFor(
  status: string | null | undefined,
): string | null {
  if (status === 'draft') {
    return 'Ce salon n’accepte pas encore de réservations en ligne.';
  }
  if (status === 'suspended') {
    return 'Ce salon ne prend plus de rendez-vous sur MyWeli.';
  }
  return null;
}

/// The same answer for a booking, read off its enriched salon status.
export function salonStoppedMessage(a: Appointment): string | null {
  return salonStoppedMessageFor(a.providerStatus);
}

/// The « Réserver à nouveau » link, carrying the rebook prefill (K2). The hub
/// sanitizes the ids against the live catalogue.
export function rebookHref(a: Appointment): string | null {
  // A salon that stopped would refuse the booking, and its public page is
  // about to 404 — a link that always fails is a dead end with a button on it
  // (§12 as amended by row 82).
  if (!a.providerSlug || !salonIsLive(a)) return null;
  const qs = new URLSearchParams();
  if (a.serviceIds && a.serviceIds.length > 0) {
    qs.set('services', a.serviceIds.join(','));
  }
  if (a.artistId) qs.set('artist', a.artistId);
  const q = qs.toString();
  return `/${a.providerSlug}/reserver${q ? `?${q}` : ''}`;
}

/// The pay-later window: a pending booking with a deposit still awaiting its
/// payment proof (mirrors the app's deposit sheet availability).
export function canAttachDeposit(a: Appointment): boolean {
  return (
    a.status === 'pending' &&
    (a.depositAmount ?? 0) > 0 &&
    !a.depositScreenshotUrl &&
    !a.salonEntered
  );
}

export type Tab = 'upcoming' | 'past' | 'cancelled';

export const TABS: { key: Tab; label: string }[] = [
  { key: 'upcoming', label: 'À venir' },
  { key: 'past', label: 'Passés' },
  { key: 'cancelled', label: 'Annulés' },
];

/// A status as `StatusChip` reads it: lower case, without `_`, `-` or spaces,
/// so `noShow`, `no_show`, `NO_SHOW` and `no-show` are one status.
export function normalizedStatus(status: string | null | undefined): string {
  return (status ?? '').toLowerCase().replace(/[_\s-]/g, '');
}

/// Is the booking's time strictly after `now`? Exactly at now is past, as in
/// the app (`isAfter`). A date that does not parse is never ahead.
function isAhead(a: Appointment, now: Date): boolean {
  return Date.parse(a.appointmentDate) > now.getTime();
}

/// Where a client's own booking is listed in « Mes rendez-vous » — the app's
/// table, the same on both surfaces (docs/design/web-account-bookings-truth.md
/// §2.1; mobile `client_booking_rule.dart`). Both suites read the table from
/// docs/design/fixtures/client-booking-rule.json.
///
/// | Booking                        | Tab      | Chip         |
/// |--------------------------------|----------|--------------|
/// | pending, time after now        | À venir  | En attente   |
/// | confirmed, time after now      | À venir  | Confirmé     |
/// | pending, time now or past      | Passés   | Non confirmé |
/// | confirmed, time now or past    | Passés   | Confirmé     |
/// | completed, any time            | Passés   | Terminé      |
/// | noShow, any time               | Passés   | Absent       |
/// | cancelled                      | Annulés  | Annulé       |
///
/// Nothing on the server closes a booking by itself: only the salon marks it
/// « Terminé » or « Absent ». A status this build does not know is placed by
/// its date, never hidden (the app cannot meet one: its status is an enum).
///
/// Client-only. The Espace pro reads the stored status — a past pending
/// booking is work still to do there — and a test keeps these helpers out of
/// `components/pro`, `lib/pro` and `app/pro`.
export function clientTab(a: Appointment, now: Date = new Date()): Tab {
  const s = normalizedStatus(a.status);
  if (s === 'cancelled') return 'cancelled';
  if (s === 'completed' || s === 'noshow') return 'past';
  return isAhead(a, now) ? 'upcoming' : 'past';
}

/// One tab's bookings, in the app's order: « À venir » soonest first,
/// « Passés » and « Annulés » newest first. Two bookings at the same time
/// keep the server's order (the sort is stable).
export function bookingsForTab(
  items: Appointment[],
  tab: Tab,
  now: Date = new Date(),
): Appointment[] {
  const sign = tab === 'upcoming' ? 1 : -1;
  return items
    .filter((a) => clientTab(a, now) === tab)
    .sort(
      (a, b) =>
        sign * (Date.parse(a.appointmentDate) - Date.parse(b.appointmentDate)) ||
        0,
    );
}

/// The salon never answered and the time has passed: MyWeli does not know
/// whether the visit happened, so it says only what it knows (decision 166).
/// Not in `STATUS_FR`: that map is shared with the Espace pro, where the same
/// booking is still « En attente ».
export const UNCONFIRMED_PAST_LABEL = 'Non confirmé';

function isUnconfirmedPast(a: Appointment, now: Date): boolean {
  return normalizedStatus(a.status) === 'pending' && !isAhead(a, now);
}

/// What a client's status chip says by its colour — always with its words.
/// The app's `AppChipTone` names, for the four tones a client sees.
export type ClientTone = 'warning' | 'success' | 'neutral' | 'error';

const CLIENT_TONE: Record<string, ClientTone> = {
  pending: 'warning',
  confirmed: 'success',
  completed: 'neutral',
  cancelled: 'error',
  noshow: 'error',
};

/// The chip's words for a client's own booking: « Non confirmé » for a past
/// booking nobody confirmed, else the status's own label. A status this build
/// does not know shows as it came.
export function clientStatusLabel(a: Appointment, now: Date = new Date()): string {
  if (isUnconfirmedPast(a, now)) return UNCONFIRMED_PAST_LABEL;
  return STATUS_FR_NORMALIZED[normalizedStatus(a.status)] ?? a.status;
}

/// The chip's tone: « Non confirmé » is neutral, since nothing is awaited any
/// more; every other chip keeps its status tone. Unknown is neutral.
export function clientStatusTone(
  a: Appointment,
  now: Date = new Date(),
): ClientTone {
  if (isUnconfirmedPast(a, now)) return 'neutral';
  return CLIENT_TONE[normalizedStatus(a.status)] ?? 'neutral';
}

/// One month of « Passés », in the SALON's calendar.
export type MonthGroup = {
  /// `YYYY-MM`, the salon's month.
  key: string;
  /// « novembre 2026 » — shown upper-case by CSS, read as words.
  label: string;
  items: Appointment[];
};

/// Group bookings by month, newest month first and newest booking first
/// within each month. The month is the one of the card's own date line: the
/// salon's zone (`providerTimezone`, else `SALON_TZ`). A booking at 23:30 UTC
/// on 31 October at a salon in Libreville (UTC+1) is on 1 November there.
export function groupByMonth(items: Appointment[]): MonthGroup[] {
  const groups = new Map<string, MonthGroup>();
  for (const a of items) {
    const tz = a.providerTimezone ?? SALON_TZ;
    const at = new Date(a.appointmentDate);
    const key = salonDayKey(at, tz).slice(0, 7);
    let g = groups.get(key);
    if (!g) {
      g = {
        key,
        label: salonFormatter({ month: 'long', year: 'numeric' }, tz).format(at),
        items: [],
      };
      groups.set(key, g);
    }
    g.items.push(a);
  }
  const newestFirst = (a: Appointment, b: Appointment) =>
    Date.parse(b.appointmentDate) - Date.parse(a.appointmentDate) || 0;
  return [...groups.values()]
    .map((g) => ({ ...g, items: [...g.items].sort(newestFirst) }))
    .sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
}

/// The « Passés » summary (decision 167): only bookings the salon marked
/// « Terminé » count. Null when there are none, so the page never reads
/// « 0 visite » above a list of past bookings.
///
/// The amount is in the NEWEST visit's currency, the app's MVP rule: a
/// mixed-currency history adds nominally (per-currency totals come after MP2).
/// Before migration 0047 (B14.1) the server stored no `currency`, so older
/// payloads carry only `providerCurrency`; from it on, each booking's own
/// stamp (docs/design/appointment-currency-stamp.md).
export function visitSummary(
  items: Appointment[],
): { count: number; total: number; currency: string | undefined } | null {
  const done = items
    .filter((a) => normalizedStatus(a.status) === 'completed')
    .sort(
      (a, b) =>
        Date.parse(b.appointmentDate) - Date.parse(a.appointmentDate) || 0,
    );
  if (done.length === 0) return null;
  const newest = done[0];
  return {
    count: done.length,
    total: done.reduce((sum, a) => sum + (a.totalPrice ?? 0), 0),
    currency: newest.currency ?? newest.providerCurrency ?? undefined,
  };
}

/// Is this booking still ahead of the client — live, not past, not closed?
///
/// **Split out of `canReschedule`, which was answering two questions.** Three
/// call sites used it: the reschedule control (which really does mean « can
/// this be moved »), the calendar-export block, and the « prochaines visites »
/// card — and the last two only ever meant « upcoming ». The distinction did
/// not matter until a salon could be stopped: a client whose salon shut down
/// must keep the calendar entry and keep seeing the visit listed, while the
/// move is refused.
///
/// A1w: the status check stays (`pending` or `confirmed`, as spelled), THEN
/// the client rule decides the time. So it answers exactly as before for every
/// status — an unknown status, which `clientTab` may file under « À venir »,
/// is never upcoming here and never gets « Reporter ».
export function isUpcoming(a: Appointment, now: Date = new Date()): boolean {
  return (
    (a.status === 'pending' || a.status === 'confirmed') &&
    clientTab(a, now) === 'upcoming'
  );
}

/// « Reporter » (parity 1.1 — the app's rule): pending/confirmed AND in the
/// future, at a salon still taking appointments.
export function canReschedule(a: Appointment, now: Date = new Date()): boolean {
  // The server refuses a move at a stopped salon (`provider_suspended` /
  // `provider_not_published`); withholding the control is a courtesy OVER that
  // gate, never instead of it.
  return isUpcoming(a, now) && salonIsLive(a);
}

export function canCancel(a: Appointment): boolean {
  return a.status === 'pending' || a.status === 'confirmed';
}

/// What a client is told about a deposit before cancelling, or null when there
/// is nothing to say (docs/design/web-true-sentences.md §3).
///
/// **It states the salon's rule, and promises nothing of its own.** The deposit
/// is between the client and the salon: the server only records the cancellation
/// (no refund logic), and the CGU say MyWeli « ne rembourse aucun fonds ». Same
/// cut-off as the app's `cancellation_policy.dart`: exactly at it counts as late.
export function cancellationNotice(
  a: Appointment,
  now: Date = new Date(),
  currency?: string,
): string | null {
  const deposit = a.depositAmount ?? 0;
  if (deposit <= 0 || a.salonEntered) return null;
  if (!a.depositScreenshotUrl) {
    return 'Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.';
  }
  const hours = a.cancellationWindowHours;
  if (hours == null) {
    return 'Le remboursement de votre acompte dépend de la règle du salon. Voyez directement avec lui\u00a0: MyWeli ne détient aucun acompte.';
  }
  const amount = formatFcfa(deposit, currency);
  const at = Date.parse(a.appointmentDate);
  const kept = `D’après la règle du salon, votre acompte de ${amount} ne sera pas remboursé, car`;
  if (now.getTime() >= at) return `${kept} l’heure du rendez-vous est passée.`;
  if (now.getTime() >= at - hours * 3_600_000) {
    return `${kept} vous annulez moins de ${hours}\u00a0h avant.`;
  }
  const when = hours === 0 ? 'avant l’heure du rendez-vous' : `plus de ${hours}\u00a0h avant`;
  return `D’après la règle du salon, votre acompte de ${amount} vous revient, car vous annulez ${when}. Voyez avec le salon pour le récupérer\u00a0: MyWeli ne détient aucun acompte.`;
}

const STATUS_FR: Record<string, string> = {
  pending: 'En attente',
  confirmed: 'Confirmé',
  completed: 'Terminé',
  cancelled: 'Annulé',
  noShow: 'Absent', // app label
  no_show: 'Absent', // alias (defensive)
};

export function statusLabelFr(status: string): string {
  return STATUS_FR[status] ?? status;
}

/// The same five labels keyed by `normalizedStatus`, for the client chip.
const STATUS_FR_NORMALIZED: Record<string, string> = Object.fromEntries(
  Object.entries(STATUS_FR).map(([k, v]) => [normalizedStatus(k), v]),
);
