'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { type ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '../../Button';
import { ButtonLink } from '../../ButtonLink';
import { Card } from '../../Card';
import { DataTable } from '../../DataTable';
import { EmptyState } from '../../EmptyState';
import { ErrorState } from '../../ErrorState';
import { Skeleton } from '../../Skeleton';
import { Tabs } from '../../Tabs';
import { ChipButton } from '../../Chip';
import {
  type ProProfile,
  getMyProvider,
  getRevenueAnalytics,
  getRevenueLedger,
} from '../../../lib/api/pro';
import { type LoadFailure, loadFailure, loadFailureMessage } from '../../../lib/api/load-failure';
import { formatFcfa } from '../../../lib/format';
import { SALON_TZ, salonToday } from '../../../lib/time';
import {
  NO_ARTIST,
  REVENUE_AXES,
  type RevenueAddress,
  type RevenueAnalytics,
  type RevenueAxis,
  type RevenueCompare,
  type RevenueFigures,
  type RevenueGroup,
  type RevenueLedgerRow,
  type RevenuePeriod,
  type RevenueQuery,
  type RevenueRow,
  type RevenueSort,
  addRevenueDays,
  channelFromApi,
  isRevenueId,
  formatDayMonthShort,
  formatDayRange,
  formatMonthShort,
  formatMonthYear,
  formatWeekdayDayMonthShort,
  periodAddress,
  previousRevenuePeriod,
  nextRevenuePeriod,
  readRevenueAddress,
  revenueComparisonLabel,
  revenueDetailHref,
  revenueHasFuture,
  revenueIsFuture,
  revenueLatestDay,
  revenueLedgerHref,
  revenueOverviewHref,
  revenueQuery,
  revenueSearch,
  revenueToday,
  switchRevenuePeriod,
  withPeriod,
  REVENUE_MAX_DAYS,
} from '../../../lib/pro/revenue';
import {
  DELETED_SERVICE_LABEL,
  FORMER_ARTIST_LABEL,
  NO_ARTIST_LABEL,
  REVENUE_ESTIMATED_FOOTNOTE,
  REVENUE_PRICE_FOOTNOTE,
  REVENUE_SERVICES_FOOTNOTE,
  type RevenueDelta,
  formatPercent,
  revenueAbsences,
  revenueAppointments,
  revenueAxisKind,
  revenueAxisTitle,
  revenueChannelLabel,
  revenueCurrencyName,
  revenueDelta,
  revenueFilterLabel,
  revenueLabelOf,
  revenuePendingLine,
  revenueRateDelta,
  revenueSortName,
  revenueToCloseTitle,
  revenueUpcomingLine,
} from '../../../lib/pro/revenue-wording';
import { revenueCsv, revenueCsvFilename, rowsOf, sortRevenueRows } from '../../../lib/pro/revenue-rows';
import { BarSeries, BarSeriesTable } from './BarSeries';
import { DeltaBadge } from './DeltaBadge';
import { KpiGrid, type KpiTileData } from './KpiGrid';
import { PeriodBar } from './PeriodBar';
import { RangeDialog } from './RangeDialog';
import { RevenueLedgerTable } from './RevenueLedgerTable';
import { ShareBar } from './ShareBar';

/// The owner's choice of comparison, kept for the browser tab's session as
/// the app keeps it for the app's (§4.3) — never on disk, never a name.
const COMPARE_KEY = 'myweli.pro.revenus.comparer';

function sessionCompare(): RevenueCompare {
  try {
    const v = window.sessionStorage.getItem(COMPARE_KEY);
    return v === 'year' || v === 'none' ? v : 'previous';
  } catch {
    return 'previous';
  }
}

function rememberCompare(mode: RevenueCompare) {
  try {
    window.sessionStorage.setItem(COMPARE_KEY, mode);
  } catch {
    // A private window may refuse storage: the address still carries it.
  }
}

/// The axis the server names in `filters.label`: the first filter it has —
/// collaborateur, then prestation, then canal.
function labelledAxis(q: Pick<RevenueQuery, 'artistId' | 'serviceId' | 'channel'>): RevenueAxis | null {
  if (q.artistId) return 'artist';
  if (q.serviceId) return 'service';
  if (q.channel) return 'channel';
  return null;
}

function filterKeyOf(q: RevenueQuery, axis: RevenueAxis): string | null {
  return axis === 'artist' ? q.artistId : axis === 'service' ? q.serviceId : q.channel;
}

const ZERO: RevenueFigures = {
  completedAmount: 0,
  completedCount: 0,
  averageTicket: null,
  upcomingAmount: 0,
  upcomingCount: 0,
  pendingAmount: 0,
  pendingCount: 0,
  toCloseAmount: 0,
  toCloseCount: 0,
  noShowAmount: 0,
  noShowCount: 0,
  noShowRate: null,
  cancelledAmount: 0,
  cancelledCount: 0,
  estimated: false,
};

type View = {
  analytics: RevenueAnalytics | null;
  loading: boolean;
  error: LoadFailure | false;
  refused: boolean;
};

type Preview = { items: RevenueLedgerRow[]; loading: boolean; error: LoadFailure | false };

/// « Revenus » and each of its details (docs/design/pro-revenue-analytics.md
/// §5, §22) — the web twin of the app's `RevenueAnalyticsPage`: the period
/// bar, then the content in its state (§4.11). **The server owns every
/// figure** (§3): this page draws the answer and steps the calendar from it.
///
/// [axis] / [filterKey]: a detail's own row (from its path); null on the
/// overview. A detail's address may carry a second filter — a detail inside
/// a detail (§5.4).
export function RevenueAnalyticsView({
  axis = null,
  filterKey = null,
}: {
  axis?: RevenueAxis | null;
  filterKey?: string | null;
}) {
  const router = useRouter();
  const urlQuery = useSearchParams()?.toString() ?? '';

  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [initError, setInitError] = useState<LoadFailure | false>(false);
  const [query, setQuery] = useState<RevenueQuery | null>(null);
  const [tab, setTab] = useState<RevenueAxis | null>(null);
  const [sort, setSort] = useState<RevenueSort>('amount');
  const [view, setView] = useState<View>({
    analytics: null,
    loading: true,
    error: false,
    refused: false,
  });
  const [currency, setCurrency] = useState<string | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [listForm, setListForm] = useState(false);
  const [rangeOpen, setRangeOpen] = useState(false);
  /// The salon's today from the last answer (the provisional title).
  const [lastToday, setLastToday] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  /// Only the latest request may land: an older period's answer arriving
  /// late is dropped (§4.11 « Period change »).
  const seq = useRef(0);
  /// Addresses this page wrote and has not seen come back through the router.
  const echoes = useRef<string[]>([]);
  /// The address as the router last reported it.
  const seenUrl = useRef<string | null>(null);
  /// Whether the address named its salon. Rewritten only if it did: adding
  /// `salon=` to an address that arrived without it is a navigation, and
  /// Next's route announcer then reads the page title out loud on arrival
  /// (found by axe-spec's scan of a bare `/pro/revenus/collaborateurs/a1`).
  const salonInAddress = useRef(false);

  const providerId = profile?.provider.id ?? null;
  const tz = profile?.provider.timezone ?? SALON_TZ;

  const load = useCallback(
    async (pid: string, q: RevenueQuery) => {
      const mine = ++seq.current;
      setView({ analytics: null, loading: true, error: false, refused: false });
      setPreview(null);
      const r = await getRevenueAnalytics(pid, q);
      if (mine !== seq.current) return;
      if (r.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (r.status === 403) {
        setView({ analytics: null, loading: false, error: false, refused: true });
        return;
      }
      if (r.status !== 200 || !r.analytics) {
        setView({ analytics: null, loading: false, error: loadFailure(r.status), refused: false });
        return;
      }
      const a = r.analytics;
      setLastToday(revenueToday(a));
      setView({ analytics: a, loading: false, error: false, refused: false });
      // The latest five are a second, small request, after the figures and
      // only when something was completed (§21.1 item 5).
      const completed = a.groups.reduce((n, g) => n + g.current.completedCount, 0);
      if (completed === 0) return;
      setPreview({ items: [], loading: true, error: false });
      const l = await getRevenueLedger(pid, q, { status: 'completed', pageSize: 5, asOf: a.asOf });
      if (mine !== seq.current) return;
      setPreview(
        l.status === 200 && l.ledger
          ? { items: l.ledger.items, loading: false, error: false }
          : { items: [], loading: false, error: loadFailure(l.status) },
      );
    },
    [router],
  );

  /// The query an address asks, with this page's own filter.
  const queryOf = useCallback(
    (addr: RevenueAddress): RevenueQuery =>
      revenueQuery({
        period: addr.period,
        date: addr.date,
        from: addr.from,
        to: addr.to,
        compare: addr.compare ?? sessionCompare(),
        artistId: axis === 'artist' ? filterKey : axis ? addr.artistId : null,
        serviceId: axis === 'service' ? filterKey : axis ? addr.serviceId : null,
        channel:
          axis === 'channel'
            ? (filterKey as RevenueQuery['channel'])
            : axis
              ? addr.channel
              : null,
      }),
    [axis, filterKey],
  );

  /// Show what an address asks — on arrival, and when a link to this same
  /// page changes it (the sidebar's « Revenus » from `?periode=annee`).
  const show = useCallback(
    (p: ProProfile, search: string) => {
      const today = salonToday(new Date(), p.provider.timezone ?? SALON_TZ);
      const addr = readRevenueAddress(search, today);
      const q = queryOf(addr);
      setTab(addr.tab);
      setSort(addr.sort);
      setCurrency(null);
      setListForm(false);
      setQuery(q);
      void load(p.provider.id, q);
    },
    [load, queryOf],
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
      const search = window.location.search;
      // A detail belongs to its salon: after a switch (the dashboard
      // remounts this page) it goes back to « Revenus », same period (§22).
      const addr = readRevenueAddress(search, salonToday(new Date(), p.provider.timezone ?? SALON_TZ));
      if (axis && addr.salon && addr.salon !== p.provider.id) {
        router.replace(revenueOverviewHref(queryOf(addr)));
        return;
      }
      // In the router's own encoding (`useSearchParams().toString()`), or an
      // address written another way (`%20` for `+`) reads as a new one and
      // asks the figures twice.
      seenUrl.current = new URLSearchParams(search).toString();
      echoes.current = [];
      salonInAddress.current = addr.salon != null;
      setProfile(p);
      show(p, search);
    })();
    return () => {
      active = false;
    };
    // The address is read once here; later changes come through `urlQuery`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reloadKey]);

  // Every change of what is shown rewrites the address — REPLACED, never
  // pushed: Back leaves the page, as the agenda's (web-pro-agenda-url.md).
  // Opening a detail or the ledger is a link, so Back returns here as it was.
  useEffect(() => {
    if (!profile || !query) return;
    const extras = axis
      ? {
          artistId: axis === 'artist' ? null : query.artistId,
          serviceId: axis === 'service' ? null : query.serviceId,
          channel: axis === 'channel' ? null : query.channel,
          salon: salonInAddress.current ? profile.provider.id : null,
        }
      : {};
    const search = revenueSearch({ ...periodAddress(query), tab, sort, ...extras });
    if (search !== window.location.search) {
      echoes.current.push(search.replace(/^\?/, ''));
      window.history.replaceState(null, '', `${window.location.pathname}${search}`);
    }
  }, [profile, query, tab, sort, axis]);

  // A link to THIS page changes the address without remounting it.
  useEffect(() => {
    if (!profile || seenUrl.current === null) return;
    if (urlQuery === seenUrl.current) return;
    seenUrl.current = urlQuery;
    const i = echoes.current.indexOf(urlQuery);
    if (i >= 0) {
      echoes.current.splice(0, i + 1);
      return;
    }
    show(profile, urlQuery ? `?${urlQuery}` : '');
  }, [urlQuery, profile, show]);

  const change = useCallback(
    (q: RevenueQuery) => {
      if (!providerId) return;
      setQuery(q);
      void load(providerId, q);
    },
    [providerId, load],
  );

  // ← / → step the period (§5.1) — guarded as the journal's shortcuts: no
  // chord, one step per press, never while typing, choosing in a list,
  // moving through the chart, or with a dialog open.
  const a = view.analytics;
  useEffect(() => {
    if (!a || !query) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.repeat || e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      const t = e.target as HTMLElement | null;
      if (
        t &&
        (t.tagName === 'INPUT' ||
          t.tagName === 'TEXTAREA' ||
          t.tagName === 'SELECT' ||
          t.isContentEditable ||
          t.closest('[role="slider"]'))
      ) {
        return;
      }
      if (document.querySelector('[role="dialog"]')) return;
      const q = e.key === 'ArrowLeft' ? previousRevenuePeriod(a, query) : nextRevenuePeriod(a, query);
      if (!q) return;
      e.preventDefault();
      change(q);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [a, query, change]);

  // ── Names ────────────────────────────────────────────────────────────────

  /// A row's name for a heading, before and after the answer: the server's
  /// label when it labels this axis (kept names of removed rows included);
  /// else the live team and catalogue; else the generic one.
  function nameOf(ax: RevenueAxis, key: string | null, answer: RevenueAnalytics | null): string | null {
    if (answer && query && labelledAxis(query) === ax) {
      return revenueFilterLabel(ax, answer.filters);
    }
    if (ax === 'channel') {
      const c = key as RevenueQuery['channel'];
      return c ? revenueChannelLabel(c) : null;
    }
    if (ax === 'artist') {
      if (key == null || key === NO_ARTIST) return NO_ARTIST_LABEL;
      const live = profile?.provider.artists?.find((x) => x.id === key)?.name;
      return live ?? (answer ? FORMER_ARTIST_LABEL : null);
    }
    const live = profile?.provider.services?.find((x) => x.id === key)?.name;
    return live ?? (answer ? DELETED_SERVICE_LABEL : null);
  }

  // ── The page ─────────────────────────────────────────────────────────────

  const heading = axis ? (nameOf(axis, filterKey, a) ?? revenueAxisKind(axis)) : 'Revenus';
  /// A detail inside a detail: the other filter is its parent.
  const parentAxis =
    axis && query
      ? (REVENUE_AXES.find((x) => x !== axis && filterKeyOf(query, x) != null) ?? null)
      : null;
  const parentName = parentAxis && query ? nameOf(parentAxis, filterKeyOf(query, parentAxis), a) : null;

  const header = (
    <header>
      {axis && query ? (
        <Link
          href={
            parentAxis
              ? revenueDetailHref(
                  parentAxis,
                  filterKeyOf(query, parentAxis),
                  { ...query, [axis === 'artist' ? 'artistId' : axis === 'service' ? 'serviceId' : 'channel']: null },
                  providerId ?? '',
                )
              : revenueOverviewHref(query)
          }
          className="-ml-s inline-flex min-h-12 items-center rounded-control px-s text-bodyMedium text-textSecondary hover:bg-surfaceVariant"
        >
          <span aria-hidden="true">←&nbsp;</span>
          {parentAxis ? (parentName ?? revenueAxisKind(parentAxis)) : 'Revenus'}
        </Link>
      ) : null}
      {axis ? (
        <p className="text-bodySmall text-textSecondary">
          {revenueAxisKind(axis)}
          {parentAxis && parentName ? ` · ${parentName}` : ''}
        </p>
      ) : null}
      <h1 className="break-words text-headlineSmall font-semibold text-textPrimary">{heading}</h1>
      {axis ? null : (
        <p className="mt-xs text-bodyMedium text-textSecondary">
          Ce que vos rendez-vous terminés ont rapporté, par collaborateur, prestation et canal.
        </p>
      )}
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

  if (!profile || !query) {
    return (
      <div>
        {header}
        <RevenueSkeleton />
      </div>
    );
  }

  const today = lastToday ?? salonToday(new Date(), tz);

  return (
    <div>
      {header}
      {/* A refusal has no period to choose: nothing on the bar could
          succeed (§21.1 item 13). */}
      {view.refused ? null : (
        <div className="mt-l">
          <PeriodBar
            query={query}
            analytics={a}
            today={today}
            onPeriod={(p: Exclude<RevenuePeriod, 'custom'>) => change(switchRevenuePeriod(a, query, p))}
            onCustom={() => setRangeOpen(true)}
            onStep={change}
            onCompare={(mode) => {
              rememberCompare(mode);
              if (mode !== query.compare) change({ ...query, compare: mode });
            }}
          />
        </div>
      )}

      <div className="mt-l">
        {view.loading ? (
          <RevenueSkeleton />
        ) : view.refused ? (
          <EmptyState
            icon="lock"
            title="Réservé au propriétaire"
            description="Seul le propriétaire du salon voit les revenus."
          />
        ) : view.error || !a ? (
          <ErrorState
            message={loadFailureMessage(view.error || 'failed', 'Chargement impossible.')}
            onRetry={() => change(query)}
          />
        ) : (
          <Success
            a={a}
            query={query}
            axis={axis}
            profile={profile}
            tab={tab}
            sort={sort}
            currency={currency}
            preview={preview}
            listForm={listForm}
            // A detail inside a detail names both rows in its file.
            detailName={axis ? (parentName ? `${parentName} ${heading}` : heading) : null}
            onTab={setTab}
            onSort={setSort}
            onCurrency={setCurrency}
            onListForm={setListForm}
            onChange={change}
          />
        )}
      </div>

      {rangeOpen ? (
        <RangeDialog
          initialFrom={query.period === 'custom' && query.from ? query.from : (a?.from ?? today)}
          initialTo={query.period === 'custom' && query.to ? query.to : (a?.to ?? today)}
          latest={a ? revenueLatestDay(a) : addRevenueDays(today, REVENUE_MAX_DAYS)}
          onClose={() => setRangeOpen(false)}
          onApply={(from, to) => {
            setRangeOpen(false);
            change(withPeriod(query, 'custom', { from, to }));
          }}
        />
      ) : null}
    </div>
  );
}

/// The answer, drawn (§4.2–§4.10, §5.1).
function Success({
  a,
  query,
  axis,
  profile,
  tab,
  sort,
  currency,
  preview,
  listForm,
  detailName,
  onTab,
  onSort,
  onCurrency,
  onListForm,
  onChange,
}: {
  a: RevenueAnalytics;
  query: RevenueQuery;
  axis: RevenueAxis | null;
  profile: ProProfile;
  tab: RevenueAxis | null;
  sort: RevenueSort;
  currency: string | null;
  preview: Preview | null;
  listForm: boolean;
  detailName: string | null;
  onTab: (t: RevenueAxis | null) => void;
  onSort: (s: RevenueSort) => void;
  onCurrency: (c: string) => void;
  onListForm: (v: boolean) => void;
  onChange: (q: RevenueQuery) => void;
}) {
  const salon = profile.provider.id;
  // Nothing in either range: the figures read 0 in the salon's currency.
  const group: RevenueGroup = a.groups.find((g) => g.currency === currency) ??
    a.groups[0] ?? {
      currency: profile.provider.currency ?? 'XOF',
      current: ZERO,
      previous: null,
      series: [],
      byArtist: [],
      byService: [],
      byChannel: [],
    };
  const cur = group.current;
  const cmp = revenueComparisonLabel(a);
  const money = (v: number) => formatFcfa(v, group.currency);
  const toClose = a.groups.reduce((n, g) => n + g.current.toCloseCount, 0);

  // « Répartition »'s tabs: the axes no filter has emptied (§7.1).
  const axes = REVENUE_AXES.filter((x) => filterKeyOf(query, x) == null);
  const activeTab = tab && axes.includes(tab) ? tab : axes[0];
  const rows = activeTab ? sortRevenueRows(rowsOf(group, activeTab), activeTab, sort) : [];
  // A row opens its detail; inside a detail, one level more (§5.4); no
  // further.
  const filters = [query.artistId, query.serviceId, query.channel].filter((v) => v != null).length;
  const linkable = filters < 2;
  const anyEstimated = cur.estimated || rows.some((r) => r.estimated);

  const banner =
    toClose > 0 ? (
      <div className="mb-l">
        <div className="rounded-xl border border-info/40 bg-info/10 p-m">
          <p className="text-titleSmall font-semibold text-textPrimary">{revenueToCloseTitle(toClose)}</p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Confirmés mais pas encore marqués « Terminé » : ils ne comptent pas dans le réalisé.
          </p>
        </div>
        {/* Under the banner, not in it — the app's StatusBanner has no
            action slot (SYSTEM §11.1). */}
        <ButtonLink variant="text" href={revenueLedgerHref(query, 'toClose', salon, a.asOf, axis)} className="-ml-m mt-xs">
          Voir
        </ButtonLink>
      </div>
    ) : null;

  const upcoming: KpiTileData = (() => {
    const value = money(cur.upcomingAmount);
    const caption = [
      revenueUpcomingLine(cur.upcomingCount),
      ...(cur.pendingCount > 0 ? [revenuePendingLine(cur.pendingCount)] : []),
    ];
    return {
      key: 'upcoming',
      title: 'Prévu',
      value,
      caption,
      wide: true,
      spoken: `Prévu : ${value}, ${caption.join(', ')}`,
    };
  })();

  const currencySwitch =
    a.groups.length > 1 ? (
      <div role="group" aria-label="Devise" className="mb-l flex flex-wrap gap-s">
        {a.groups.map((g) => (
          <ChipButton
            key={g.currency}
            selected={g.currency === group.currency}
            aria-pressed={g.currency === group.currency}
            onClick={() => onCurrency(g.currency)}
          >
            {revenueCurrencyName(g.currency)}
          </ChipButton>
        ))}
      </div>
    ) : null;

  // A salon with nothing completed, ever (§4.11; §21.1 item 8: the banner
  // and « Prévu » still show above it).
  if (!a.everCompleted && !axis) {
    return (
      <div>
        {currencySwitch}
        {banner}
        {revenueHasFuture(a) && (cur.upcomingCount > 0 || cur.pendingCount > 0) ? (
          <div className="mb-l">
            <KpiGrid tiles={[upcoming]} />
          </div>
        ) : null}
        <EmptyState
          icon="insights"
          title="Pas encore de revenus"
          description="Vos revenus s’afficheront ici dès votre premier rendez-vous marqué « Terminé »."
          action={
            <ButtonLink href="/pro/rendez-vous" variant="secondary">
              Voir les rendez-vous
            </ButtonLink>
          }
        />
        <Footnotes price />
      </div>
    );
  }

  const prev = group.previous;
  const done = money(cur.completedAmount);
  const sentence = (title: string, value: string, d: RevenueDelta | null) =>
    d ? `${title} : ${value}, ${d.spoken}` : `${title} : ${value}`;
  const doneDelta = revenueDelta(cur.completedAmount, prev?.completedAmount, cmp);
  const countDelta = revenueDelta(cur.completedCount, prev?.completedCount, cmp);
  const avg = cur.averageTicket;
  const avgText = avg == null ? '—' : money(avg);
  const avgDelta = avg == null ? null : revenueDelta(avg, prev == null ? null : (prev.averageTicket ?? 0), cmp);
  const rate = cur.noShowRate;
  const rateText = rate == null ? '—' : formatPercent(rate, 1);
  const rateDelta = revenueRateDelta(rate, prev?.noShowRate, cmp);
  const absences = cur.noShowCount > 0 ? `${revenueAbsences(cur.noShowCount)} · ${money(cur.noShowAmount)}` : null;

  const tiles: KpiTileData[] = [
    {
      key: 'done',
      title: 'Réalisé',
      value: done,
      delta: doneDelta,
      caption: cur.estimated ? ['estimé'] : null,
      spoken: sentence('Réalisé', cur.estimated ? `${done}, estimé` : done, doneDelta),
    },
    {
      key: 'count',
      title: 'Rendez-vous terminés',
      value: String(cur.completedCount),
      delta: countDelta,
      spoken: sentence('Rendez-vous terminés', String(cur.completedCount), countDelta),
    },
    {
      key: 'avg',
      title: 'Panier moyen',
      value: avgText,
      delta: avgDelta,
      spoken: avg == null ? 'Panier moyen : aucun rendez-vous terminé' : sentence('Panier moyen', avgText, avgDelta),
    },
    {
      key: 'rate',
      title: 'Taux d’absence',
      value: rateText,
      delta: rateDelta,
      caption: absences ? [absences] : null,
      spoken:
        rate == null
          ? 'Taux d’absence : aucun rendez-vous terminé ni manqué'
          : `${sentence('Taux d’absence', rateText, rateDelta)}${absences ? `, ${absences}` : ''}`,
    },
    ...(revenueHasFuture(a) ? [upcoming] : []),
  ];

  const empty = cur.completedCount === 0;
  const previous = previousRevenuePeriod(a, query);

  function exportCsv() {
    if (!activeTab) return;
    const csv = revenueCsv(rows, activeTab, group);
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = revenueCsvFilename(a, activeTab, detailName);
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div>
      {currencySwitch}
      {banner}
      <KpiGrid tiles={tiles} />

      {group.series.length >= 2 && cur.completedCount > 0 ? (
        <Section
          title="Évolution"
          action={
            <Button variant="text" onClick={() => onListForm(!listForm)}>
              {listForm ? 'Voir le graphique' : 'Voir les données'}
            </Button>
          }
        >
          <Card>
            {listForm ? (
              <BarSeriesTable
                rows={group.series.map((p) => ({
                  key: p.start,
                  date: bucketName(a, p.start, p.end),
                  amount: money(p.completedAmount),
                  count: String(p.completedCount),
                }))}
              />
            ) : (
              <BarSeries
                key={`${a.from}:${a.to}:${group.currency}`}
                summary={`Réalisé sur la période : ${done} · ${revenueAppointments(cur.completedCount)}`}
                points={group.series.map((p) => ({
                  value: p.completedAmount,
                  axisLabel: a.bucket === 'month' ? formatMonthShort(p.start) : formatDayMonthShort(p.start),
                  sentence: `${bucketName(a, p.start, p.end)} · ${money(p.completedAmount)} · ${revenueAppointments(p.completedCount)}`,
                }))}
              />
            )}
          </Card>
        </Section>
      ) : null}

      {activeTab ? (
        <Section title="Répartition">
          <Tabs
            label="Répartition"
            items={axes.map((x) => ({ key: x, label: revenueAxisTitle(x) }))}
            value={activeTab}
            // The first tab is the default: never written in the address.
            onChange={(t) => onTab(t === axes[0] ? null : t)}
          />
          {empty ? (
            <div className="mt-m">
              {revenueIsFuture(a) ? (
                <EmptyState
                  icon="event"
                  title="Rien de terminé pour l’instant"
                  description="Cette période n’a pas commencé."
                />
              ) : (
                <EmptyState
                  icon="insights"
                  title="Aucun rendez-vous terminé sur cette période"
                  action={
                    previous ? (
                      <Button variant="secondary" onClick={() => onChange(previous)}>
                        Période précédente
                      </Button>
                    ) : undefined
                  }
                />
              )}
            </div>
          ) : (
            <>
              <div className="mt-m flex flex-wrap items-end justify-between gap-m">
                <label className="block text-labelMedium text-textSecondary">
                  Trier par
                  <select
                    value={sort}
                    onChange={(e) => onSort(e.target.value as RevenueSort)}
                    className="mt-xs block min-h-12 rounded-control border border-primary bg-surface px-m text-bodyMedium text-textPrimary"
                  >
                    {(['amount', 'count', 'name'] as const).map((s) => (
                      <option key={s} value={s}>
                        {revenueSortName(s)}
                      </option>
                    ))}
                  </select>
                </label>
                <Button variant="secondary" onClick={exportCsv}>
                  Exporter (CSV)
                </Button>
              </div>
              <div className="mt-m">
                <BreakdownTable
                  axis={activeTab}
                  rows={rows}
                  money={money}
                  comparison={cmp}
                  hrefOf={(r) =>
                    linkable && rowHasDetail(activeTab, r.key)
                      ? revenueDetailHref(activeTab, r.key, query, salon)
                      : undefined
                  }
                />
              </div>
            </>
          )}
        </Section>
      ) : null}

      {cur.completedCount > 0 ? (
        <Section
          title="Rendez-vous terminés"
          action={
            <ButtonLink variant="text" href={revenueLedgerHref(query, 'completed', salon, a.asOf, axis)}>
              {`Voir tout (${cur.completedCount})`}
            </ButtonLink>
          }
        >
          <RevenueLedgerTable
            rows={preview?.items ?? []}
            salon={salon}
            timezone={a.timezone}
            status="completed"
            isLoading={preview == null || preview.loading}
            error={preview?.error ? (loadFailureMessage(preview.error, 'Chargement impossible.') ?? null) : null}
            onRetry={() => onChange(query)}
          />
        </Section>
      ) : null}

      <Footnotes
        price
        services={activeTab === 'service' && rows.length > 0}
        estimated={anyEstimated}
      />
    </div>
  );
}

/// A row opens a detail only when the server can be asked about it: an id it
/// accepts (§7.1), « none » for the unassigned, a known channel.
function rowHasDetail(axis: RevenueAxis, key: string | null): boolean {
  switch (axis) {
    case 'artist':
      return key == null || isRevenueId(key);
    case 'service':
      return isRevenueId(key);
    case 'channel':
      return channelFromApi(key) != null;
  }
}

/// A bucket's name: « mar. 4 nov. », « 24 – 30 nov. 2026 », « novembre 2026 ».
function bucketName(a: RevenueAnalytics, start: string, end: string): string {
  switch (a.bucket) {
    case 'day':
      return formatWeekdayDayMonthShort(start);
    case 'week':
      return formatDayRange(start, end);
    case 'month':
      return formatMonthYear(start);
  }
}

/// « Répartition »'s table (§5.1): Nom · Rendez-vous · Montant · Part ·
/// Panier moyen · Évolution. Each row a link to its detail (the
/// DataTable's navigation row), when there is one.
function BreakdownTable({
  axis,
  rows,
  money,
  comparison,
  hrefOf,
}: {
  axis: RevenueAxis;
  rows: RevenueRow[];
  money: (v: number) => string;
  comparison: string | null;
  hrefOf: (r: RevenueRow) => string | undefined;
}) {
  return (
    <DataTable
      columns={[
        { label: 'Nom', flex: 4 },
        { label: 'Rendez-vous', flex: 2, align: 'right' },
        { label: 'Montant', flex: 3, align: 'right' },
        { label: 'Part', flex: 2, align: 'right' },
        { label: 'Panier moyen', flex: 3, align: 'right' },
        { label: 'Évolution', flex: 2, align: 'right' },
      ]}
      emptyTitle="Aucun rendez-vous terminé sur cette période"
      rows={rows.map((r, i) => {
        const label = revenueLabelOf(axis, r);
        const delta = revenueDelta(r.current.completedAmount, r.previous?.completedAmount, comparison);
        const href = hrefOf(r);
        return {
          key: `${r.key ?? 'none'}:${i}`,
          href,
          rowLabel: href ? `Ouvrir le détail : ${label}` : undefined,
          cells: [
            <div key="n" className="w-full min-w-0">
              <span className="break-words text-textPrimary">{label}</span>
              <ShareBar share={r.share} className="mt-xs" />
            </div>,
            <span key="c">{r.current.completedCount}</span>,
            <span key="a" className="whitespace-nowrap font-semibold">
              {money(r.current.completedAmount)}
              {r.estimated ? <span className="font-normal text-textSecondary"> · estimé</span> : null}
            </span>,
            <span key="s" className="whitespace-nowrap">
              {formatPercent(r.share)}
            </span>,
            <span key="t" className="whitespace-nowrap text-textSecondary">
              {r.current.averageTicket == null ? '—' : money(r.current.averageTicket)}
            </span>,
            delta ? (
              // The badge for the eye, the sentence for the ear — once each
              // (the badge's « stable » then « stable par rapport à … » read
              // twice, heard on the real server's answer).
              <span key="d">
                <span aria-hidden="true">
                  <DeltaBadge delta={delta} />
                </span>
                <span className="sr-only">{delta.spoken}</span>
              </span>
            ) : (
              <span key="d" className="text-textTertiary">
                —
              </span>
            ),
          ],
        };
      })}
    />
  );
}

function Section({
  title,
  action,
  children,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="mt-xl">
      <div className="flex flex-wrap items-center justify-between gap-s">
        <h2 className="text-titleLarge font-semibold text-textPrimary">{title}</h2>
        {action}
      </div>
      <div className="mt-s">{children}</div>
    </section>
  );
}

function Footnotes({
  price = false,
  services = false,
  estimated = false,
}: {
  price?: boolean;
  services?: boolean;
  estimated?: boolean;
}) {
  return (
    <div className="mt-xl space-y-s text-bodySmall text-textTertiary">
      {price ? <p>{REVENUE_PRICE_FOOTNOTE}</p> : null}
      {services ? <p>{REVENUE_SERVICES_FOOTNOTE}</p> : null}
      {estimated ? <p>{REVENUE_ESTIMATED_FOOTNOTE}</p> : null}
    </div>
  );
}

/// The first load's shape (§4.11): the figure tiles, a chart block and three
/// rows — nothing reflows when the answer lands. One sentence for screen
/// readers.
export function RevenueSkeleton() {
  return (
    <div className="mt-l">
      <p role="status" className="sr-only">
        Chargement des revenus…
      </p>
      <div className="grid grid-cols-1 gap-m sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24" />
        ))}
      </div>
      <Skeleton className="mt-xl h-40" />
      <div className="mt-xl space-y-s">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-12" />
        ))}
      </div>
    </div>
  );
}
