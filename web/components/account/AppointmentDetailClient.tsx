'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import {
  type Appointment,
  canCancel,
  statusLabelFr,
} from '../../lib/account/appointments';
import { cancelAppointment, getAppointment } from '../../lib/api/account';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import { Button } from '../Button';

export function AppointmentDetailClient({ id }: { id: string }) {
  const router = useRouter();
  const [appt, setAppt] = useState<Appointment | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [cancelError, setCancelError] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const r = await getAppointment(id);
    if (r.status === 401) {
      router.replace(`/connexion?returnTo=/mon-compte/${id}`);
      return;
    }
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

  async function cancel() {
    setBusy(true);
    setCancelError(false);
    const r = await cancelAppointment(id);
    setBusy(false);
    setConfirming(false);
    if (!r.ok) {
      setCancelError(true);
      return;
    }
    await load();
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (notFound || !appt) {
    return <p className="text-error">Rendez-vous introuvable.</p>;
  }

  return (
    <div>
      <Link href="/mon-compte" className="text-sm text-textTertiary">
        ← Mes rendez-vous
      </Link>
      <section className="mt-m rounded-xl border border-border bg-secondary p-l">
        <div className="flex items-center justify-between gap-m">
          <h2 className="text-lg font-semibold text-textPrimary">
            {appt.providerName ?? 'Salon'}
          </h2>
          <span className="rounded-full bg-surface px-s py-xs text-xs text-textSecondary">
            {statusLabelFr(appt.status)}
          </span>
        </div>
        {appt.providerSlug ? (
          <Link
            href={`/${appt.providerSlug}`}
            className="text-sm text-textPrimary underline"
          >
            Voir le salon
          </Link>
        ) : null}

        <dl className="mt-m space-y-xs text-sm">
          <Row label="Date" value={formatDateTimeFr(appt.appointmentDate)} />
          {appt.serviceNames && appt.serviceNames.length > 0 ? (
            <Row label="Prestations" value={appt.serviceNames.join(', ')} />
          ) : null}
          {typeof appt.totalPrice === 'number' ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice)} />
          ) : null}
          {appt.depositAmount ? (
            <Row label="Acompte" value={formatFcfa(appt.depositAmount)} />
          ) : null}
          {typeof appt.balanceDue === 'number' ? (
            <Row label="Reste à payer" value={formatFcfa(appt.balanceDue)} />
          ) : null}
        </dl>

        {appt.salonEntered ? (
          <p className="mt-m text-xs text-textTertiary">
            Réservé par votre salon.
          </p>
        ) : null}

        {cancelError ? (
          <p className="mt-s text-sm text-error">
            L’annulation a échoué. Réessayez.
          </p>
        ) : null}

        {canCancel(appt) ? (
          <div className="mt-l">
            {!confirming ? (
              <Button variant="secondary" onClick={() => setConfirming(true)}>
                Annuler le rendez-vous
              </Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-sm text-textSecondary">
                  Confirmer l’annulation&nbsp;?
                  {appt.depositAmount
                    ? ' L’acompte peut ne pas être remboursé selon la politique du salon.'
                    : ''}
                </p>
                <div className="mt-s flex gap-s">
                  <Button
                    variant="secondary"
                    onClick={() => setConfirming(false)}
                  >
                    Retour
                  </Button>
                  <Button disabled={busy} onClick={cancel}>
                    Confirmer l’annulation
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
