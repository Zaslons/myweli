/// Pro lifecycle actions per status — mirrors the app's « Détails du rendez-vous ».
/// Pure; unit-tested.

import { type Membership, hasCap } from './team';

export type LifecycleAction = 'accept' | 'reject' | 'complete' | 'no-show';

export type ActionDef = {
  action: LifecycleAction;
  label: string;
  variant?: 'primary' | 'secondary';
  confirm?: boolean; // when set, ask before running (NO_SHOW_CONFIRM)
};

/// Where the booking stands against the clock. Only `started` matters today:
/// « absent » before the start is not something a salon can know.
export type ActionTiming = { started: boolean };

/// Has the booking's start passed? Two instants — no salon-clock arithmetic,
/// so the timezone cannot get it wrong. An unreadable date has NOT started:
/// the act this gates is irreversible, so the doubt goes to not offering it.
export function hasStarted(appointmentDate: string, now: Date = new Date()): boolean {
  const start = Date.parse(appointmentDate);
  return !Number.isNaN(start) && start <= now.getTime();
}

/// The no-show confirmation — the app's dialog word for word
/// (`pro_appointment_detail_screen.dart:357-368`; docs/design/
/// web-pro-journal-panel-deposit.md §3 T10–T13). « Marquer absent » is not red:
/// a state change, not a deletion (SYSTEM.md §15; the app's
/// `isDestructive: false`).
export const NO_SHOW_CONFIRM = {
  title: 'Client absent ?',
  body: 'Le client ne s’est pas présenté.',
  /// True under no-custody: the salon received the deposit and keeps it;
  /// MyWeli never holds it. Said only when there IS a deposit.
  deposit: 'L’acompte est conservé selon votre politique d’annulation.',
  confirm: 'Marquer absent',
} as const;

export function noShowConfirmLines(depositAmount: number | undefined): string[] {
  return depositAmount && depositAmount > 0
    ? [NO_SHOW_CONFIRM.body, NO_SHOW_CONFIRM.deposit]
    : [NO_SHOW_CONFIRM.body];
}

/// « Marquer comme absent » only once the start is past, and always confirmed
/// — the app's detail screen (`:351`). The server takes a no-show on a future
/// booking and the state is terminal, so this guard is the only one.
export function actionsFor(status: string, { started }: ActionTiming): ActionDef[] {
  if (status === 'pending') {
    return [
      { action: 'accept', label: 'Accepter', variant: 'primary' },
      { action: 'reject', label: 'Refuser', variant: 'secondary' },
    ];
  }
  if (status === 'confirmed') {
    const complete: ActionDef = {
      action: 'complete',
      label: 'Marquer comme terminé',
      variant: 'primary',
    };
    if (!started) return [complete];
    return [
      complete,
      {
        action: 'no-show',
        label: 'Marquer comme absent',
        variant: 'secondary',
        confirm: true,
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
  timing: ActionTiming,
): ActionDef[] {
  if (!membership || hasCap(membership, 'journal.manage.all')) {
    return actionsFor(status, timing);
  }
  if (hasCap(membership, 'journal.manage.own')) {
    return status === 'confirmed' ? actionsFor(status, timing) : [];
  }
  return [];
}
