'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { SkeletonRows } from '../Skeleton';
import { type ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { Toast } from '../Toast';
import { useToast } from '../../lib/useToast';
import { type ProProfile, getMyProvider, listProAppointments } from '../../lib/api/pro';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/pro/load-failure';
import {
  type ListTab,
  LIST_TABS,
  addDays,
  appointmentsOnDate,
  dateKey,
  filterList,
} from '../../lib/pro/agenda';
import { getJournalDay } from '../../lib/api/pro';
import type { JournalDay } from '../../lib/pro/journal';
import {
  type AgendaState,
  type AgendaView,
  agendaQuery,
  readAgenda,
} from '../../lib/pro/agenda-url';
import { hasCap } from '../../lib/pro/team';
import type { ProAppointment } from '../../lib/pro/today';
import { salonFormatter } from '../../lib/time';
import { JournalGrid } from './JournalGrid';
import { ManualBookingDialog } from './ManualBookingDialog';
import { MonthCalendar } from './MonthCalendar';
import { ProAppointmentRow } from './ProAppointmentRow';
import { Tabs } from '../Tabs';
import { WeekGrid } from './WeekGrid';
import { WeekStrip } from './WeekStrip';
import { useIsDesktop } from '../../lib/pro/use-is-desktop';
import { weekOf, weekStripLabel } from '../../lib/pro/week-strip';
import { weekArtists } from '../../lib/pro/week-view';

type View = AgendaView;

/// The view switcher's labels. Tabled rather than built from a ternary inside
/// the map, which is what the hand-rolled strip did (B9).
const VIEW_TABS: { key: View; label: string }[] = [
  { key: 'journal', label: 'Journée' },
  // Desktop only (docs/design/web-pro-week-view.md Q3): phones keep the week
  // strip + the Journée, as the app.
  { key: 'week', label: 'Semaine' },
  { key: 'calendar', label: 'Calendrier' },
  { key: 'list', label: 'Liste' },
];

// Midday anchors the key inside its salon day at any wave offset (±11 h).
const dayLabel = (key: string, tz?: string) =>
  salonFormatter({ day: 'numeric', month: 'long', year: 'numeric' }, tz).format(
    new Date(`${key}T12:00:00.000Z`),
  );

export function RendezVousClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [error, setError] = useState<LoadFailure | false>(false);
  const [view, setView] = useState<View>('journal');
  const [journalDay, setJournalDay] = useState<JournalDay | null>(null);
  const [journalError, setJournalError] = useState<LoadFailure | false>(false);
  const [journalDate, setJournalDate] = useState<string>(dateKey(new Date()));
  const [showCancelled, setShowCancelled] = useState(false);
  const { toast, show } = useToast();
  const [focused, setFocused] = useState<Date>(new Date());
  const [selected, setSelected] = useState<string>(dateKey(new Date()));
  const [listTab, setListTab] = useState<ListTab>('today');
  const [creating, setCreating] = useState(false);
  const isDesktop = useIsDesktop();
  // The « Semaine »: its seven days (the Journée's reads), and the « Artiste »
  // filter — null = « Tous », '' = « Sans artiste ».
  const [weekDays, setWeekDays] = useState<JournalDay[] | null>(null);
  const [weekError, setWeekError] = useState<LoadFailure | false>(false);
  const [artistFilter, setArtistFilter] = useState<string | null>(null);

  // The address as Next's router knows it — it follows `history.replaceState`
  // (14.1+), so the page's own writes come back here too.
  const urlQuery = useSearchParams()?.toString() ?? '';
  /// The address value the screen already reflects; null until it was read.
  const settled = useRef<string | null>(null);
  /// What this page wrote and has not yet seen come back through the router
  /// (its sync is a transition: two quick ›› can echo late, and in order).
  const echoes = useRef<string[]>([]);

  /// Show what an address asks — on load, and when a link to this same page
  /// changes it (docs/design/web-pro-agenda-url.md).
  const showAgenda = useCallback((shown: AgendaState) => {
    setView(shown.view);
    setJournalDate(shown.journalDate);
    setSelected(shown.selected);
    // The Calendrier's month follows its chosen day (a midday anchor, the
    // grid's own convention).
    setFocused(new Date(`${shown.selected}T12:00:00.000Z`));
    setListTab(shown.listTab);
  }, []);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
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
      // « Aujourd'hui » is the ACTIVE salon's day (multi-pays MP3) — the
      // pre-profile defaults assumed Abidjan; realign before first paint.
      // And the address says what the salon was looking at — the view, its
      // day, the Liste's tab (docs/design/web-pro-agenda-url.md): coming back
      // from a booking or reloading lands there, not on today's Journée. Read
      // HERE, after /me, because « today » is the salon's; and here rather
      // than in a state initializer, because the server render has no address.
      const salonTz = me.profile?.provider.timezone ?? undefined;
      settled.current = window.location.search;
      echoes.current = [];
      showAgenda(readAgenda(window.location.search, dateKey(new Date(), salonTz)));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey, showAgenda]);

  // …and every change of what is shown rewrites it — REPLACED, never pushed:
  // Back must leave the page, not walk back through each day the ‹ › and ← →
  // visited. `history.replaceState` is the browser's own call (Next 14.2
  // follows it): no navigation, no server round trip. Not before /me — until
  // then nothing was read, and « today » is not known.
  useEffect(() => {
    if (!profile) return;
    const today = dateKey(new Date(), profile.provider.timezone ?? undefined);
    const query = agendaQuery({ view, journalDate, selected, listTab }, today);
    const { pathname, search } = window.location;
    if (query !== search) {
      echoes.current.push(query);
      window.history.replaceState(null, '', `${pathname}${query}`);
    }
  }, [profile, view, journalDate, selected, listTab]);

  // A link to THIS page — the menu's « Rendez-vous » from `?jour=…`, a link
  // to `?vue=liste…` — changes the address without remounting (Next keeps
  // the page), so nothing above runs again: the e2e caught the address going
  // bare while the grid kept the dated day. An address the page did not write
  // is one to show. Its own writes come back too, and are only acknowledged.
  useEffect(() => {
    if (!profile || settled.current === null) return;
    const query = urlQuery ? `?${urlQuery}` : '';
    if (query === settled.current) return;
    settled.current = query;
    const echo = echoes.current.indexOf(query);
    if (echo !== -1) {
      echoes.current.splice(0, echo + 1);
      return;
    }
    echoes.current = [];
    showAgenda(
      readAgenda(query, dateKey(new Date(), profile.provider.timezone ?? undefined)),
    );
  }, [urlQuery, profile, showAgenda]);

  // The booking hub's request-id dedupe: a held ←/→ fires several day loads
  // in flight at once, and without this the SLOWEST response wins — the grid
  // could show Tuesday under a header saying Thursday.
  const journalReq = useRef(0);
  const loadJournal = useCallback(async () => {
    if (!profile) return;
    const req = ++journalReq.current;
    setJournalError(false);
    const r = await getJournalDay(profile.provider.id, journalDate);
    if (req !== journalReq.current) return;
    if (r.status === 200 && r.day) {
      setJournalDay(r.day);
      return;
    }
    // The session is gone (the BFF's refresh failed): the login, as this
    // page's other reads — « Réessayer » could only fail again.
    if (r.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    // Any other failure — a 5xx, no network (status 0) — is the section's error
    // state, as the app (`_day = null` + « Réessayer »). It used to do
    // nothing: the skeleton for ever, or the PREVIOUS day's grid under the
    // new date (docs/design/web-pro-network-failure.md §4).
    setJournalDay(null);
    setJournalError(loadFailure(r.status));
  }, [profile, journalDate, router]);

  useEffect(() => {
    if (view === 'journal') loadJournal();
  }, [view, loadJournal]);

  // §9's journal shortcuts (B7): ← / → = jour précédent/suivant, T =
  // aujourd'hui. Guarded four ways — no modifier chords, never while typing
  // (input/textarea/select/contenteditable), never while ANY dialog is open
  // (the manual-booking + quick-create dialogs and the block panel), and
  // only on the Journée view. T is a single-character shortcut (WCAG 2.1.4);
  // the typing guard + view scope are the mitigation, recorded in §9.
  useEffect(() => {
    if (view !== 'journal' && view !== 'week') return;
    // The same keys, a week at a time in « Semaine ».
    const step = view === 'week' ? 7 : 1;
    const salonTz = profile?.provider.timezone ?? undefined;
    const onKey = (e: KeyboardEvent) => {
      // A held key auto-repeats — one deliberate press, one step.
      if (e.repeat) return;
      if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
      const t = e.target as HTMLElement | null;
      if (
        t &&
        (t.tagName === 'INPUT' ||
          t.tagName === 'TEXTAREA' ||
          t.tagName === 'SELECT' ||
          t.isContentEditable)
      )
        return;
      if (document.querySelector('[role="dialog"]')) return;
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        const delta = e.key === 'ArrowLeft' ? -step : step;
        setJournalDate((d) =>
          // Midday anchor: ±1 day stays inside the salon day at any offset.
          dateKey(addDays(new Date(`${d}T12:00:00.000Z`), delta), salonTz),
        );
      } else if (e.key === 't' || e.key === 'T') {
        setJournalDate(dateKey(new Date(), salonTz));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [view, profile]);


  // A « Semaine » address on a phone (or a window narrowed under it) opens
  // that day's Journée — the tab is a desktop one (web-pro-week-view.md Q3).
  useEffect(() => {
    if (view === 'week' && !isDesktop) setView('journal');
  }, [view, isDesktop]);

  // The week's seven days, read together — the Journée's own reads, so the
  // panel gets what it expects; the newest request wins (a held → must not
  // let a slower, older week land).
  const weekReq = useRef(0);
  const monday = weekOf(journalDate)[0];
  const loadWeek = useCallback(async () => {
    if (!profile) return;
    const req = ++weekReq.current;
    setWeekError(false);
    const results = await Promise.all(
      weekOf(monday).map((d) => getJournalDay(profile.provider.id, d)),
    );
    if (req !== weekReq.current) return;
    if (results.some((r) => r.status === 401)) {
      router.replace('/pro/connexion');
      return;
    }
    const failed = results.find((r) => r.status !== 200 || !r.day);
    if (failed) {
      setWeekDays(null);
      setWeekError(loadFailure(failed.status));
      return;
    }
    setWeekDays(results.map((r) => r.day as JournalDay));
  }, [profile, monday, router]);

  useEffect(() => {
    if (view === 'week') void loadWeek();
  }, [view, loadWeek]);

  if (loading) return <SkeletonRows count={5} className="mt-l" />;
  if (error) {
    return <ErrorState title="Rendez-vous" message={loadFailureMessage(error)} onRetry={() => { setError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  const serviceName = (id: string) =>
    profile?.provider.services?.find((s) => s.id === id)?.name;
  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;
  const dayList = appointmentsOnDate(items, selected, tz);
  const list = filterList(items, listTab, new Date(), tz);
  // What every link to a booking carries, so its « ← Rendez-vous » comes back
  // here (web-pro-agenda-url.md §2.2) — the same words the address has.
  const bookingQuery = agendaQuery(
    { view, journalDate, selected, listTab },
    dateKey(new Date(), tz),
  );

  // Team access R5b: own-scope roles (Collaborateur) get a read-only,
  // server-filtered planning — no creation, no drag.
  const canManageAll = hasCap(profile?.membership, 'journal.manage.all');

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-s">
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          {canManageAll
            ? 'Rendez-vous'
            : `${profile?.provider.name ?? ''} — votre planning`}
        </h1>
        {profile && canManageAll ? (
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="rounded-lg bg-primary px-m py-s text-labelLarge font-medium text-secondary hover:bg-primaryHover"
          >
            + Nouveau rendez-vous
          </button>
        ) : null}
      </div>

      <Tabs
        label="Vue de l’agenda"
        className="mt-l"
        value={view}
        onChange={setView}
        items={isDesktop ? VIEW_TABS : VIEW_TABS.filter((t) => t.key !== 'week')}
      />

      {view === 'journal' ? (
        <div className="mt-m">
          <div className="flex flex-wrap items-center justify-between gap-s">
            {/* B11: `flex-wrap` is the reflow fix. Four controls — ‹, a 16px
                `type="date"` field whose intrinsic width the UA owns, ›, and
                « Aujourd'hui » — measured 312px of the 272 available at 320,
                pushing the whole page sideways. The parent row already wraps;
                this one did not, so it spilled instead. Wrapping is the same
                answer B9 gave the tab strips, one level down. */}
            <div className="flex flex-wrap items-center gap-s">
              <button
                type="button"
                aria-label="Jour précédent"
                title="Raccourci : ←"
                className="rounded-lg border border-border px-s py-xs text-textSecondary"
                onClick={() =>
                  // Midday anchor: ±1 day stays inside the salon day at any
                  // wave offset.
                  setJournalDate(
                    dateKey(
                      addDays(new Date(`${journalDate}T12:00:00.000Z`), -1),
                      tz,
                    ),
                  )
                }
              >
                ‹
              </button>
              <input
                type="date"
                value={journalDate}
                onChange={(e) => setJournalDate(e.target.value)}
                aria-label="Date"
                className="min-h-12 rounded-lg border border-borderStrong bg-surface px-s py-xs text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
              />
              <button
                type="button"
                aria-label="Jour suivant"
                title="Raccourci : →"
                className="rounded-lg border border-border px-s py-xs text-textSecondary"
                onClick={() =>
                  setJournalDate(
                    dateKey(
                      addDays(new Date(`${journalDate}T12:00:00.000Z`), 1),
                      tz,
                    ),
                  )
                }
              >
                ›
              </button>
              <button
                type="button"
                title="Raccourci : T"
                className="text-bodyMedium text-textTertiary underline"
                onClick={() => setJournalDate(dateKey(new Date(), tz))}
              >
                Aujourd’hui
              </button>
            </div>
            <label className="flex items-center gap-xs text-bodyMedium text-textSecondary">
              <input
                type="checkbox"
                checked={showCancelled}
                onChange={(e) => setShowCancelled(e.target.checked)}
              />
              Voir les annulés
            </label>
          </div>
          {/* Outside the day's states: it stays while a day loads or fails,
              so another day is one click away. */}
          <WeekStrip
            shown={journalDate}
            items={items}
            loaded={journalDay}
            tz={tz}
            onSelect={setJournalDate}
          />
          {journalError ? (
            // A section error: the page's h1 stays above it.
            <ErrorState
              className="mt-l"
              message={loadFailureMessage(journalError)}
              onRetry={() => void loadJournal()}
            />
          ) : profile && journalDay ? (
            <div className="mt-m">
              <JournalGrid
                providerId={profile.provider.id}
                day={{
                  ...journalDay,
                  appointments: journalDay.appointments.filter(
                    (a) => showCancelled || a.status !== 'cancelled',
                  ),
                }}
                profile={profile}
                readOnly={!canManageAll}
                onChanged={loadJournal}
                onToast={show}
                bookingQuery={bookingQuery}
              />
            </div>
          ) : (
            <SkeletonRows count={6} className="mt-l" />
          )}
        </div>
      ) : view === 'week' ? (
        <WeekView
          days={weekDays}
          error={weekError}
          onRetry={() => void loadWeek()}
          monday={monday}
          tz={tz}
          showCancelled={showCancelled}
          setShowCancelled={setShowCancelled}
          artistFilter={artistFilter}
          setArtistFilter={setArtistFilter}
          onWeek={(delta) =>
            setJournalDate((d) =>
              dateKey(addDays(new Date(`${d}T12:00:00.000Z`), delta * 7), tz),
            )
          }
          onThisWeek={() => setJournalDate(dateKey(new Date(), tz))}
        >
          {profile && weekDays ? (
            <WeekGrid
              providerId={profile.provider.id}
              days={weekDays}
              profile={profile}
              readOnly={!canManageAll}
              artistFilter={artistFilter}
              showCancelled={showCancelled}
              onChanged={() => void loadWeek()}
              onToast={show}
              bookingQuery={bookingQuery}
            />
          ) : null}
        </WeekView>
      ) : view === 'calendar' ? (
        <div className="mt-m grid gap-l md:grid-cols-2">
          <MonthCalendar
            items={items}
            focused={focused}
            selected={selected}
            onFocus={setFocused}
            onSelect={setSelected}
            tz={tz}
          />
          <div>
            <p className="text-bodyMedium text-textTertiary">
              pour {dayLabel(selected, tz)}
            </p>
            <div className="mt-s space-y-s">
              {dayList.length === 0 ? (
                <EmptyState icon="event" title="Aucun rendez-vous ce jour-là" />
              ) : (
                dayList.map((a) => (
                  <ProAppointmentRow
                    key={a.id}
                    appt={a}
                    serviceName={serviceName}
                    href={`/pro/rendez-vous/${a.id}${bookingQuery}`}
                    tz={tz}
                    currency={currency}
                  />
                ))
              )}
            </div>
          </div>
        </div>
      ) : (
        <div className="mt-m">
          <Tabs
            label="Filtrer les rendez-vous"
            value={listTab}
            onChange={setListTab}
            items={LIST_TABS}
          />
          <div className="mt-m space-y-s">
            {list.length === 0 ? (
              <EmptyState icon="event" title="Aucun rendez-vous" description="Les réservations de vos clients apparaîtront ici." />
            ) : (
              list.map((a) => (
                <ProAppointmentRow
                  key={a.id}
                  appt={a}
                  serviceName={serviceName}
                  href={`/pro/rendez-vous/${a.id}${bookingQuery}`}
                  tz={tz}
                  currency={currency}
                />
              ))
            )}
          </div>
        </div>
      )}
      {creating && profile ? (
        <ManualBookingDialog
          providerId={profile.provider.id}
          profile={profile}
          initialDate={view === 'journal' ? journalDate : undefined}
          onClose={() => setCreating(false)}
          onCreated={async () => {
            setCreating(false);
            show('Rendez-vous créé', 'success');
            loadJournal();
            const appts = await listProAppointments();
            if (appts.status === 200) setItems(appts.items);
          }}
        />
      ) : null}
      <Toast toast={toast} />
    </div>
  );
}
/// The « Semaine » chrome (docs/design/web-pro-week-view.md): ‹ « Semaine du
/// 19 octobre » ›, « Cette semaine », the « Artiste » filter, « Voir les
/// annulés » — then the grid, or its states.
function WeekView({
  days,
  error,
  onRetry,
  monday,
  tz,
  showCancelled,
  setShowCancelled,
  artistFilter,
  setArtistFilter,
  onWeek,
  onThisWeek,
  children,
}: {
  days: JournalDay[] | null;
  error: LoadFailure | false;
  onRetry: () => void;
  monday: string;
  tz?: string;
  showCancelled: boolean;
  setShowCancelled: (v: boolean) => void;
  artistFilter: string | null;
  setArtistFilter: (v: string | null) => void;
  onWeek: (delta: -1 | 1) => void;
  onThisWeek: () => void;
  children: ReactNode;
}) {
  const artists = days ? weekArtists(days) : [];
  const visible = days
    ? days
        .flatMap((d) => d.appointments)
        .filter((a) => showCancelled || a.status !== 'cancelled')
        .filter((a) => artistFilter === null || (a.artistId ?? '') === artistFilter)
    : [];
  return (
    <div className="mt-m">
      <div className="flex flex-wrap items-center justify-between gap-s">
        <div className="flex flex-wrap items-center gap-s">
          <button
            type="button"
            aria-label="Semaine précédente"
            title="Raccourci : ←"
            className="min-h-12 rounded-lg border border-border px-s py-xs text-textSecondary"
            onClick={() => onWeek(-1)}
          >
            ‹
          </button>
          <p className="text-titleMedium text-textPrimary">
            {weekStripLabel(weekOf(monday), tz)}
          </p>
          <button
            type="button"
            aria-label="Semaine suivante"
            title="Raccourci : →"
            className="min-h-12 rounded-lg border border-border px-s py-xs text-textSecondary"
            onClick={() => onWeek(1)}
          >
            ›
          </button>
          <button
            type="button"
            title="Raccourci : T"
            className="text-bodyMedium text-textTertiary underline"
            onClick={onThisWeek}
          >
            Cette semaine
          </button>
        </div>
        <div className="flex flex-wrap items-center gap-m">
          <label className="flex items-center gap-xs text-bodyMedium text-textSecondary">
            Artiste
            <select
              value={artistFilter ?? '__all'}
              onChange={(e) => setArtistFilter(e.target.value === '__all' ? null : e.target.value)}
              className="min-h-12 rounded-lg border border-borderStrong bg-surface px-s text-bodyMedium text-textPrimary"
            >
              <option value="__all">Tous</option>
              {artists.map((a) => (
                <option key={a.id || 'none'} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </label>
          <label className="flex items-center gap-xs text-bodyMedium text-textSecondary">
            <input
              type="checkbox"
              checked={showCancelled}
              onChange={(e) => setShowCancelled(e.target.checked)}
            />
            Voir les annulés
          </label>
        </div>
      </div>
      {error ? (
        <ErrorState className="mt-l" message={loadFailureMessage(error)} onRetry={onRetry} />
      ) : days ? (
        <>
          {visible.length === 0 ? (
            <p className="mt-m text-bodyMedium text-textTertiary">
              Aucun rendez-vous cette semaine.
            </p>
          ) : null}
          <div className="mt-m">{children}</div>
        </>
      ) : (
        <SkeletonRows count={6} className="mt-l" />
      )}
    </div>
  );
}
