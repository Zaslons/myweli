'use client';

import Link from 'next/link';
import { SkeletonRows } from '../Skeleton';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  type DashboardStats,
  type ProProfile,
  getDashboard,
  getMyProvider,
  getSalonSubscription,
  listProAppointments,
} from '../../lib/api/pro';
import { formatFcfa } from '../../lib/format';
import { hasCap } from '../../lib/pro/team';
import {
  type ProAppointment,
  todayCounts,
  todaysAppointments,
} from '../../lib/pro/today';
import { GoLiveCard } from './GoLiveCard';
import { ProAppointmentRow } from './ProAppointmentRow';
import { ProInvitationsCard } from './ProInvitationsCard';

export function AujourdhuiClient() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [live, setLive] = useState(false);
  const [items, setItems] = useState<ProAppointment[]>([]);
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [offerLive, setOfferLive] = useState(false);
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
      // Secondary fetches are capability-gated (team access R5b): the server
      // would 403/field-gate them anyway — skipping is the honest UI.
      if (me.profile) {
        const m = me.profile.membership;
        if (hasCap(m, 'journal.view.all')) {
          // Revenue stats are best-effort — don't block the bookings list.
          const dash = await getDashboard(me.profile.provider.id);
          if (active && dash.status === 200) setStats(dash.stats ?? null);
        }
        // A draft salon needs a live offer to publish (team access R5a) —
        // owner-only concern (salon.publish).
        if (
          me.profile.provider.status === 'draft' &&
          hasCap(m, 'salon.publish')
        ) {
          const sub = await getSalonSubscription(me.profile.provider.id);
          if (active && sub.status === 200 && sub.offer) {
            setOfferLive(
              sub.offer.status === 'trial' || sub.offer.status === 'paid',
            );
          }
        }
      }
    })();
    return () => {
      active = false;
    };
  }, [router]);

  if (loading) return <SkeletonRows count={4} className="mt-l" />;
  if (error) {
    return <p role="alert" className="text-error">Une erreur est survenue. Réessayez.</p>;
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
          {salonName} — votre planning
        </h1>

        {/* Pending invitations for THIS account (if any). */}
        <ProInvitationsCard />

        <h2 className="mt-l text-titleLarge font-semibold text-textPrimary">
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

      {/* Team access R5a: pending invitations for THIS account (if any). */}
      <ProInvitationsCard />

      {/* Draft salons: the go-live checklist (pro-salon-lifecycle.md B2) —
          publishing is the owner's act (salon.publish). */}
      {profile?.provider.status === 'draft' && hasCap(m, 'salon.publish') ? (
        <GoLiveCard
          profile={profile}
          offerLive={offerLive}
          onPublished={() => {
            setProfile({
              ...profile,
              provider: { ...profile.provider, status: 'active' },
            });
            setLive(true);
          }}
        />
      ) : null}
      <p
        role="status"
        className={
          live
            ? 'mt-m rounded-xl border border-success/40 bg-success/10 p-m text-bodyMedium text-success'
            : 'sr-only'
        }
      >
        {live
          ? '🎉 Votre salon est en ligne ! Il apparaît maintenant dans les recherches.'
          : ''}
      </p>

      {hasCap(m, 'profile.manage') ? (
        <Link
          href="/pro/profil"
          className="mt-m flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
        >
          <span>Configurer mon profil</span>
          <span className="text-textTertiary">›</span>
        </Link>
      ) : null}

      {profile?.provider.status === 'active' && profile.provider.slug ? (
        <Link
          href={`/${profile.provider.slug}`}
          className="mt-s flex items-center justify-between rounded-xl border border-border bg-secondary p-m text-bodyMedium text-textPrimary hover:bg-surfaceVariant"
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

      {/* The money row needs finances.view — the server drops the revenue
          fields for other roles, so rendering it would show a lying 0 F. */}
      {hasCap(m, 'finances.view') ? (
        <div className="mt-m grid grid-cols-3 gap-m">
          <Stat
            label="Revenus aujourd’hui"
            value={stats ? formatFcfa(stats.todayRevenue ?? 0, currency) : '—'}
          />
          <Stat
            label="Revenus cette semaine"
            value={stats ? formatFcfa(stats.weekRevenue ?? 0, currency) : '—'}
          />
          <Stat
            label="Revenus ce mois"
            value={stats ? formatFcfa(stats.monthRevenue ?? 0, currency) : '—'}
          />
        </div>
      ) : null}

      <h2 className="mt-l text-titleLarge font-semibold text-textPrimary">
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
              tz={tz}
              currency={currency}
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
      <p className="text-titleLarge font-semibold text-textPrimary">{value}</p>
      <p className="text-bodySmall text-textTertiary">{label}</p>
    </div>
  );
}
