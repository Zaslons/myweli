/// Pure helpers for the consumer account bookings view. Unit-tested.

export type Appointment = {
  id: string;
  status: string;
  appointmentDate: string;
  durationMinutes?: number;
  totalPrice?: number;
  depositAmount?: number;
  balanceDue?: number;
  cancellationWindowHours?: number;
  providerId: string;
  providerName?: string;
  providerSlug?: string;
  serviceNames?: string[];
  salonEntered?: boolean;
};

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
