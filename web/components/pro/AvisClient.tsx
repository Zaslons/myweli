'use client';

import Image from 'next/image';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Review } from '../../lib/api/providers';
import { getMyProvider, listProviderReviews } from '../../lib/api/pro';
import { formatDateFr } from '../../lib/format';
import { reviewStats } from '../../lib/pro/reviews';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';

/// « Avis » (docs/design/web-pro-reviews.md) — the pro app's ReviewsScreen,
/// web-adapted: summary card (average + 5→1 distribution) over the review
/// list, paginated « Charger plus ». Read-only, like the app.
export function AvisClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  const [items, setItems] = useState<Review[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  // The active salon's timezone (multi-pays MP3) — review dates in SALON time.
  const [salonTz, setSalonTz] = useState<string | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(true);
      setLoading(false);
      return;
    }
    const pid = me.profile.provider.id;
    setProviderId(pid);
    setSalonTz(me.profile.provider.timezone ?? undefined);
    const r = await listProviderReviews(pid, 1);
    if (r.status !== 200) {
      setError(true);
      setLoading(false);
      return;
    }
    setItems(r.items);
    setTotal(r.total);
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
        <ErrorState title="Avis" message="Impossible de charger les avis." onRetry={load} />
      </div>
    );
  }

  const stats = reviewStats(items);

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
          <section className="mt-l flex flex-wrap items-center gap-l rounded-xl border border-border bg-secondary p-l">
            <div>
              <p className="text-headlineMedium font-semibold text-textPrimary">
                ★ {stats.average.toFixed(1)}
              </p>
              <p className="mt-xs text-bodyMedium text-textSecondary">
                {total} avis
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
          </section>

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
                      <p
                        className="text-bodyMedium text-primary"
                        aria-label={`${r.rating} étoiles sur 5`}
                      >
                        {'★'.repeat(Math.round(r.rating))}
                        <span className="text-textTertiary">
                          {'★'.repeat(5 - Math.round(r.rating))}
                        </span>
                      </p>
                    </div>
                    <p className="mt-xs text-bodySmall text-textTertiary">
                      {formatDateFr(r.createdAt, salonTz)}
                      {r.serviceName ? ` · ${r.serviceName}` : ''}
                      {r.artistName ? ` · avec ${r.artistName}` : ''}
                    </p>
                    {r.text ? (
                      <p className="mt-s text-bodyMedium text-textSecondary">{r.text}</p>
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
