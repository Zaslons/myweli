'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { SkeletonRows } from '../Skeleton';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  type DashboardStats,
  type ProProfile,
  getDashboard,
  getMyProvider,
  listProAppointments,
} from '../../lib/api/pro';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { formatFcfa } from '../../lib/format';
import {
  SALON_SWITCH_REFUSED,
  type TeamInvitation,
  hasCap,
  joinedSalonMessage,
} from '../../lib/pro/team';
import { REQUEST_SENT, goLiveState } from '../../lib/pro/salon-validation';
import { SALON_ID_PATTERN, isValidationPush } from '../../lib/pro/notifications';
import {
  type ProAppointment,
  todayCounts,
  todaysAppointments,
} from '../../lib/pro/today';
import { BrowserPushBand } from './BrowserPushBand';
import { GoLiveCard, type PublishOutcome } from './GoLiveCard';
import { ProAppointmentRow } from './ProAppointmentRow';
import { ProInvitationsCard } from './ProInvitationsCard';
import { type SwitchOutcome, useOptionalProMembership } from './ProMembershipContext';
import { staffPlanningTitle } from '../../lib/salon-name';

/// A notice's ask — switch to this salon, once (docs/design/web-salon-validation.md
/// §4.5). Module-level because it must outlive the one remount the switch
/// itself causes (`tried`: the remount checks it landed, and says so if not —
/// a server that does not take the switch cannot send the page round in
/// circles). The page TAKES it on its first read, whatever that read says, so
/// no later remount (a switch from « Mes salons », a retry) can find a stale one.
let ask: { salon: string; tried: boolean } | null = null;

/// « Aujourd’hui ». [salon] — `?salon=` from a notice about one of the
/// account's salons (B0.18: the decision's push, feed row and e-mail land on
/// `/pro?salon={id}`): the page switches to it once.
export function AujourdhuiClient({ salon }: { salon?: string } = {}) {
  const router = useRouter();
  const membershipCtx = useOptionalProMembership();
  const switchSalon = membershipCtx?.switchSalon;
  const refreshSalons = membershipCtx?.refreshSalons;
  const [profile, setProfile] = useState<ProProfile | null>(null);
  /// The line after a publish: a 200 (live) or a 202 (a request).
  const [notice, setNotice] = useState<'live' | 'requested' | null>(null);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [error, setError] = useState<LoadFailure | false>(false);
  const [switchError, setSwitchError] = useState<LoadFailure | false>(false);

  // `?salon=` becomes an ask and leaves the address AT ONCE, before any read
  // (Next keeps its router in step with `history.replaceState`). Only an ask
  // the live address still carries counts: Next re-renders this page from its
  // cached payload — `salon` and all — when « Mes salons » re-keys it, and that
  // stale prop must never pull the salon back.
  const askRead = useRef(false);
  useEffect(() => {
    const s = validSalonParam(salon);
    if (!s || new URLSearchParams(window.location.search).get('salon') !== s) return;
    ask = { salon: s, tried: false };
    window.history.replaceState(null, '', '/pro');
    // Mounted already (a link to `/pro?salon=…` from `/pro`): load for it.
    if (askRead.current) setReloadKey((k) => k + 1);
  }, [salon]);

  useEffect(() => {
    let active = true;
    (async () => {
      askRead.current = true;
      const me = await getMyProvider();
      if (!active) return;
      // Taken on this first read, whatever it says.
      const a = ask;
      ask = null;
      if (me.status === 401) {
        // The salon rides through the login (§4.5): a two-salon owner who
        // opens the decision's e-mail signed out still lands on it.
        router.replace(a ? `/pro/connexion?salon=${a.salon}` : '/pro/connexion');
        return;
      }
      if (a && switchSalon && me.status === 200 && me.profile && me.profile.provider.id !== a.salon) {
        // Already switched once and still elsewhere: the server did not take
        // it — say so rather than switch again.
        let outcome: SwitchOutcome = 'failed';
        if (!a.tried) {
          ask = { salon: a.salon, tried: true };
          outcome = await switchSalon(a.salon);
          // Switched: the shell re-keys; the page reads again under it.
          if (outcome === 'switched') return;
          ask = null;
          if (!active) return;
        }
        // Refused, or no answer: « Accueil » of the current salon, saying why
        // — the app goes to « Accueil » too.
        setSwitchError(outcome as LoadFailure);
      }
      const appts = await listProAppointments();
      if (!active) return;
      if (me.status !== 200 || appts.status !== 200) {
        setError(loadFailure(me.status, appts.status));
        setLoading(false);
        return;
      }
      setProfile(me.profile ?? null);
      setItems(appts.items);
      setLoading(false);
      // « Mes salons » too: its lines carry each salon's validation state
      // (§4.6 — a refresh point is this page loading).
      void refreshSalons?.();
      // Secondary fetches are capability-gated (team access R5b): the server
      // would 403/field-gate them anyway — skipping is the honest UI.
      if (me.profile) {
        const m = me.profile.membership;
        if (hasCap(m, 'journal.view.all')) {
          // Revenue stats are best-effort — don't block the bookings list.
          const dash = await getDashboard(me.profile.provider.id);
          if (active && dash.status === 200) setStats(dash.stats ?? null);
        }
      }
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey, switchSalon, refreshSalons]);

  // A quiet re-read of the salon's state (§4.6): after a publish, and when a
  // decision's push arrives. A failed read keeps what is shown — it never
  // turns the day into an error.
  const shownSalon = useRef<string | null>(null);
  shownSalon.current = profile?.provider.id ?? null;
  const refreshState = useCallback(async () => {
    const me = await getMyProvider();
    void refreshSalons?.();
    if (me.status !== 200 || !me.profile) return;
    // Another salon now (the selection changed in another tab): reload the
    // whole day for it rather than graft its state onto this one.
    if (shownSalon.current && me.profile.provider.id !== shownSalon.current) {
      setReloadKey((k) => k + 1);
      return;
    }
    const next = me.profile;
    setProfile(next);
    // « Demande envoyée » is about a request still waiting: gone once MyWeli
    // decided (the region stays, emptied — nothing is said).
    if (goLiveState(next.provider.status, next.validation) !== 'pending') {
      setNotice((n) => (n === 'requested' ? null : n));
    }
  }, [refreshSalons]);

  // The service worker tells open tabs of each push, with its event: a
  // decision on a salon (`salon.validation.*`) re-reads the state now.
  useEffect(() => {
    const sw = typeof navigator === 'undefined' ? undefined : navigator.serviceWorker;
    if (!sw) return;
    const onMessage = (e: MessageEvent) => {
      if (isValidationPush(e.data)) void refreshState();
    };
    sw.addEventListener('message', onMessage);
    return () => sw.removeEventListener('message', onMessage);
  }, [refreshState]);

  function onPublished(outcome: PublishOutcome) {
    if (!profile) return;
    if (outcome.kind === 'live') {
      setProfile({ ...profile, provider: { ...profile.provider, status: 'active' } });
      setNotice('live');
    } else {
      // The 202's validation, when it came back readable; the re-read below
      // settles it either way.
      if (outcome.validation !== undefined) {
        setProfile({ ...profile, validation: outcome.validation });
      }
      // « Demande envoyée » only for a request now waiting (or a body that
      // could not be read — the request IS recorded) — not for a refusal
      // MyWeli decided at that very moment, nor for a request that vanished
      // (`null`: the account was erased).
      const v = outcome.validation;
      setNotice(v === undefined || (v !== null && v.state !== 'refused') ? 'requested' : null);
    }
    void refreshState();
  }

  // An already-active member accepted another salon's invitation: the new
  // salon joins « Mes salons » (the switcher), and the app's success line
  // says so. The provider owns the toast (a remount must not swallow it).
  function onInvitationAccepted(inv: TeamInvitation) {
    void membershipCtx?.refreshSalons();
    membershipCtx?.notify(joinedSalonMessage(inv.salonName), 'success');
  }

  // The session died under an invitation card (signed out in another tab, the
  // refresh token expired): the login, as this page's reads do — the card
  // would otherwise say the accept failed, and « Réessayer » could only fail
  // again.
  const toLogin = () => router.replace('/pro/connexion');

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (error) {
    // The retry re-probes the membership too: after a join whose /me
    // failed, the sidebar waits in its skeleton (never a nav drawn from an
    // absent membership) — and this page, where the join lands, is the one
    // place a retry is offered (docs/design/pro-rejoin-gate.md §10).
    return (
      <ErrorState
        title="Aujourd’hui"
        message={loadFailureMessage(error)}
        onRetry={() => {
          void membershipCtx?.refresh();
          setError(false);
          setLoading(true);
          setReloadKey((k) => k + 1);
        }}
      />
    );
  }

  // The ACTIVE salon's market (multi-pays MP3) — day boundary + money label.
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;
  const today = todaysAppointments(items, new Date(), tz);
  const counts = todayCounts(items, new Date(), tz);
  const serviceName = (id: string) =>
    profile?.provider.services?.find((s) => s.id === id)?.name;

  // Team access R5b: the role shape. A Collaborateur gets « votre planning »
  // (own rows, server-filtered) — no stats, no owner cards.
  const m = profile?.membership;
  const staffView = !hasCap(m, 'journal.view.all');
  const salonName = profile?.provider.name ?? '';

  if (staffView) {
    return (
      <div>
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          {staffPlanningTitle(salonName)}
        </h1>
        <SwitchAlert failure={switchError} />

        {/* A Collaborateur is told of their own artist's bookings: the same
            band (docs/design/web-pro-browser-push.md §2). */}
        <BrowserPushBand />

        {/* Pending invitations for THIS account (if any). A dead session
            on « Rejoindre »/« Refuser » goes to the login, as this page's
            reads do (docs/design/web-pro-truthful-failure.md §2.4). */}
        <ProInvitationsCard
          onAccepted={onInvitationAccepted}
          onUnauthenticated={toLogin}
        />

        <h2 className="mt-l text-titleLarge font-semibold text-textPrimary">
          Rendez-vous du jour
        </h2>
        <div className="mt-m space-y-s">
          {today.length === 0 ? (
            <EmptyState icon="event" title="Aucun rendez-vous aujourd’hui" description="Vos rendez-vous du jour apparaîtront ici." />
          ) : (
            today.map((a) => (
              <ProAppointmentRow
                key={a.id}
                appt={a}
                serviceName={serviceName}
                href={`/pro/rendez-vous/${a.id}`}
                tz={tz}
                currency={currency}
              />
            ))
          )}
        </div>
      </div>
    );
  }

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Aujourd’hui</h1>
      <p className="mt-xs text-bodyMedium text-textTertiary">{profile?.provider.name}</p>
      <SwitchAlert failure={switchError} />

      {/* The app's push prompt on its first dashboard visit, as a band —
          once per browser (docs/design/web-pro-browser-push.md §2). */}
      <BrowserPushBand />

      {/* §9's two-pane desktop (B7): ONE DOM tree. Below xl the two children
          stack in the vertical flow (interrupts + stats, then the day's
          list); at xl the agenda takes the main pane and this rail moves
          right — grid placement, no duplicated content. */}
      <div className="xl:grid xl:grid-cols-desk xl:items-start xl:gap-xl">
        <div className="xl:col-start-2 xl:row-start-1">
          {/* Team access R5a: pending invitations for THIS account (if any). */}
          <ProInvitationsCard
            onAccepted={onInvitationAccepted}
            onUnauthenticated={toLogin}
          />

          {/* Draft salons: the go-live checklist (pro-salon-lifecycle.md B2) —
              publishing is the owner's act (salon.publish). B0.18: the card
              branches inside on the validation; with the new server a
              SUSPENDED salon gets its banner too (owner, 2026-11-13 —
              web-salon-validation.md §9 Q2). */}
          {profile && showGoLiveCard(profile) && hasCap(m, 'salon.publish') ? (
            <GoLiveCard
              profile={profile}
              onPublished={onPublished}
              onStale={() => void refreshState()}
            />
          ) : null}
          <p
            role="status"
            className={
              notice
                ? 'mt-m rounded-xl border border-success/40 bg-success/10 p-m text-bodyMedium text-success'
                : 'sr-only'
            }
          >
            {notice === 'live'
              ? '🎉 Votre salon est en ligne ! Il apparaît maintenant dans les recherches.'
              : notice === 'requested'
                ? REQUEST_SENT
                : ''}
          </p>

          {/* Parity with the app's « Demandes » (web-b7-desktop.md): pending
              across ALL dates from DashboardStats — a salon with Monday
              requests must not read « 0 » on Friday. Today-only fallback
              while the best-effort stats call is out (or failed). */}
          {/* B11: `grid-cols-3` gave each tile ~46px of the 320 viewport (and 64
              of 375) for French labels like « Demandes en attente » — measured
              spilling at BOTH widths, on a route this gate had never opened.
              Stacked below `sm`; three across once there is room. */}
          <div className="mt-l grid grid-cols-1 gap-m sm:grid-cols-3 xl:grid-cols-1">
            <Stat
              label="Demandes en attente"
              value={stats?.pendingRequests ?? counts.pending}
            />
            <Stat label="Confirmés" value={counts.confirmed} />
            <Stat label="Total du jour" value={counts.total} />
          </div>

          {/* The money row needs finances.view — the server drops the revenue
              fields for other roles, so rendering it would show a lying 0 F.
              « prévus »: these count confirmed + completed bookings, while
              « Revenus » (/pro/revenus) counts completed only — the app's
              words (provider-dashboard-stats.md §12). */}
          {hasCap(m, 'finances.view') ? (
            <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-3 xl:grid-cols-1">
              <Stat
                label="Revenus prévus aujourd’hui"
                value={stats ? formatFcfa(stats.todayRevenue ?? 0, currency) : '—'}
              />
              <Stat
                label="Revenus prévus cette semaine"
                value={stats ? formatFcfa(stats.weekRevenue ?? 0, currency) : '—'}
              />
              <Stat
                label="Revenus prévus ce mois"
                value={stats ? formatFcfa(stats.monthRevenue ?? 0, currency) : '—'}
              />
            </div>
          ) : null}

          {hasCap(m, 'profile.manage') ? (
            <Link
              href="/pro/profil"
              className="mt-l flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyLarge text-textPrimary hover:bg-surfaceVariant"
            >
              <span>Configurer mon profil</span>
              <span className="text-textTertiary">›</span>
            </Link>
          ) : null}

          {profile?.provider.status === 'active' && profile.provider.slug ? (
            <Link
              href={`/${profile.provider.slug}`}
              className="mt-s flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyLarge text-textPrimary hover:bg-surfaceVariant"
            >
              <span>Voir ma page publique</span>
              <span className="text-textTertiary">›</span>
            </Link>
          ) : null}
        </div>

        <div className="xl:col-start-1 xl:row-start-1">
          <h2 className="mt-l text-titleLarge font-semibold text-textPrimary">
            Rendez-vous du jour
          </h2>
          <div className="mt-m space-y-s">
            {today.length === 0 ? (
              <EmptyState icon="event" title="Aucun rendez-vous aujourd’hui" description="Vos rendez-vous du jour apparaîtront ici." />
            ) : (
              today.map((a) => (
                <ProAppointmentRow
                  key={a.id}
                  appt={a}
                  serviceName={serviceName}
                  href={`/pro/rendez-vous/${a.id}`}
                  tz={tz}
                  currency={currency}
                />
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/// The card shows for a draft (every state of it), and — with the B0.18
/// server only — for a suspended salon. Never for a live one.
function showGoLiveCard(profile: ProProfile): boolean {
  if (profile.provider.status === 'draft') return true;
  return goLiveState(profile.provider.status, profile.validation) === 'suspended';
}

/// A `?salon=` the page could not follow — the booking detail's sentences.
function SwitchAlert({ failure }: { failure: LoadFailure | false }) {
  if (!failure) return null;
  return (
    <p role="alert" className="mt-m text-bodyMedium text-error">
      {loadFailureMessage(failure, SALON_SWITCH_REFUSED)}
    </p>
  );
}

/// Only a salon id goes anywhere (the id pattern the service worker checks);
/// anything else in the address is ignored.
function validSalonParam(salon: string | undefined): string | null {
  return salon && SALON_ID_PATTERN.test(salon) ? salon : null;
}

function Stat({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <Card className="text-center">
      <p className="text-titleLarge font-semibold text-textPrimary">{value}</p>
      <p className="text-bodySmall text-textTertiary">{label}</p>
    </Card>
  );
}
