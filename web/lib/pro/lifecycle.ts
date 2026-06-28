/// Pro lifecycle actions per status — mirrors the app's « Détails du rendez-vous ».
/// Pure; unit-tested.

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
