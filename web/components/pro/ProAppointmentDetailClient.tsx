'use client';

import Link from 'next/link';
import { Chip } from '../Chip';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import { noShowBadge, noShowLabel } from '../../lib/pro/clients';
import {
  type ProProfile,
  getMyProvider,
  arriveAppointment,
  getProAppointment,
  proAction,
  proDepositScreenshotUrl,
} from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import {
  type LifecycleAction,
  actionsForMembership,
} from '../../lib/pro/lifecycle';
import { hasCap } from '../../lib/pro/team';
import { rescheduleAppointment } from '../../lib/api/pro';
import { hhmm, minutesOfDay } from '../../lib/pro/journal';
import { combineDateTime } from '../../lib/pro/manual-booking';
import type { ProAppointment } from '../../lib/pro/today';
import { isSameSalonDay, salonDayKey, salonFormatter } from '../../lib/time';
import { Button } from '../Button';
import { Loading } from '../Loading';

export function ProAppointmentDetailClient({ id }: { id: string }) {
  const router = useRouter();
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [appt, setAppt] = useState<ProAppointment | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<LifecycleAction | null>(null);
  const [proofUrl, setProofUrl] = useState<string | null>(null);

  const load = useCallback(async () => {
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    const r = await getProAppointment(id);
    if (r.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    setProfile(me.profile ?? null);
    if (r.status !== 200 || !r.appt) {
      setNotFound(true);
      setLoading(false);
      return;
    }
    setAppt(r.appt);
    setLoading(false);
  }, [id, router]);

  useEffect(() => {
    load();
  }, [load]);

  // « Reprogrammer » (parity 1.9) — cross-day, the app's date+time flow;
  // the server re-validates (409 → créneau indisponible).
  const [reprog, setReprog] = useState(false);
  const [reprogDate, setReprogDate] = useState('');
  const [reprogTime, setReprogTime] = useState('');
  const [reprogError, setReprogError] = useState<string | null>(null);

  async function reschedule() {
    if (!reprogDate || !reprogTime) return;
    setBusy(true);
    setReprogError(null);
    // The picked wall-clock IS salon time — offset-aware build through the
    // seam (multi-pays MP3).
    const r = await rescheduleAppointment(
      id,
      combineDateTime(
        reprogDate,
        reprogTime,
        profile?.provider.timezone ?? undefined,
      ) ?? '',
    );
    setBusy(false);
    if (!r.ok) {
      setReprogError(
        r.status === 409
          ? 'Créneau indisponible. Choisissez un autre horaire.'
          : 'Le report a échoué. Réessayez.',
      );
      return;
    }
    setReprog(false);
    await load();
  }

  async function run(action: LifecycleAction) {
    setBusy(true);
    setError(null);
    setConfirm(null);
    const r = await proAction(id, action);
    setBusy(false);
    if (!r.ok) {
      setError(
        r.status === 409
          ? 'Action impossible — le statut a déjà changé.'
          : 'L’action a échoué. Réessayez.',
      );
      return;
    }
    await load();
  }

  if (loading) return <Loading className="mt-l" />;
  if (notFound || !appt) {
    return (
      <div>
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          Rendez-vous
        </h1>
        <p role="alert" className="mt-m text-bodyMedium text-error">
          Rendez-vous introuvable.
        </p>
        <p className="mt-m">
          <Link href="/pro/rendez-vous" className="text-bodyMedium underline">
            ← Rendez-vous
          </Link>
        </p>
      </div>
    );
  }

  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile?.provider.timezone ?? undefined;
  const currency = profile?.provider.currency ?? undefined;
  const serviceName = (sid: string) =>
    profile?.provider.services?.find((s) => s.id === sid)?.name;
  const services =
    (appt.serviceIds ?? []).map(serviceName).filter(Boolean).join(', ') || '—';
  // Team access R5b: the role-shaped action set (staff = Terminé/Absent on
  // their own confirmed bookings; the server enforces T40 regardless).
  const membership = profile?.membership;
  const actions = actionsForMembership(appt.status, membership);
  const canManageAll = hasCap(membership, 'journal.manage.all');
  const canViewClients = hasCap(membership, 'clients.view');

  return (
    <div>
      <Link href="/pro/rendez-vous" className="text-bodyMedium text-textTertiary">
        ← Rendez-vous
      </Link>
      <h1 className="mt-m text-headlineSmall font-semibold text-textPrimary">
        Détails du rendez-vous
      </h1>

      <section className="mt-m rounded-xl border border-border bg-secondary p-l">
        <div className="flex items-center justify-between gap-m">
          <p className="flex items-center gap-s font-medium text-textPrimary">
            {appt.clientName ?? 'Client'}
            {noShowBadge(appt.clientNoShowCount) !== 'none' ? (
              <Chip
                variant={noShowBadge(appt.clientNoShowCount) === 'red' ? 'tinted' : 'neutral'}
                tint="error"
              >
                {noShowLabel(appt.clientNoShowCount ?? 0)}
              </Chip>
            ) : null}
            {appt.salonClientId && canViewClients ? (
              <Link
                href={`/pro/clients/${appt.salonClientId}`}
                className="text-bodySmall font-normal text-textTertiary underline"
              >
                Voir la fiche
              </Link>
            ) : null}
          </p>
          <Chip>
            {statusLabelFr(appt.status)}
          </Chip>
        </div>

        <dl className="mt-m space-y-xs text-bodyMedium">
          <Row
            label="Date"
            value={formatDateTimeFr(appt.appointmentDate, tz)}
          />
          {appt.clientPhone ? (
            <Row label="Téléphone" value={appt.clientPhone} />
          ) : null}
          <Row label="Prestations" value={services} />
          {typeof appt.totalPrice === 'number' ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice, currency)} />
          ) : null}
          {appt.depositAmount ? (
            <Row
              label="Acompte annoncé"
              value={formatFcfa(appt.depositAmount, currency)}
            />
          ) : null}
        </dl>

        {appt.depositScreenshotUrl ? (
          <div className="mt-m">
            {proofUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={proofUrl}
                alt="Justificatif d’acompte"
                className="max-h-80 rounded-lg border border-border"
              />
            ) : (
              <Button
                variant="secondary"
                onClick={async () => setProofUrl(await proDepositScreenshotUrl(id))}
              >
                Voir le justificatif
              </Button>
            )}
          </div>
        ) : appt.depositAmount ? (
          <p className="mt-s text-bodySmall text-textTertiary">
            Justificatif d’acompte non reçu.
          </p>
        ) : null}

        {error ? <p role="alert" className="mt-s text-bodyMedium text-error">{error}</p> : null}

        {actions.length > 0 ? (
          <div className="mt-l flex flex-wrap gap-s">
            {actions.map((a) =>
              confirm === a.action ? (
                <div
                  key={a.action}
                  className="w-full rounded-lg bg-surface p-m"
                >
                  <p className="text-bodyMedium text-textSecondary">{a.confirm}</p>
                  <div className="mt-s flex gap-s">
                    <Button variant="secondary" onClick={() => setConfirm(null)}>
                      Annuler
                    </Button>
                    <Button disabled={busy} onClick={() => run(a.action)}>
                      Confirmer
                    </Button>
                  </div>
                </div>
              ) : (
                <Button
                  key={a.action}
                  variant={a.variant}
                  disabled={busy}
                  onClick={() =>
                    a.confirm ? setConfirm(a.action) : run(a.action)
                  }
                >
                  {a.label}
                </Button>
              ),
            )}
          </div>
        ) : null}

        {/* Parity 1.10 (J1b §4.2 debt): arrival from the detail page too. */}
        {appt.arrivedAt ? (
          <p className="mt-m text-bodyMedium text-textSecondary">
            Arrivé à{' '}
            {salonFormatter({ hour: '2-digit', minute: '2-digit' }, tz).format(
              new Date(appt.arrivedAt),
            )}
          </p>
        ) : appt.status === 'confirmed' &&
          canManageAll &&
          isSameSalonDay(new Date(appt.appointmentDate), new Date(), tz) ? (
          <div className="mt-m">
            <Button
              variant="secondary"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                const r = await arriveAppointment(id);
                setBusy(false);
                if (!r.ok) {
                  setError('Impossible d’enregistrer l’arrivée.');
                  return;
                }
                await load();
              }}
            >
              Client arrivé
            </Button>
          </div>
        ) : null}

        {(appt.status === 'pending' || appt.status === 'confirmed') &&
        canManageAll ? (
          <div className="mt-m border-t border-divider pt-m">
            {!reprog ? (
              <Button
                variant="secondary"
                disabled={busy}
                onClick={() => {
                  setReprog(true);
                  setReprogError(null);
                  // Prefill with the SALON wall-clock (multi-pays MP3).
                  setReprogDate(
                    salonDayKey(new Date(appt.appointmentDate), tz),
                  );
                  setReprogTime(hhmm(minutesOfDay(appt.appointmentDate, tz)));
                }}
              >
                Reprogrammer
              </Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-bodyMedium text-textPrimary">
                  Nouvelle date et heure
                </p>
                <div className="mt-s flex flex-wrap gap-s">
                  <input
                    type="date"
                    aria-label="Nouvelle date"
                    value={reprogDate}
                    onChange={(e) => setReprogDate(e.target.value)}
                    className="min-h-12 rounded-lg border border-borderStrong bg-secondary p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
                  />
                  <input
                    type="time"
                    aria-label="Nouvelle heure"
                    step={900}
                    value={reprogTime}
                    onChange={(e) => setReprogTime(e.target.value)}
                    className="min-h-12 rounded-lg border border-borderStrong bg-secondary p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
                  />
                </div>
                {reprogError ? (
                  <p role="alert" className="mt-s text-bodyMedium text-error">{reprogError}</p>
                ) : null}
                <div className="mt-m flex gap-s">
                  <Button variant="secondary" onClick={() => setReprog(false)}>
                    Annuler
                  </Button>
                  <Button
                    disabled={busy || !reprogDate || !reprogTime}
                    onClick={reschedule}
                  >
                    Confirmer
                  </Button>
                </div>
              </div>
            )}
          </div>
        ) : null}
      </section>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-m">
      <dt className="text-textTertiary">{label}</dt>
      <dd className="text-right text-textPrimary">{value}</dd>
    </div>
  );
}
