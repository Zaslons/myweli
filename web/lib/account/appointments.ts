/// Pure helpers for the consumer account bookings view. Unit-tested.

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

export function categorize(status: string): Tab {
  if (status === 'completed') return 'past';
  // Canonical statuses: pending/confirmed/completed/cancelled/noShow (reject → cancelled).
  if (status === 'cancelled' || status === 'noShow' || status === 'no_show') {
    return 'cancelled';
  }
  return 'upcoming'; // pending | confirmed
}

export function filterByTab(items: Appointment[], tab: Tab): Appointment[] {
  return items.filter((a) => categorize(a.status) === tab);
}

/// « Reporter » (parity 1.1 — the app's rule): pending/confirmed AND in the
/// future.
/// Is this booking still ahead of the client — live, not past, not closed?
///
/// **Split out of `canReschedule`, which was answering two questions.** Three
/// call sites used it: the reschedule control (which really does mean « can
/// this be moved »), the calendar-export block, and the « prochaines visites »
/// card — and the last two only ever meant « upcoming ». The distinction did
/// not matter until a salon could be stopped: a client whose salon shut down
/// must keep the calendar entry and keep seeing the visit listed, while the
/// move is refused.
export function isUpcoming(a: Appointment): boolean {
  return (
    (a.status === 'pending' || a.status === 'confirmed') &&
    Date.parse(a.appointmentDate) > Date.now()
  );
}

export function canReschedule(a: Appointment): boolean {
  // The server refuses a move at a stopped salon (`provider_suspended` /
  // `provider_not_published`); withholding the control is a courtesy OVER that
  // gate, never instead of it.
  return isUpcoming(a) && salonIsLive(a);
}

export function canCancel(a: Appointment): boolean {
  return a.status === 'pending' || a.status === 'confirmed';
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
