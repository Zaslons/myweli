'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { addFavorite, getFavorites, removeFavorite } from '../../lib/api/account';
import { writeFailureMessage } from '../../lib/api/network';

/// Favorite toggle on the public provider page (client island). Reads the user's
/// favorites for initial state; not signed in → /connexion. Like the app's
/// heart it waits for the server; a refusal keeps the state and says why under
/// the button (docs/design/web-consumer-optimistic-revert.md §3.2 ④).
export function FavoriteButton({
  providerId,
  slug,
}: {
  providerId: string;
  slug: string;
}) {
  const router = useRouter();
  const [fav, setFav] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      const r = await getFavorites();
      if (active && r.status === 200) {
        setFav(r.favorites.some((f) => f.id === providerId));
      }
    })();
    return () => {
      active = false;
    };
  }, [providerId]);

  // The button was disabled while the call was out, which can drop focus to
  // <body>: back on it with the failure, never stolen from elsewhere.
  useEffect(() => {
    if (!error) return;
    const active = document.activeElement;
    if (!active || active === document.body) buttonRef.current?.focus();
  }, [error]);

  async function toggle() {
    setError(null);
    setBusy(true);
    const next = !fav;
    const r = next
      ? await addFavorite(providerId)
      : await removeFavorite(providerId);
    setBusy(false);
    if (r.status === 401) {
      router.push(`/connexion?returnTo=${encodeURIComponent(`/${slug}`)}`);
      return;
    }
    if (r.ok) setFav(next);
    else setError(writeFailureMessage(r.status));
  }

  return (
    <>
      <button
        ref={buttonRef}
        type="button"
        onClick={toggle}
        disabled={busy}
        aria-pressed={fav}
        className="inline-flex min-h-12 items-center gap-xs rounded-lg border border-borderStrong bg-secondary px-m text-labelLarge font-medium text-textPrimary hover:bg-surfaceVariant"
      >
        <span aria-hidden="true">{fav ? '♥' : '♡'}</span>
        {fav ? 'Favori' : 'Ajouter aux favoris'}
      </button>
      {error ? (
        <p role="alert" className="mt-xs text-bodyMedium text-error">
          {error}
        </p>
      ) : null}
    </>
  );
}
