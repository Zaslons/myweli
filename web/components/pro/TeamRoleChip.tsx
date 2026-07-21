import { ROLE_LABELS, type TeamRole } from '../../lib/pro/team';
import { Chip } from '../Chip';

/// The role chip (team access R5a). Propriétaire = the gold accent (the only
/// privileged tone) · Manager = filled · Réception/Collaborateur = outlined.
/// B6: a <Chip> caller — the old py-[2px] ds-ignore died with the hand-rolled
/// pill (Chip's py-xs is on the 4px grid).
export function TeamRoleChip({ role }: { role: TeamRole }) {
  const variant =
    role === 'owner' ? 'gold' : role === 'manager' ? 'filled' : 'outlined';
  return <Chip variant={variant}>{ROLE_LABELS[role]}</Chip>;
}
