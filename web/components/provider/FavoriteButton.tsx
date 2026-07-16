'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { addFavorite, getFavorites, removeFavorite } from '../../lib/api/account';

/// Favorite toggle on the public provider page (client island). Reads the user's
/// favorites for initial state; not signed in → /connexion.
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

  async function toggle() {
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
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={busy}
      aria-pressed={fav}
      className="inline-flex items-center gap-xs rounded-lg border border-border bg-secondary px-m py-s text-labelLarge font-medium text-textPrimary hover:bg-surfaceVariant"
    >
      <span aria-hidden="true">{fav ? '♥' : '♡'}</span>
      {fav ? 'Favori' : 'Ajouter aux favoris'}
    </button>
  );
}
