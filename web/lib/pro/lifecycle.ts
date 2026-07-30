/// Pro lifecycle actions per status — mirrors the app's « Détails du rendez-vous ».
/// Pure; unit-tested.

import { type Membership, hasCap } from './team';

export type LifecycleAction = 'accept' | 'reject' | 'complete' | 'no-show';

export type ActionDef = {
  action: LifecycleAction;
  label: string;
  variant?: 'primary' | 'secondary';
  confirm?: string; // when set, ask before running
};

export function actionsFor(status: string): ActionDef[] {
  if (status === 'pending') {
    return [
      { action: 'accept', label: 'Accepter', variant: 'primary' },
      { action: 'reject', label: 'Refuser', variant: 'secondary' },
    ];
  }
  if (status === 'confirmed') {
    return [
      { action: 'complete', label: 'Marquer comme terminé', variant: 'primary' },
      {
        action: 'no-show',
        label: 'Marquer comme absent',
        variant: 'secondary',
        confirm: 'Le client ne s’est pas présenté ?',
      },
    ];
  }
  return []; // completed / cancelled / noShow → terminal
}

/// Team access R5b: the role-shaped action set. Full journal rights (or the
/// legacy null membership) keep everything; own-scope only (Collaborateur)
/// mirrors the server's T40 rule — no accept/reject (whole-journal acts),
/// Terminé/Absent on their own confirmed bookings; no journal rights → none.
export function actionsForMembership(
  status: string,
  membership: Membership | null | undefined,
): ActionDef[] {
  if (!membership || hasCap(membership, 'journal.manage.all')) {
    return actionsFor(status);
  }
  if (hasCap(membership, 'journal.manage.own')) {
    return status === 'confirmed' ? actionsFor(status) : [];
  }
  return [];
}
