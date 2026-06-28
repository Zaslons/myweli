'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import { type ProProfile, getMyProvider, listProAppointments } from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import {
  type ProAppointment,
  todayCounts,
  todaysAppointments,
} from '../../lib/pro/today';

const slotTime = (iso: string) =>
  new Intl.DateTimeFormat('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
  }).format(new Date(iso));

export function AujourdhuiClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

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

  const today = todaysAppointments(items);
  const counts = todayCounts(items);
  const serviceName = (id: string) =>
    profile?.provider.services?.find((s) => s.id === id)?.name;

  return (
    <div>
      <h1 className="text-2xl font-semibold text-textPrimary">Aujourd’hui</h1>
      <p className="mt-xs text-sm text-textTertiary">{profile?.provider.name}</p>

      <div className="mt-l grid grid-cols-3 gap-m">
        <Stat label="À confirmer" value={counts.pending} />
        <Stat label="Confirmés" value={counts.confirmed} />
        <Stat label="Total du jour" value={counts.total} />
      </div>

      <h2 className="mt-l text-lg font-semibold text-textPrimary">
        Rendez-vous du jour
      </h2>
      <div className="mt-m space-y-s">
        {today.length === 0 ? (
          <p className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
            Aucun rendez-vous aujourd’hui.
          </p>
        ) : (
          today.map((a) => (
            <div
              key={a.id}
              className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m"
            >
              <div>
                <p className="font-medium text-textPrimary">
                  {slotTime(a.appointmentDate)} · {a.clientName ?? 'Client'}
                </p>
                <p className="text-sm text-textTertiary">
                  {(a.serviceIds ?? [])
                    .map(serviceName)
                    .filter(Boolean)
                    .join(', ')}
                </p>
              </div>
              <div className="text-right">
                <span className="rounded-full bg-surface px-s py-xs text-xs text-textSecondary">
                  {statusLabelFr(a.status)}
                </span>
                {typeof a.totalPrice === 'number' ? (
                  <p className="mt-s text-sm text-textPrimary">
                    {formatFcfa(a.totalPrice)}
                  </p>
                ) : null}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl border border-border bg-secondary p-m text-center">
      <p className="text-2xl font-semibold text-textPrimary">{value}</p>
      <p className="text-xs text-textTertiary">{label}</p>
    </div>
  );
}
