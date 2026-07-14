import { ROLE_LABELS, type TeamRole } from '../../lib/pro/team';

/// The role chip (team access R5a). Propriétaire = filled gold accent (the
/// only privileged tone) · Manager = filled neutral · Réception/Collaborateur
/// = outline. Tokens only.
export function TeamRoleChip({ role }: { role: TeamRole }) {
  const styles: Record<TeamRole, string> = {
    owner: 'bg-gold/15 text-textPrimary border border-gold/40',
    manager: 'bg-primary text-secondary',
    reception: 'border border-border text-textSecondary',
    staff: 'border border-border text-textSecondary',
  };
  return (
    <span
      className={`inline-flex items-center rounded-full px-s py-[2px] text-xs font-medium ${styles[role]}`}
    >
      {ROLE_LABELS[role]}
    </span>
  );
}
