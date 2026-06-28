'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { type ProProfile, getMyProvider, listProAppointments } from '../../lib/api/pro';
import {
  type ListTab,
  LIST_TABS,
  appointmentsOnDate,
  dateKey,
  filterList,
} from '../../lib/pro/agenda';
import type { ProAppointment } from '../../lib/pro/today';
import { MonthCalendar } from './MonthCalendar';
import { ProAppointmentRow } from './ProAppointmentRow';

type View = 'calendar' | 'list';

const dayLabel = (key: string) =>
  new Intl.DateTimeFormat('fr-FR', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${key}T00:00:00.000Z`));

export function RendezVousClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [view, setView] = useState<View>('calendar');
  const [focused, setFocused] = useState<Date>(new Date());
  const [selected, setSelected] = useState<string>(dateKey(new Date()));
  const [listTab, setListTab] = useState<ListTab>('today');

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
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (error) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const serviceName = (id: string) =>
    profile?.provider.services?.find((s) => s.id === id)?.name;
  const dayList = appointmentsOnDate(items, selected);
  const list = filterList(items, listTab);

  return (
    <div>
      <h1 className="text-2xl font-semibold text-textPrimary">Rendez-vous</h1>

      <div className="mt-l flex gap-s border-b border-divider">
        {(['calendar', 'list'] as View[]).map((v) => (
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
            {v === 'calendar' ? 'Calendrier' : 'Liste'}
          </button>
        ))}
      </div>

      {view === 'calendar' ? (
        <div className="mt-m grid gap-l md:grid-cols-2">
          <MonthCalendar
            items={items}
            focused={focused}
            selected={selected}
            onFocus={setFocused}
            onSelect={setSelected}
          />
          <div>
            <p className="text-sm text-textTertiary">pour {dayLabel(selected)}</p>
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
                />
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
