'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  type DashboardStats,
  type ProProfile,
  getDashboard,
  getMyProvider,
  listProAppointments,
} from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import {
  type ProAppointment,
  todayCounts,
  todaysAppointments,
} from '../../lib/pro/today';
import { GoLiveCard } from './GoLiveCard';
import { ProAppointmentRow } from './ProAppointmentRow';

export function AujourdhuiClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [live, setLive] = useState(false);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [stats, setStats] = useState<DashboardStats | null>(null);
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
      // Revenue stats are best-effort — don't block the bookings list.
      if (me.profile) {
        const dash = await getDashboard(me.profile.provider.id);
        if (active && dash.status === 200) setStats(dash.stats ?? null);
      }
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

      {/* Draft salons: the go-live checklist (pro-salon-lifecycle.md B2). */}
      {profile?.provider.status === 'draft' ? (
        <GoLiveCard
          profile={profile}
          onPublished={() => {
            setProfile({
              ...profile,
              provider: { ...profile.provider, status: 'active' },
            });
            setLive(true);
          }}
        />
      ) : null}
      {live ? (
        <p className="mt-m rounded-xl border border-success/40 bg-success/10 p-m text-sm text-success">
          🎉 Votre salon est en ligne ! Il apparaît maintenant dans les
          recherches.
        </p>
      ) : null}

      <Link
        href="/pro/profil"
        className="mt-m flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-sm text-textPrimary hover:bg-surfaceVariant"
      >
        <span>Configurer mon profil</span>
        <span className="text-textTertiary">›</span>
      </Link>

      {profile?.provider.status === 'active' && profile.provider.slug ? (
        <Link
          href={`/${profile.provider.slug}`}
          className="mt-s flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-sm text-textPrimary hover:bg-surfaceVariant"
        >
          <span>Voir ma page publique</span>
          <span className="text-textTertiary">›</span>
        </Link>
      ) : null}

      <div className="mt-l grid grid-cols-3 gap-m">
        <Stat label="À confirmer" value={counts.pending} />
        <Stat label="Confirmés" value={counts.confirmed} />
        <Stat label="Total du jour" value={counts.total} />
      </div>

      <div className="mt-m grid grid-cols-2 gap-m">
        <Stat
          label="Revenus aujourd’hui"
          value={stats ? formatFcfa(stats.todayRevenue ?? 0) : '—'}
        />
        <Stat
          label="Revenus ce mois"
          value={stats ? formatFcfa(stats.monthRevenue ?? 0) : '—'}
        />
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
  );
}

function Stat({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <div className="rounded-xl border border-border bg-secondary p-m text-center">
      <p className="text-xl font-semibold text-textPrimary">{value}</p>
      <p className="text-xs text-textTertiary">{label}</p>
    </div>
  );
}
