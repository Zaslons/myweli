'use client';

import Image from 'next/image';
import { Card } from '../Card';
import { Rating } from '../Rating';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Review } from '../../lib/api/providers';
import { getMyProvider, listProviderReviews, reportSalonReview } from '../../lib/api/pro';
import { NO_CONNECTION_MESSAGE } from '../../lib/api/network';
import { hasCap } from '../../lib/pro/team';
import { focusOnMount } from '../../lib/focusOnMount';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { formatDateFr } from '../../lib/format';
import { type ReviewSummary, reviewStats, statsFromSummary } from '../../lib/pro/reviews';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';

/// « Avis » (docs/design/web-pro-reviews.md) — the pro app's ReviewsScreen,
/// web-adapted: summary card (average + 5→1 distribution) over the review
/// list, paginated « Charger plus ». The salon may report a review
/// (« Signaler » — B6.6, App Store 1.2: docs/design/backend-integrity-batch6.md
/// §2.6), the Propriétaire and the Gérant only, as in the app.
export function AvisClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [items, setItems] = useState<Review[]>([]);
  const [total, setTotal] = useState(0);
  // The whole salon's card, from the server (salon-reviews-summary.md).
  const [summary, setSummary] = useState<ReviewSummary | undefined>(undefined);
  const [page, setPage] = useState(1);
  // The active salon's timezone (multi-pays MP3) — review dates in SALON time.
  const [salonTz, setSalonTz] = useState<string | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<LoadFailure | false>(false);
  const [busy, setBusy] = useState(false);
  // « Signaler » is the Propriétaire's and the Gérant's (`profile.manage`,
  // decision 20) — read off this page's own /me, like every page gate.
  const [canReport, setCanReport] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(loadFailure(me.status));
      setLoading(false);
      return;
    }
    const pid = me.profile.provider.id;
    setProviderId(pid);
    setCanReport(hasCap(me.profile.membership, 'profile.manage'));
    setSalonTz(me.profile.provider.timezone ?? undefined);
    const r = await listProviderReviews(pid, 1);
    if (r.status !== 200) {
      setError(loadFailure(r.status));
      setLoading(false);
      return;
    }
    setItems(r.items);
    setTotal(r.total);
    setSummary(r.summary);
    setPage(1);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  async function loadMore() {
    if (!providerId) return;
    setBusy(true);
    const r = await listProviderReviews(providerId, page + 1);
    setBusy(false);
    if (r.status !== 200) return;
    setItems((prev) => [...prev, ...r.items]);
    setPage((p) => p + 1);
  }

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (error) {
    return (
      <div>
        <ErrorState
          title="Avis"
          message={loadFailureMessage(error, 'Impossible de charger les avis.')}
          onRetry={load}
        />
      </div>
    );
  }

  // The server's card when it sends one — the WHOLE salon. The loaded pages
  // (50 at a time) only list: averaging them beside the server's total told a
  // salon with 60 reviews a note from 50 (docs/design/salon-reviews-summary.md).
  const stats = summary ? statsFromSummary(summary) : reviewStats(items);
  const shownCount = summary ? summary.count : total;

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Avis</h1>

      {items.length === 0 ? (
        <EmptyState
          className="mt-l"
          icon="star"
          title="Aucun avis"
          description="Les avis de vos clients apparaîtront ici."
        />
      ) : (
        <>
          {/* Summary card — the app's average + 5→1 distribution */}
          <Card as="section" className="mt-l flex flex-wrap items-center gap-l">
            <div>
              <p className="text-headlineMedium font-semibold text-textPrimary">
                <Rating value={stats.average} />
              </p>
              <p className="mt-xs text-bodyMedium text-textSecondary">
                {shownCount} avis
              </p>
            </div>
            <dl className="min-w-56 flex-1">
              {stats.distribution.map((d) => (
                <div key={d.rating} className="flex items-center gap-s py-xs">
                  <dt className="w-8 shrink-0 text-bodyMedium text-textSecondary">
                    {d.rating} ★
                  </dt>
                  <dd className="flex flex-1 items-center gap-s">
                    <div
                      className="h-2 flex-1 overflow-hidden rounded-pill bg-surface"
                      role="progressbar"
                      aria-label={`${d.rating} étoiles`}
                      aria-valuenow={d.count}
                      aria-valuemin={0}
                      aria-valuemax={stats.count}
                    >
                      <div
                        className="h-full rounded-pill bg-primary"
                        style={{ width: `${d.pct}%` }}
                      />
                    </div>
                    <span className="w-6 shrink-0 text-right text-bodyMedium text-textSecondary">
                      {d.count}
                    </span>
                  </dd>
                </div>
              ))}
            </dl>
          </Card>

          {/* Review cards */}
          <ul className="mt-m space-y-s">
            {items.map((r) => (
              <li
                key={r.id}
                className="rounded-xl border border-border bg-secondary p-m"
              >
                <div className="flex items-start gap-m">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-pill bg-surface font-medium text-textPrimary">
                    {(r.userName || '?').slice(0, 1).toUpperCase()}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center justify-between gap-s">
                      <p className="font-medium text-textPrimary">
                        {r.userName}
                      </p>
                      <p className="text-bodyMedium text-primary">
                        <span aria-hidden="true">
                          {'★'.repeat(Math.round(r.rating))}
                          <span className="text-textTertiary">
                            {'★'.repeat(5 - Math.round(r.rating))}
                          </span>
                        </span>{' '}
                        <span className="text-textSecondary">{r.rating}/5</span>
                      </p>
                    </div>
                    <p className="mt-xs text-bodySmall text-textTertiary">
                      {formatDateFr(r.createdAt, salonTz)}
                      {r.serviceName ? ` · ${r.serviceName}` : ''}
                      {r.artistName ? ` · avec ${r.artistName}` : ''}
                    </p>
                    {r.text ? (
                      <p className="mt-s text-bodyLarge text-textSecondary">{r.text}</p>
                    ) : null}
                    {(r.photoUrls ?? []).length > 0 ? (
                      <div className="mt-s flex flex-wrap gap-s">
                        {(r.photoUrls ?? []).map((url) => (
                          <Image
                            key={url}
                            src={url}
                            alt="Photo de l’avis"
                            width={96}
                            height={96}
                            className="h-24 w-24 rounded-lg object-cover"
                          />
                        ))}
                      </div>
                    ) : null}
                    {canReport ? (
                      <SalonReportAction
                        reviewId={r.id}
                        onSessionGone={() => router.replace('/pro/connexion')}
                      />
                    ) : null}
                  </div>
                </div>
              </li>
            ))}
          </ul>

          {items.length < total ? (
            <div className="mt-m">
              <Button variant="secondary" isLoading={busy} onClick={loadMore}>
                Charger plus
              </Button>
            </div>
          ) : null}
        </>
      )}
    </div>
  );
}

/// « Signaler » on one review — the client's form and words (ReviewList's
/// `ReportAction`): an optional reason, then « Merci. Notre équipe va examiner
/// cet avis. ». No answer says so; a dead session goes to the login.
function SalonReportAction({
  reviewId,
  onSessionGone,
}: {
  reviewId: string;
  onSessionGone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [state, setState] = useState<'idle' | 'done' | 'error' | 'offline'>('idle');

  async function send() {
    setBusy(true);
    const r = await reportSalonReview(reviewId, reason);
    setBusy(false);
    if (r.ok) {
      setState('done');
      setOpen(false);
      return;
    }
    if (r.status === 401) return onSessionGone();
    setState(r.status === 0 ? 'offline' : 'error');
  }

  if (state === 'done') {
    return (
      <p ref={focusOnMount} tabIndex={-1} className="mt-s text-bodySmall text-textSecondary">
        Merci. Notre équipe va examiner cet avis.
      </p>
    );
  }

  return (
    <div className="mt-s">
      {!open ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="-my-sm inline-flex min-h-12 items-center text-bodySmall text-textTertiary underline"
        >
          Signaler
        </button>
      ) : (
        <div className="w-full rounded-lg bg-surface p-s">
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={500}
            placeholder="Raison (optionnel)"
            aria-label="Raison du signalement"
            className="min-h-12 w-full rounded-lg border border-borderStrong bg-secondary px-s py-xs text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
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
      {state === 'error' || state === 'offline' ? (
        <p role="alert" className="mt-xs text-bodySmall text-error">
          {state === 'offline' ? NO_CONNECTION_MESSAGE : 'Le signalement a échoué. Réessayez.'}
        </p>
      ) : null}
    </div>
  );
}
