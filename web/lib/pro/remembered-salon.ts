import { type KeyStore, safeLocalStore } from './browser-push';

/// The salon this browser last acted in — so that « Votre accès à {salon} a
/// été retiré. » still names it after a reload, as the app does (decision 14,
/// docs/design/web-pro-truthful-failure.md §2.4). The membership context
/// writes it at every profile it receives; its in-memory salon still wins.
///
/// Its id and PUBLIC name only — no client data. Forgotten at every sign-out
/// that lands AND at every sign-in: the server's `not_a_member` names no
/// salon, so the browser cannot check that the one it kept is the one
/// withdrawn — what makes it right is that it can only have been written by
/// the account now signed in.
export type RememberedSalon = { id: string; name: string };

export const REMEMBERED_SALON_KEY = 'myweli_pro_last_salon';

export function rememberSalon(
  salon: RememberedSalon,
  store: KeyStore = safeLocalStore(),
): void {
  // A salon with nothing to call it: the one kept before is not this one,
  // so it goes — never a name for the wrong salon.
  if (!salon.id || !salon.name) return forgetSalon(store);
  try {
    store.set(
      REMEMBERED_SALON_KEY,
      JSON.stringify({ id: salon.id, name: salon.name }),
    );
  } catch {
    /* nothing to keep it in */
  }
}

/// What was kept — or null: nothing, or something that is not a salon.
export function rememberedSalon(
  store: KeyStore = safeLocalStore(),
): RememberedSalon | null {
  try {
    const raw = store.get(REMEMBERED_SALON_KEY);
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<RememberedSalon> | null;
    if (
      v &&
      typeof v.id === 'string' &&
      v.id &&
      typeof v.name === 'string' &&
      v.name
    ) {
      return { id: v.id, name: v.name };
    }
  } catch {
    /* unreadable: nothing kept */
  }
  return null;
}

export function forgetSalon(store: KeyStore = safeLocalStore()): void {
  try {
    store.remove(REMEMBERED_SALON_KEY);
  } catch {
    /* nothing to remove */
  }
}
