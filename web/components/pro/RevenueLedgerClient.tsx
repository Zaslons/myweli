'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '../Button';
import { ChipButton } from '../Chip';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { SkeletonRows } from '../Skeleton';
import { type ProProfile, getMyProvider, getRevenueLedger } from '../../lib/api/pro';
import { type LoadFailure, loadFailure, loadFailureMessage } from '../../lib/api/load-failure';
import { SALON_TZ, salonDayKey, salonToday } from '../../lib/time';
import {
  NO_ARTIST,
  REVENUE_AXES,
  REVENUE_LEDGER_STATUSES,
  type RevenueAxis,
  type RevenueLedgerRow,
  type RevenueLedgerStatus,
  type RevenueQuery,
  periodAddress,
  provisionalRevenueTitle,
  readRevenueAddress,
  revenueDetailHref,
  revenueOverviewHref,
  revenueQuery,
  revenueSearch,
} from '../../lib/pro/revenue';
import {
  DELETED_SERVICE_LABEL,
  FORMER_ARTIST_LABEL,
  NO_ARTIST_LABEL,
  revenueAppointments,
  revenueChannelLabel,
  revenueLedgerStatusLabel,
} from '../../lib/pro/revenue-wording';
import { RevenueLedgerTable } from './revenue/RevenueLedgerTable';

/// The server takes an `asOf` from the last 24 hours only (§7.2): an older
/// link — a page left open overnight — asks the server's now instead
/// (§21.1 item 11).
const AS_OF_MAX_AGE_MS = 23 * 60 * 60 * 1000;

const PAGE_SIZE = 20;

type Ledger = {
  items: RevenueLedgerRow[];
  page: number;
  total: number;
  asOf: string | null;
  loading: boolean;
  loadingMore: boolean;
  error: LoadFailure | false;
  moreError: LoadFailure | false;
  refused: boolean;
};

/// « Rendez-vous » — the bookings behind a figure
/// (docs/design/pro-revenue-analytics.md §4.9, §5.1): « Terminés » (default)
/// · « À venir » · « À clôturer » · « Absents » · « Annulés », pages of 20
/// with « Afficher plus » (a control, and announced — no infinite scroll).
/// « À venir » soonest first; the others newest first — the server's order.
/// Each row opens the booking; coming back (Back) reloads the page.
export function RevenueLedgerClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [initError, setInitError] = useState<LoadFailure | false>(false);
  const [query, setQuery] = useState<RevenueQuery | null>(null);
  const [status, setStatus] = useState<RevenueLedgerStatus>('completed');
  const [asOf, setAsOf] = useState<string | null>(null);
  /// The detail this ledger was opened from (`depuis`).
  const [origin, setOrigin] = useState<RevenueAxis | null>(null);
  const [ledger, setLedger] = useState<Ledger | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const seq = useRef(0);
  /// Whether the address named its salon — rewritten only if it did (a
  /// rewrite on arrival is a navigation, and Next's route announcer would
  /// read the page title out loud).
  const salonInAddress = useRef(false);

  const load = useCallback(
    async (pid: string, q: RevenueQuery, s: RevenueLedgerStatus, at: string | null) => {
      const mine = ++seq.current;
      setLedger({
        items: [],
        page: 0,
        total: 0,
        asOf: at,
        loading: true,
        loadingMore: false,
        error: false,
        moreError: false,
        refused: false,
      });
      const r = await getRevenueLedger(pid, q, { status: s, page: 1, pageSize: PAGE_SIZE, asOf: at });
      if (mine !== seq.current) return;
      if (r.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      const base = { loadingMore: false, moreError: false as const };
      if (r.status === 403) {
        setLedger({ items: [], page: 0, total: 0, asOf: at, loading: false, error: false, refused: true, ...base });
        return;
      }
      if (r.status !== 200 || !r.ledger) {
        setLedger({
          items: [],
          page: 0,
          total: 0,
          asOf: at,
          loading: false,
          error: loadFailure(r.status),
          refused: false,
          ...base,
        });
        return;
      }
      setLedger({
        items: r.ledger.items,
        page: 1,
        total: r.ledger.total,
        // The next pages count against the same instant as the first.
        asOf: r.ledger.asOf,
        loading: false,
        error: false,
        refused: false,
        ...base,
      });
    },
    [router],
  );

  useEffect(() => {
    let active = true;
    (async () => {
      setInitError(false);
      const me = await getMyProvider();
      if (!active) return;
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (me.status !== 200 || !me.profile) {
        setInitError(loadFailure(me.status));
        return;
      }
      const p = me.profile;
      const tz = p.provider.timezone ?? SALON_TZ;
      const addr = readRevenueAddress(window.location.search, salonToday(new Date(), tz));
      const q = revenueQuery({
        period: addr.period,
        date: addr.date,
        from: addr.from,
        to: addr.to,
        compare: addr.compare ?? 'previous',
        artistId: addr.artistId,
        serviceId: addr.serviceId,
        channel: addr.channel,
      });
      // Another salon's bookings: back to « Revenus » of this one (§22).
      if (addr.salon && addr.salon !== p.provider.id) {
        router.replace(revenueOverviewHref(q));
        return;
      }
      const age = addr.asOf ? Date.now() - Date.parse(addr.asOf) : null;
      const at = age != null && age >= 0 && age <= AS_OF_MAX_AGE_MS ? addr.asOf : null;
      salonInAddress.current = addr.salon != null;
      setProfile(p);
      setQuery(q);
      setStatus(addr.status);
      setAsOf(at);
      setOrigin(addr.origin);
      void load(p.provider.id, q, addr.status, at);
    })();
    return () => {
      active = false;
    };
  }, [reloadKey, load, router]);

  // The filter lives in the address — replaced, so Back leaves the page.
  useEffect(() => {
    if (!profile || !query) return;
    const search = revenueSearch({
      ...periodAddress(query),
      artistId: query.artistId,
      serviceId: query.serviceId,
      channel: query.channel,
      status,
      asOf,
      origin,
      salon: salonInAddress.current ? profile.provider.id : null,
    });
    if (search !== window.location.search) {
      window.history.replaceState(null, '', `${window.location.pathname}${search}`);
    }
  }, [profile, query, status, asOf, origin]);

  function choose(s: RevenueLedgerStatus) {
    if (s === status || !profile || !query) return;
    setStatus(s);
    void load(profile.provider.id, query, s, asOf);
  }

  async function more() {
    if (!profile || !query || !ledger || ledger.loadingMore) return;
    const mine = seq.current;
    setLedger({ ...ledger, loadingMore: true, moreError: false });
    const r = await getRevenueLedger(profile.provider.id, query, {
      status,
      page: ledger.page + 1,
      pageSize: PAGE_SIZE,
      asOf: ledger.asOf,
    });
    if (mine !== seq.current) return;
    if (r.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    setLedger((l) =>
      l == null
        ? l
        : r.status === 200 && r.ledger
          ? {
              ...l,
              items: [...l.items, ...r.ledger.items],
              page: l.page + 1,
              total: r.ledger.total,
              loadingMore: false,
            }
          : { ...l, loadingMore: false, moreError: loadFailure(r.status) },
    );
  }

  // ── Where these bookings come from ───────────────────────────────────────

  const keyOf = (q: RevenueQuery, ax: RevenueAxis): string | null =>
    ax === 'artist' ? q.artistId : ax === 'service' ? q.serviceId : q.channel;

  /// The detail these bookings were opened from: the address says it
  /// (`depuis`, the detail's own row) — inside a detail, the other filter is
  /// its parent, so « the first filter » would open the mirror page (found by
  /// the review: Awa → Tresses → « Voir tout » → « ← » landed on Awa's page
  /// filtered by Tresses). Without it (a hand-typed address), the first filter.
  const filterAxis: RevenueAxis | null = query
    ? origin && keyOf(query, origin) != null
      ? origin
      : (REVENUE_AXES.find((ax) => keyOf(query, ax) != null) ?? null)
    : null;

  /// A filter, named from the live team and catalogue (the ledger's answer
  /// has no label; no name ever rides in the address, §22).
  function nameOf(q: RevenueQuery, ax: RevenueAxis): string | null {
    if (ax === 'artist' && q.artistId) {
      return q.artistId === NO_ARTIST
        ? NO_ARTIST_LABEL
        : (profile?.provider.artists?.find((x) => x.id === q.artistId)?.name ?? FORMER_ARTIST_LABEL);
    }
    if (ax === 'service' && q.serviceId) {
      return profile?.provider.services?.find((x) => x.id === q.serviceId)?.name ?? DELETED_SERVICE_LABEL;
    }
    if (ax === 'channel' && q.channel) return revenueChannelLabel(q.channel);
    return null;
  }

  /// The filters' names, the page's own row first.
  function names(q: RevenueQuery): string[] {
    const order = filterAxis ? [filterAxis, ...REVENUE_AXES.filter((ax) => ax !== filterAxis)] : REVENUE_AXES;
    return order.map((ax) => nameOf(q, ax)).filter((n): n is string => n != null);
  }

  const tz = profile?.provider.timezone ?? SALON_TZ;
  const today = salonDayKey(asOf ? new Date(asOf) : new Date(), tz);
  const subtitle = query
    ? [...names(query), provisionalRevenueTitle(query, today)].filter(Boolean).join(' · ')
    : '';

  /// Back to the page these bookings were opened from, on the same period.
  const backHref = query
    ? filterAxis
      ? revenueDetailHref(
          filterAxis,
          keyOf(query, filterAxis),
          {
            ...query,
            ...(filterAxis === 'artist'
              ? { artistId: null }
              : filterAxis === 'service'
                ? { serviceId: null }
                : { channel: null }),
          },
          profile?.provider.id ?? '',
        )
      : revenueOverviewHref(query)
    : '/pro/revenus';

  const header = (
    <header>
      <Link
        href={backHref}
        className="-ml-s inline-flex min-h-12 items-center rounded-control px-s text-bodyMedium text-textSecondary hover:bg-surfaceVariant"
      >
        <span aria-hidden="true">←&nbsp;</span>
        {query && filterAxis ? nameOf(query, filterAxis) : 'Revenus'}
      </Link>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Rendez-vous</h1>
      {subtitle ? <p className="mt-xs break-words text-bodyMedium text-textSecondary">{subtitle}</p> : null}
    </header>
  );

  if (initError) {
    return (
      <div>
        {header}
        <div className="mt-l">
          <ErrorState
            message={loadFailureMessage(initError, 'Chargement impossible.')}
            onRetry={() => setReloadKey((k) => k + 1)}
          />
        </div>
      </div>
    );
  }

  return (
    <div>
      {header}
      {ledger?.refused ? (
        <div className="mt-l">
          <EmptyState
            icon="lock"
            title="Réservé au propriétaire"
            description="Seul le propriétaire du salon voit les revenus."
          />
        </div>
      ) : (
        <>
          <div role="group" aria-label="Statut des rendez-vous" className="mt-l flex flex-wrap gap-s">
            {REVENUE_LEDGER_STATUSES.map((s) => (
              <ChipButton key={s} selected={s === status} aria-pressed={s === status} onClick={() => choose(s)}>
                {revenueLedgerStatusLabel(s)}
              </ChipButton>
            ))}
          </div>
          <div className="mt-m">
            {!profile || !ledger || ledger.loading ? (
              <>
                <p role="status" className="sr-only">
                  Chargement des rendez-vous…
                </p>
                <SkeletonRows count={6} />
              </>
            ) : ledger.error ? (
              <ErrorState
                message={loadFailureMessage(ledger.error, 'Chargement impossible.')}
                onRetry={() => query && void load(profile.provider.id, query, status, asOf)}
              />
            ) : (
              <>
                <RevenueLedgerTable
                  rows={ledger.items}
                  salon={profile.provider.id}
                  timezone={tz}
                  status={status}
                />
                {ledger.items.length > 0 ? (
                  <div className="mt-m flex flex-col items-center gap-s">
                    {/* Announced when « Afficher plus » adds a page. */}
                    <p role="status" className="text-bodySmall text-textTertiary">
                      {`${ledger.items.length} sur ${revenueAppointments(ledger.total)}`}
                    </p>
                    {ledger.moreError ? (
                      <p role="alert" className="text-bodySmall text-error">
                        {loadFailureMessage(ledger.moreError, 'Chargement impossible. Réessayez.')}
                      </p>
                    ) : null}
                    {ledger.items.length < ledger.total ? (
                      <Button variant="secondary" isLoading={ledger.loadingMore} onClick={() => void more()}>
                        Afficher plus
                      </Button>
                    ) : null}
                  </div>
                ) : null}
              </>
            )}
          </div>
        </>
      )}
    </div>
  );
}
