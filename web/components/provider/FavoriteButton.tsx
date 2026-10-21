'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { addFavorite, getFavorites, removeFavorite } from '../../lib/api/account';
import { writeFailureMessage } from '../../lib/api/network';
import { announceFavorite } from '../../lib/account/favorite-toast';
import { useToast } from '../../lib/useToast';
import { Toast } from '../Toast';

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
  const { toast, show, dismiss } = useToast();

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
  // <body>: back on it once the answer is in — the failure, or the toast's
  // success — never stolen from elsewhere.
  useEffect(() => {
    if (busy) return;
    const active = document.activeElement;
    if (!active || active === document.body) buttonRef.current?.focus();
  }, [busy]);

  /// Says what it did, with « Annuler » (B5.4, decision 16 —
  /// docs/design/web-client-polish.md §2.4).
  async function toggle() {
    const next = !fav;
    if (await write(next)) {
      announceFavorite(show, dismiss, next, () => void write(!next));
    }
  }

  async function write(next: boolean): Promise<boolean> {
    setError(null);
    setBusy(true);
    const r = next
      ? await addFavorite(providerId)
      : await removeFavorite(providerId);
    setBusy(false);
    if (r.status === 401) {
      router.push(`/connexion?returnTo=${encodeURIComponent(`/${slug}`)}`);
      return false;
    }
    if (r.ok) setFav(next);
    else setError(writeFailureMessage(r.status));
    return r.ok;
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
      <Toast toast={toast} />
    </>
  );
}
