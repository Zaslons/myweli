import { salonDayKey, salonToday } from "../time";

/// The bookable window on web (A14d) — the mirror of mobile's
/// `SlotPicker._emptyReason`, kept as a pure function so both consumer surfaces
/// classify identically and a test can reach it without rendering anything.
///
/// **Why the client classifies at all, when the server is the authority.** The
/// server refuses; only the client can *explain*. The salon's window rides
/// `provider.availability` on every provider read, so naming the condition
/// costs no request and no new response shape. §12 requires an empty state to
/// say WHY, with an action wherever one can fix it — and « Aucun créneau
/// disponible » says nothing while implying the salon is full.
export type EmptyReason = "past" | "beyondHorizon" | "tooSoon" | "full";

/// Fallbacks when a provider payload predates A14d. They mirror
/// `backend/lib/src/appointments/booking_window.dart`, which is the authority,
/// and mobile's `booking_horizons.dart` — all three must agree or the same
/// salon reaches differently depending on the surface.
export const DEFAULT_HORIZON_DAYS = 365;
export const DEFAULT_NOTICE_MINUTES = 60;

/// Days are compared as `YYYY-MM-DD` salon days, where lexicographic order IS
/// chronological order — no `Date` arithmetic, so no DST drift and no
/// device-timezone leak.
export function shiftSalonDay(ymd: string, days: number, tz?: string): string {
  // Noon anchors the instant far from either midnight, so adding whole days
  // cannot land on the wrong side of a DST transition before it is re-read in
  // the salon's zone.
  const at = new Date(`${ymd}T12:00:00.000Z`);
  at.setUTCDate(at.getUTCDate() + days);
  return salonDayKey(at, tz);
}

export function lastBookableDay(horizonDays: number, tz?: string): string {
  return shiftSalonDay(salonToday(new Date(), tz), horizonDays, tz);
}

/// The salon day containing the earliest instant a client may still book.
export function firstBookableDay(noticeMinutes: number, tz?: string): string {
  return salonDayKey(new Date(Date.now() + noticeMinutes * 60_000), tz);
}

/// Why did this day come back with nothing?
///
/// Claimed only when CERTAIN: `full` is the catch-all and absorbs closed
/// weekdays, blocked dates and genuine capacity, so a day is never mislabelled
/// a window breach. The reverse — calling a window breach « full » — is the
/// defect this exists to end.
export function emptyReason(params: {
  date: string;
  horizonDays: number;
  noticeMinutes: number;
  tz?: string;
}): EmptyReason {
  const { date, horizonDays, noticeMinutes, tz } = params;
  // A day already gone is not « too soon » — that sentence is about a delay
  // before a start and reads as nonsense on a past date.
  if (date < salonToday(new Date(), tz)) return "past";
  // Horizon first, mirroring the server's ordering. The both-at-once case is
  // unreachable: the API refuses a notice past the horizon as invalid_input.
  if (date > lastBookableDay(horizonDays, tz)) return "beyondHorizon";
  if (date < firstBookableDay(noticeMinutes, tz)) return "tooSoon";
  return "full";
}

/// « 2 h », « 48 h », « 1 h 30 » — the delay, spoken the way the pro set it.
export function formatNotice(minutes: number): string {
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h} h` : `${h} h ${m}`;
}

/// What a refused booking/reschedule actually means, in French (A14d).
///
/// **Six surfaces said some version of « someone else just took your slot »,
/// and four of them read only the HTTP status** — so `beyond_horizon` and
/// `too_soon`, which A14d's backend added precisely to be distinguishable,
/// rendered as a lie: the slot was never taken, the date is outside what the
/// salon accepts, and « choisissez-en un autre » invites the user to retry a
/// time that can never succeed.
///
/// The code was always available — `lib/api/account.ts` and `lib/api/pro.ts`
/// both return `{ ok, status, error }`. Only one call site read it.
/// [taken] is the surface's OWN « the slot went » sentence and [fallback] its
/// own generic failure — both are passed in rather than centralised, because
/// they are not the same sentence everywhere and should not become one: a pro
/// moving someone else's booking reads « Créneau indisponible », a client
/// losing their own reads « Ce créneau vient d'être pris ». A first draft of
/// this function collapsed all of them into the consumer wording and an e2e
/// test that pins the pro's caught it. **This adds two codes; it does not
/// rewrite the three sentences that were already right.**
///
/// **Row 82 added [audience], and it does NOT contradict the paragraph above.**
/// That argument is about `taken`/`fallback`, which vary by *situation* — what
/// went wrong differs per surface, so the surface supplies the words. Who is
/// reading is a different axis: a closed two-value one, the same shape as
/// `teamErrorMessage(code, ctx)` in `lib/pro/team.ts`. The two provider codes
/// need it because one wire code has two correct sentences — a client hitting
/// a stale link is shopping, a salon owner whose salon was stopped is not.
/// Centralising those IS right, because they must not drift apart.
export function conflictMessage(
  error: string | undefined,
  {
    audience,
    taken,
    fallback,
  }: { audience: "client" | "salon"; taken: string; fallback: string },
): string {
  switch (error) {
    case "beyond_horizon":
      return "Ce salon n’accepte pas encore les réservations à cette date.";
    case "too_soon":
      return "Ce salon demande plus de délai avant un rendez-vous. Choisissez une date plus tardive.";
    case "slot_unavailable":
      return taken;
    // Row 82. The tense carries the whole distinction: « pas encore » has
    // never been live, « ne … plus » was stopped. Neither says « Réessayez » —
    // retrying fixes neither, and §12's retry control is carved out for
    // exactly this (A14's doctrine, now stated in SYSTEM.md §12).
    case "provider_not_published":
      return audience === "salon"
        ? // Unreachable from the salon's own manual booking, which row 82's
          // Decision A now allows for a draft — kept honest rather than
          // silently falling through to a client sentence if that ever changes.
          "Votre salon n’est pas encore en ligne."
        : "Ce salon n’accepte pas encore de réservations en ligne.";
    case "provider_suspended":
      return audience === "salon"
        ? "Votre salon est suspendu. Contactez Myweli pour le réactiver — vos rendez-vous sont intacts."
        : "Ce salon ne prend plus de rendez-vous sur Myweli.";
    default:
      return fallback;
  }
}

/// The way out, for the refusals that have one (§12, row 82).
///
/// Modelled on `teamErrorCta` (`lib/pro/team.ts`): a second pure function on
/// the same code, so the sentence and the action cannot drift apart, and the
/// component stores the CODE rather than the message.
///
/// **Only the two provider codes.** A taken slot is fixed by choosing another
/// time at the same salon — sending that client away would be wrong, and the
/// null arm is what keeps the CTA from becoming unconditional.
export function bookingErrorCta(
  code?: string,
): { label: string; href: string } | null {
  if (code === "provider_not_published" || code === "provider_suspended") {
    // The phrase and the destination both already ship, in `AccountClient`'s
    // two empty states. Reusing them rather than minting « Découvrir d'autres
    // salons » — §17 says the product has one way to say a thing.
    return { label: "Découvrir des salons", href: "/" };
  }
  return null;
}
