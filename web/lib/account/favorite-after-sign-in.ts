/// A heart a guest tapped, carried across the sign-in and applied once they
/// are back (docs/design/consumer-signin-push.md §14, decision 205 — the
/// app's `heart_after_sign_in.dart`, web-shaped).
///
/// **Two keys, both needed (§14.3).** This tab stored the heart
/// (`sessionStorage`), and the address says the person is coming back from the
/// sign-in that heart opened (`suite=favori`). The address alone could be
/// forged by a link; the stored heart alone would fire on a later visit, after
/// a sign-in the heart never opened.

/// The marker `returnTo` carries back from `/connexion`.
export const AFTER_SIGN_IN_PARAM = 'suite';
export const AFTER_SIGN_IN_VALUE = 'favori';

/// How long a stored heart waits for its sign-in: an e-mail code, or an
/// account created on the way, fits; a tab left open until tomorrow does not.
export const FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS = 30 * 60 * 1000;

/// What the app says when the salon already was a favourite
/// (`heart_after_sign_in.dart`): nothing is sent, since a toggle would have
/// removed it.
export const FAVORITE_ALREADY = 'Déjà dans vos favoris';

const STORAGE_KEY = 'myweli.favoriApresConnexion';

/// Remembers the heart in this tab and returns the sign-in to open: with its
/// reason, and a `returnTo` that is `back` plus the marker. Storage refused (a
/// private window, blocked storage) stores nothing, and the heart is then not
/// applied: the page behaves as it did before A3w.
export function signInForFavorite(
  providerId: string,
  back: string,
  now: number = Date.now(),
): string {
  try {
    window.sessionStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ id: providerId, at: now }),
    );
  } catch {
    // Nothing stored: no heart to apply.
  }
  const sep = back.includes('?') ? '&' : '?';
  const returnTo = `${back}${sep}${AFTER_SIGN_IN_PARAM}=${AFTER_SIGN_IN_VALUE}`;
  return `/connexion?raison=favori&returnTo=${encodeURIComponent(returnTo)}`;
}

/// Called once the page's favourites read has answered. When the address
/// carries the marker: removes it (the other parameters stay), forgets the
/// stored heart, and returns its salon id if it is fresh. Without the marker
/// it does nothing and returns null — the heart waits for its own return.
export function takeFavoriteAfterSignIn(now: number = Date.now()): string | null {
  const { pathname, search, hash } = window.location;
  const params = new URLSearchParams(search);
  if (params.get(AFTER_SIGN_IN_PARAM) !== AFTER_SIGN_IN_VALUE) return null;

  params.delete(AFTER_SIGN_IN_PARAM);
  const rest = params.toString();
  // Next 14.2 syncs its router with the native call; nothing is fetched.
  window.history.replaceState(null, '', `${pathname}${rest ? `?${rest}` : ''}${hash}`);

  let raw: string | null;
  try {
    raw = window.sessionStorage.getItem(STORAGE_KEY);
    window.sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    return null;
  }
  return freshId(raw, now);
}

function freshId(raw: string | null, now: number): string | null {
  if (!raw) return null;
  let stored: unknown;
  try {
    stored = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof stored !== 'object' || stored === null) return null;
  const { id, at } = stored as { id?: unknown; at?: unknown };
  if (typeof id !== 'string' || id.length === 0) return null;
  if (typeof at !== 'number' || !Number.isFinite(at)) return null;
  const age = now - at;
  return age >= 0 && age <= FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS ? id : null;
}
