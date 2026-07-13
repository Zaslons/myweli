'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import {
  type Appointment,
  canAttachDeposit,
  canCancel,
  canReschedule,
  rebookHref,
  statusLabelFr,
} from '../../lib/account/appointments';
import { buildIcs, googleCalendarUrl } from '../../lib/account/calendar';
import { canRebook, canReview } from '../../lib/account/extras';
import {
  cancelAppointment,
  getAppointment,
  rescheduleAppointment,
} from '../../lib/api/account';
import { fetchSlots } from '../../lib/booking/client';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import { salonFormatter, salonToday } from '../../lib/time';
import { Button } from '../Button';
import { SalonTimeHint } from '../SalonTimeHint';
import { DepositProof } from '../booking/DepositProof';
import { ReviewForm } from './ReviewForm';

export function AppointmentDetailClient({ id }: { id: string }) {
  const router = useRouter();
  const [appt, setAppt] = useState<Appointment | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [cancelError, setCancelError] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  // « Reporter » (parity 1.1) — the app's slot-picker flow, inline.
  const [rescheduling, setRescheduling] = useState(false);
  const [reschedDate, setReschedDate] = useState('');
  const [slots, setSlots] = useState<string[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [pickedSlot, setPickedSlot] = useState<string | null>(null);
  const [reschedError, setReschedError] = useState<string | null>(null);
  const [rescheduled, setRescheduled] = useState(false);

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

  async function loadSlots(a: Appointment, date: string) {
    setSlotsLoading(true);
    setPickedSlot(null);
    const r = await fetchSlots({
      providerId: a.providerId,
      date,
      serviceIds: a.serviceIds ?? [],
      durationMinutes: a.durationMinutes ?? 30,
      artistId: a.artistId ?? null,
    });
    setSlots(r);
    setSlotsLoading(false);
  }

  function openReschedule(a: Appointment) {
    setRescheduling(true);
    setReschedError(null);
    setRescheduled(false);
    const day = a.appointmentDate.slice(0, 10);
    const today = salonToday();
    const initial = day > today ? day : today;
    setReschedDate(initial);
    loadSlots(a, initial);
  }

  async function confirmReschedule() {
    if (!pickedSlot || !appt) return;
    setBusy(true);
    setReschedError(null);
    const r = await rescheduleAppointment(appt.id, pickedSlot);
    setBusy(false);
    if (!r.ok) {
      setReschedError(
        r.status === 409
          ? 'Ce créneau vient d’être pris. Choisissez-en un autre.'
          : 'Le report a échoué. Réessayez.',
      );
      return;
    }
    setRescheduling(false);
    setRescheduled(true);
    await load();
  }

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

        {/* Parity 1.2 — add the booking to a calendar (upcoming only). */}
        {canReschedule(appt) ? (
          <div className="mt-s flex flex-wrap gap-s">
            <a
              href={googleCalendarUrl(appt)}
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-lg border border-border bg-surface px-m py-xs text-sm text-textPrimary hover:bg-surfaceVariant"
            >
              Ajouter au calendrier (Google)
            </a>
            <button
              type="button"
              onClick={() => {
                const blob = new Blob([buildIcs(appt)], {
                  type: 'text/calendar',
                });
                const url = URL.createObjectURL(blob);
                const el = document.createElement('a');
                el.href = url;
                el.download = 'rendez-vous-myweli.ics';
                el.click();
                URL.revokeObjectURL(url);
              }}
              className="rounded-lg border border-border bg-surface px-m py-xs text-sm text-textPrimary hover:bg-surfaceVariant"
            >
              Fichier .ics
            </button>
          </div>
        ) : null}

        {/* Parity 1.6 — contact the salon from the booking. */}
        {appt.providerPhone || appt.providerWhatsapp ? (
          <div className="mt-s flex flex-wrap gap-s">
            {appt.providerPhone ? (
              <a
                href={`tel:${appt.providerPhone.replace(/\s/g, '')}`}
                className="rounded-lg border border-border bg-surface px-m py-xs text-sm text-textPrimary hover:bg-surfaceVariant"
              >
                Appeler
              </a>
            ) : null}
            {appt.providerWhatsapp ? (
              <a
                href={`https://wa.me/${appt.providerWhatsapp.replace(/[^0-9]/g, '')}`}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-lg border border-border bg-surface px-m py-xs text-sm text-textPrimary hover:bg-surfaceVariant"
              >
                WhatsApp
              </a>
            ) : null}
          </div>
        ) : null}

        <dl className="mt-m space-y-xs text-sm">
          <Row label="Date" value={formatDateTimeFr(appt.appointmentDate)} />
          {appt.serviceNames && appt.serviceNames.length > 0 ? (
            <Row label="Prestations" value={appt.serviceNames.join(', ')} />
          ) : null}
          {appt.artistName ? (
            <Row label="Spécialiste" value={appt.artistName} />
          ) : null}
          {appt.notes ? <Row label="Notes" value={appt.notes} /> : null}
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
        <SalonTimeHint date={appt.appointmentDate} />

        {appt.salonEntered ? (
          <p className="mt-m text-xs text-textTertiary">
            Réservé par votre salon.
          </p>
        ) : null}

        {/* Pay-later (K2): attach the deposit proof from the detail too. */}
        {canAttachDeposit(appt) ? (
          <div className="mt-m">
            <DepositProof
              appointmentId={appt.id}
              amount={appt.depositAmount ?? 0}
              operator={appt.depositMobileMoneyOperator}
              number={appt.depositMobileMoneyNumber}
              onAttached={load}
            />
          </div>
        ) : appt.status === 'pending' && appt.depositScreenshotUrl ? (
          <p className="mt-m text-sm text-textSecondary">
            Justificatif d’acompte envoyé · en attente de confirmation du
            salon.{' '}
            <a
              href={`/api/appointments/${appt.id}/deposit-screenshot?redirect=1`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-textPrimary underline"
            >
              Voir ma capture
            </a>
          </p>
        ) : null}

        {cancelError ? (
          <p className="mt-s text-sm text-error">
            L’annulation a échoué. Réessayez.
          </p>
        ) : null}

        {rescheduled ? (
          <p className="mt-m text-sm text-textSecondary">
            Rendez-vous reporté ✓
          </p>
        ) : null}

        {/* « Reporter » (parity 1.1) — the app's slot-picker flow. */}
        {canReschedule(appt) ? (
          <div className="mt-l">
            {!rescheduling ? (
              <Button onClick={() => openReschedule(appt)}>Reporter</Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-sm text-textPrimary">
                  Choisissez un nouveau créneau
                </p>
                <input
                  type="date"
                  aria-label="Nouvelle date"
                  min={salonToday()}
                  value={reschedDate}
                  onChange={(e) => {
                    setReschedDate(e.target.value);
                    if (e.target.value) loadSlots(appt, e.target.value);
                  }}
                  className="mt-s rounded-lg border border-border bg-secondary px-m py-s text-sm text-textPrimary"
                />
                {slotsLoading ? (
                  <p className="mt-s text-sm text-textSecondary">
                    Chargement des créneaux…
                  </p>
                ) : slots.length === 0 ? (
                  <p className="mt-s text-sm text-textSecondary">
                    Aucun créneau disponible ce jour.
                  </p>
                ) : (
                  <div className="mt-s flex flex-wrap gap-s">
                    {slots.map((iso) => (
                      <button
                        key={iso}
                        type="button"
                        onClick={() => setPickedSlot(iso)}
                        className={`rounded-full border px-m py-xs text-sm ${
                          pickedSlot === iso
                            ? 'border-primary bg-primary text-secondary'
                            : 'border-border bg-secondary text-textPrimary'
                        }`}
                      >
                        {salonFormatter({
                          hour: '2-digit',
                          minute: '2-digit',
                        }).format(new Date(iso))}
                      </button>
                    ))}
                  </div>
                )}
                {reschedError ? (
                  <p className="mt-s text-sm text-error">{reschedError}</p>
                ) : null}
                <div className="mt-m flex gap-s">
                  <Button
                    variant="secondary"
                    onClick={() => setRescheduling(false)}
                  >
                    Retour
                  </Button>
                  <Button
                    disabled={busy || !pickedSlot}
                    onClick={confirmReschedule}
                  >
                    Confirmer le report
                  </Button>
                </div>
              </div>
            )}
          </div>
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

        {canRebook(appt.status) && rebookHref(appt) ? (
          <div className="mt-l">
            <Link
              href={rebookHref(appt)!}
              className="inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary hover:bg-primaryLight"
            >
              Réserver à nouveau
            </Link>
          </div>
        ) : null}

        {canReview(appt.status) ? (
          <div className="mt-l border-t border-divider pt-l">
            <ReviewForm appointmentId={appt.id} />
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
