import type { ToastAction, ToastKind } from '../useToast';

/// What a ♥ that worked says — the app's snack (`provider_card.dart`,
/// `provider_detail_screen.dart`): what happened, and « Annuler », which
/// writes the opposite (decision 16, docs/design/web-client-polish.md §2.4).
/// The ♥ itself stays a way back, so the toast's 10 s are not a trap.
export const FAVORITE_ADDED = 'Ajouté aux favoris';
export const FAVORITE_REMOVED = 'Retiré des favoris';

type Show = (message: string, kind?: ToastKind, action?: ToastAction) => void;

export function announceFavorite(
  show: Show,
  dismiss: () => void,
  added: boolean,
  undo: () => void,
): void {
  show(added ? FAVORITE_ADDED : FAVORITE_REMOVED, 'success', {
    label: 'Annuler',
    onAction: () => {
      // An action taken has done its job; the undo says its own outcome.
      dismiss();
      undo();
    },
  });
}
