'use client';

import { useState } from 'react';
import type { Review } from '../../lib/api/providers';
import { reportReview } from '../../lib/account/review-photos';
import { formatDateFr } from '../../lib/format';
import { Button } from '../Button';
import { Lightbox } from '../Lightbox';

/// Public review list (parity 2.13/2.14): photo thumbnails + a fullscreen
/// lightbox, and the consumer « Signaler » action (FR-REV-005 — anonymous
/// visitors get a login prompt; the endpoint is idempotent per reporter).
export function ReviewList({
  reviews,
  rating,
  reviewCount,
  slug,
  tz,
}: {
  reviews: Review[];
  rating: number;
  reviewCount: number;
  slug: string;
  /// The salon's timezone (multi-pays MP3) — review dates in SALON time.
  tz?: string | null;
}) {
  const [lightbox, setLightbox] = useState<string | null>(null);

  if (reviewCount === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">
        Avis ({reviewCount})
      </h2>
      <p className="mt-xs text-sm text-textSecondary">
        ★ {rating.toFixed(1)} sur 5
      </p>
      <ul className="mt-m space-y-m">
        {reviews.map((r) => (
          <li key={r.id} className="rounded-lg bg-secondary p-m">
            <div className="flex justify-between">
              <span className="font-medium text-textPrimary">{r.userName}</span>
              <span className="text-sm text-textTertiary">★ {r.rating}</span>
            </div>
            {r.text ? (
              <p className="mt-xs text-sm text-textSecondary">{r.text}</p>
            ) : null}
            {r.photoUrls && r.photoUrls.length > 0 ? (
              <div className="mt-s flex gap-s overflow-x-auto">
                {r.photoUrls.map((url) => (
                  <button
                    key={url}
                    type="button"
                    onClick={() => setLightbox(url)}
                    aria-label="Agrandir la photo"
                    className="shrink-0"
                  >
                    {/* User content — plain img (no domain allowlist). */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={url}
                      alt="Photo de l’avis"
                      className="h-16 w-16 rounded-lg object-cover"
                      loading="lazy"
                    />
                  </button>
                ))}
              </div>
            ) : null}
            <div className="mt-xs flex items-center justify-between gap-m">
              <p className="text-xs text-textTertiary">
                {formatDateFr(r.createdAt, tz ?? undefined)}
              </p>
              <ReportAction reviewId={r.id} slug={slug} />
            </div>
          </li>
        ))}
      </ul>

      {lightbox ? (
        <Lightbox
          url={lightbox}
          label="Photo de l’avis"
          onClose={() => setLightbox(null)}
        />
      ) : null}
    </section>
  );
}

/// « Signaler » — inline optional-reason form; 401 → login prompt.
function ReportAction({ reviewId, slug }: { reviewId: string; slug: string }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [state, setState] = useState<'idle' | 'done' | 'auth' | 'error'>(
    'idle',
  );

  async function send() {
    setBusy(true);
    const r = await reportReview(reviewId, reason);
    setBusy(false);
    if (r.ok) {
      setState('done');
      setOpen(false);
      return;
    }
    setState(r.status === 401 ? 'auth' : 'error');
  }

  if (state === 'done') {
    return (
      <p className="text-xs text-textSecondary">
        Merci. Notre équipe va examiner cet avis.
      </p>
    );
  }

  return (
    <div className="text-right">
      {!open ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="text-xs text-textTertiary underline"
        >
          Signaler
        </button>
      ) : (
        <div className="mt-xs w-full rounded-lg bg-surface p-s text-left">
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={500}
            placeholder="Raison (optionnel)"
            aria-label="Raison du signalement"
            className="w-full rounded-lg border border-border bg-secondary px-s py-xs text-sm text-textPrimary"
          />
          <div className="mt-s flex justify-end gap-s">
            <Button variant="secondary" onClick={() => setOpen(false)}>
              Annuler
            </Button>
            <Button disabled={busy} onClick={send}>
              Signaler
            </Button>
          </div>
        </div>
      )}
      {state === 'auth' ? (
        <p className="mt-xs text-xs text-textSecondary">
          <a href={`/connexion?returnTo=/${slug}`} className="underline">
            Connectez-vous
          </a>{' '}
          pour signaler cet avis.
        </p>
      ) : state === 'error' ? (
        <p className="mt-xs text-xs text-error">
          Le signalement a échoué. Réessayez.
        </p>
      ) : null}
    </div>
  );
}
