'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import { noShowBadge, noShowLabel } from '../../lib/pro/clients';
import {
  type ProProfile,
  getMyProvider,
  getProAppointment,
  proAction,
  proDepositScreenshotUrl,
} from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import { type LifecycleAction, actionsFor } from '../../lib/pro/lifecycle';
import type { ProAppointment } from '../../lib/pro/today';
import { Button } from '../Button';

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

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (notFound || !appt) {
    return <p className="text-error">Rendez-vous introuvable.</p>;
  }

  const serviceName = (sid: string) =>
    profile?.provider.services?.find((s) => s.id === sid)?.name;
  const services =
    (appt.serviceIds ?? []).map(serviceName).filter(Boolean).join(', ') || '—';
  const actions = actionsFor(appt.status);

  return (
    <div>
      <Link href="/pro/rendez-vous" className="text-sm text-textTertiary">
        ← Rendez-vous
      </Link>
      <h1 className="mt-m text-2xl font-semibold text-textPrimary">
        Détails du rendez-vous
      </h1>

      <section className="mt-m rounded-xl border border-border bg-secondary p-l">
        <div className="flex items-center justify-between gap-m">
          <p className="flex items-center gap-s font-medium text-textPrimary">
            {appt.clientName ?? 'Client'}
            {noShowBadge(appt.clientNoShowCount) !== 'none' ? (
              <span
                className={`rounded-full px-s py-xs text-xs font-normal ${
                  noShowBadge(appt.clientNoShowCount) === 'red'
                    ? 'bg-error/10 text-error'
                    : 'bg-surface text-textSecondary'
                }`}
              >
                {noShowLabel(appt.clientNoShowCount ?? 0)}
              </span>
            ) : null}
            {appt.salonClientId ? (
              <Link
                href={`/pro/clients/${appt.salonClientId}`}
                className="text-xs font-normal text-textTertiary underline"
              >
                Voir la fiche
              </Link>
            ) : null}
          </p>
          <span className="rounded-full bg-surface px-s py-xs text-xs text-textSecondary">
            {statusLabelFr(appt.status)}
          </span>
        </div>

        <dl className="mt-m space-y-xs text-sm">
          <Row label="Date" value={formatDateTimeFr(appt.appointmentDate)} />
          {appt.clientPhone ? (
            <Row label="Téléphone" value={appt.clientPhone} />
          ) : null}
          <Row label="Prestations" value={services} />
          {typeof appt.totalPrice === 'number' ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice)} />
          ) : null}
          {appt.depositAmount ? (
            <Row label="Acompte annoncé" value={formatFcfa(appt.depositAmount)} />
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
          <p className="mt-s text-xs text-textTertiary">
            Justificatif d’acompte non reçu.
          </p>
        ) : null}

        {error ? <p className="mt-s text-sm text-error">{error}</p> : null}

        {actions.length > 0 ? (
          <div className="mt-l flex flex-wrap gap-s">
            {actions.map((a) =>
              confirm === a.action ? (
                <div
                  key={a.action}
                  className="w-full rounded-lg bg-surface p-m"
                >
                  <p className="text-sm text-textSecondary">{a.confirm}</p>
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
