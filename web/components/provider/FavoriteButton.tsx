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
  // success — never stolen from elsewhere. Only after a call: on load nothing
  // has run, and taking the focus then scrolled the salon page 317px at 320×568,
  // off its cover (docs/design/web-swiss-salon.md §1.4).
  const called = useRef(false);
  useEffect(() => {
    if (busy) {
      called.current = true;
      return;
    }
    if (!called.current) return;
    called.current = false;
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
        className="inline-flex min-h-12 items-center gap-xs rounded-control border border-primary bg-secondary px-m text-labelLarge font-medium text-textPrimary hover:bg-surfaceVariant"
      >
        <span aria-hidden="true">{fav ? '♥' : '♡'}</span>
        {fav ? 'Favori' : 'Ajouter aux favoris'}
      </button>
      {error ? (
        <p role="alert" className="mt-xs text-bodyMedium text-error">
          {error}
        </p>
      ) : null}
      {/* Lifted above the salon page's booking bar under `lg`: at 24px it stood on the bar,
          and at 320 « Annuler » took a corner of « Réserver ». The lift is in rem, as the bar's
          height is, so at rest it stays clear with the browser's font at 200 % (a 32px root;
          web-swiss-salon.md §1.4), though not with Android's larger text, which grows the bar
          and not the lift. That is the toast's home: the bar is a
          `data-floating-control` (ProviderView), so where it still comes near the pill (at the
          page's end, stopped above the footer, or with text enlarged otherwise) the toast is
          measured against it and moved clear of it: just above it or just below it, whichever is
          the shorter move (Toast.tsx, B11.5). Only a screen too short to hold both leaves
          them meeting. */}
      <Toast toast={toast} aboveBookingBar />
    </>
  );
}
