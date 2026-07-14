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
};

/// The « Réserver à nouveau » link, carrying the rebook prefill (K2). The hub
/// sanitizes the ids against the live catalogue.
export function rebookHref(a: Appointment): string | null {
  if (!a.providerSlug) return null;
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
export function canReschedule(a: Appointment): boolean {
  return (
    (a.status === 'pending' || a.status === 'confirmed') &&
    Date.parse(a.appointmentDate) > Date.now()
  );
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
