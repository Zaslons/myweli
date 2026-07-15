'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { type ProProfile, getMyProvider, listProAppointments } from '../../lib/api/pro';
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
import { hasCap } from '../../lib/pro/team';
import type { ProAppointment } from '../../lib/pro/today';
import { salonFormatter } from '../../lib/time';
import { JournalGrid } from './JournalGrid';
import { ManualBookingDialog } from './ManualBookingDialog';
import { MonthCalendar } from './MonthCalendar';
import { ProAppointmentRow } from './ProAppointmentRow';

type View = 'journal' | 'calendar' | 'list';

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
  const [error, setError] = useState(false);
  const [view, setView] = useState<View>('journal');
  const [journalDay, setJournalDay] = useState<JournalDay | null>(null);
  const [journalDate, setJournalDate] = useState<string>(dateKey(new Date()));
  const [showCancelled, setShowCancelled] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [focused, setFocused] = useState<Date>(new Date());
  const [selected, setSelected] = useState<string>(dateKey(new Date()));
  const [listTab, setListTab] = useState<ListTab>('today');
  const [creating, setCreating] = useState(false);

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
        setError(true);
        setLoading(false);
        return;
      }
      setProfile(me.profile ?? null);
      setItems(appts.items);
      // « Aujourd'hui » is the ACTIVE salon's day (multi-pays MP3) — the
      // pre-profile defaults assumed Abidjan; realign before first paint.
      const salonTz = me.profile?.provider.timezone ?? undefined;
      setJournalDate(dateKey(new Date(), salonTz));
      setSelected(dateKey(new Date(), salonTz));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  const loadJournal = useCallback(async () => {
    if (!profile) return;
    const r = await getJournalDay(profile.provider.id, journalDate);
    if (r.status === 200 && r.day) setJournalDay(r.day);
  }, [profile, journalDate]);

  useEffect(() => {
    if (view === 'journal') loadJournal();
  }, [view, loadJournal]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2500);
    return () => clearTimeout(t);
  }, [toast]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const serviceName = (id: string) =>
    profile?.provider.services?.find((s) => s.id === id)?.name;
  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;
  const dayList = appointmentsOnDate(items, selected, tz);
  const list = filterList(items, listTab, new Date(), tz);

  // Team access R5b: own-scope roles (Collaborateur) get a read-only,
  // server-filtered planning — no creation, no drag.
  const canManageAll = hasCap(profile?.membership, 'journal.manage.all');

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-s">
        <h1 className="text-2xl font-semibold text-textPrimary">
          {canManageAll
            ? 'Rendez-vous'
            : `${profile?.provider.name ?? ''} — votre planning`}
        </h1>
        {profile && canManageAll ? (
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="rounded-lg bg-primary px-m py-s text-sm font-medium text-secondary hover:bg-primaryHover"
          >
            + Nouveau rendez-vous
          </button>
        ) : null}
      </div>

      <div className="mt-l flex gap-s border-b border-divider">
        {(['journal', 'calendar', 'list'] as View[]).map((v) => (
          <button
            key={v}
            type="button"
            onClick={() => setView(v)}
            className={`px-m py-s text-sm ${
              view === v
                ? 'border-b-2 border-primary text-textPrimary'
                : 'text-textTertiary'
            }`}
          >
            {v === 'journal' ? 'Journée' : v === 'calendar' ? 'Calendrier' : 'Liste'}
          </button>
        ))}
      </div>

      {view === 'journal' ? (
        <div className="mt-m">
          <div className="flex flex-wrap items-center justify-between gap-s">
            <div className="flex items-center gap-s">
              <button
                type="button"
                aria-label="Jour précédent"
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
                className="rounded-lg border border-border bg-surface px-s py-xs text-sm text-textPrimary"
              />
              <button
                type="button"
                aria-label="Jour suivant"
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
                className="text-sm text-textTertiary underline"
                onClick={() => setJournalDate(dateKey(new Date(), tz))}
              >
                Aujourd’hui
              </button>
            </div>
            <label className="flex items-center gap-xs text-sm text-textSecondary">
              <input
                type="checkbox"
                checked={showCancelled}
                onChange={(e) => setShowCancelled(e.target.checked)}
              />
              Voir les annulés
            </label>
          </div>
          {profile && journalDay ? (
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
                onToast={setToast}
              />
            </div>
          ) : (
            <p className="mt-l text-textSecondary">Chargement du planning…</p>
          )}
        </div>
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
            <p className="text-sm text-textTertiary">
              pour {dayLabel(selected, tz)}
            </p>
            <div className="mt-s space-y-s">
              {dayList.length === 0 ? (
                <p className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
                  Aucun rendez-vous ce jour-là.
                </p>
              ) : (
                dayList.map((a) => (
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
      ) : (
        <div className="mt-m">
          <div className="flex gap-s border-b border-divider">
            {LIST_TABS.map((t) => (
              <button
                key={t.key}
                type="button"
                onClick={() => setListTab(t.key)}
                className={`px-m py-s text-sm ${
                  listTab === t.key
                    ? 'border-b-2 border-primary text-textPrimary'
                    : 'text-textTertiary'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>
          <div className="mt-m space-y-s">
            {list.length === 0 ? (
              <p className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
                Aucun rendez-vous.
              </p>
            ) : (
              list.map((a) => (
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
      )}
      {creating && profile ? (
        <ManualBookingDialog
          providerId={profile.provider.id}
          profile={profile}
          initialDate={view === 'journal' ? journalDate : undefined}
          onClose={() => setCreating(false)}
          onCreated={async () => {
            setCreating(false);
            setToast('Rendez-vous créé');
            loadJournal();
            const appts = await listProAppointments();
            if (appts.status === 200) setItems(appts.items);
          }}
          onToast={setToast}
        />
      ) : null}
      {toast ? (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-lg bg-primary px-l py-s text-sm text-secondary shadow-lg">
          {toast}
        </div>
      ) : null}
    </div>
  );
}