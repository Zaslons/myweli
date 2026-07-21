import { Chip } from './Chip';
import { statusLabelFr } from '../lib/account/appointments';

/// The shared status chip (§11.2, B7) — the web twin of the admin console's
/// `StatusChip.forStatus(String)`: **kind, not color, is the API.** The kind
/// mapping mirrors mobile's `AdminChipKind` (status_chip.dart), widened to the
/// complete cross-surface inventory (appointments, KYC, subscription, team,
/// salon) so every surface speaks one tint language.
///
/// Before B7 the status pills were all NEUTRAL gray — « En attente » looked
/// exactly like « Terminé ». The kind tints are the app journal's own
/// STATUS_STYLE language, product-wide (owner decision).
export type StatusKind = 'ok' | 'pending' | 'danger' | 'neutral';

const OK = new Set(['verified', 'active', 'confirmed', 'resolved', 'paid', 'arrived']);
const PENDING = new Set(['pending', 'open', 'trial', 'invited', 'grace']);
const DANGER = new Set([
  'rejected', 'suspended', 'banned', 'hidden', 'cancelled', 'noshow', 'expired', 'revoked',
]);

export function statusChipKind(status: string | null | undefined): StatusKind {
  const s = (status ?? '').toLowerCase().replace(/[_\s-]/g, '');
  if (OK.has(s)) return 'ok';
  if (PENDING.has(s)) return 'pending';
  if (DANGER.has(s)) return 'danger';
  return 'neutral';
}

const KIND_TINT: Record<Exclude<StatusKind, 'neutral'>, string> = {
  ok: 'success',
  pending: 'warning',
  danger: 'error',
};

/** French labels beyond the appointment vocabulary (`statusLabelFr`). */
const EXTRA_FR: Record<string, string> = {
  verified: 'Vérifié',
  active: 'Actif',
  resolved: 'Résolu',
  paid: 'Payé',
  arrived: 'Arrivé',
  open: 'Ouvert',
  trial: 'Essai',
  invited: 'Invitation envoyée',
  grace: 'Période de grâce',
  rejected: 'Rejeté',
  suspended: 'Suspendu',
  banned: 'Banni',
  hidden: 'Masqué',
  expired: 'Expirée',
  revoked: 'Accès révoqué',
  draft: 'Brouillon',
};

export function statusChipLabel(status: string): string {
  const viaAppointments = statusLabelFr(status);
  if (viaAppointments !== status) return viaAppointments;
  return EXTRA_FR[status] ?? EXTRA_FR[status.toLowerCase()] ?? status;
}

export function StatusChip({
  status,
  label,
  dense = false,
  className = '',
}: {
  status: string;
  /** Overrides the derived French label (a caller-specific phrasing). */
  label?: string;
  dense?: boolean;
  className?: string;
}) {
  const kind = statusChipKind(status);
  return kind === 'neutral' ? (
    <Chip variant="neutral" dense={dense} className={className}>
      {label ?? statusChipLabel(status)}
    </Chip>
  ) : (
    <Chip variant="tinted" tint={KIND_TINT[kind]} dense={dense} className={className}>
      {label ?? statusChipLabel(status)}
    </Chip>
  );
}
