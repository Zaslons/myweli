'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { statusLabelFr } from '../../lib/account/appointments';
import {
  arriveAppointment,
  getClientCard,
  proAction,
  rescheduleAppointment,
} from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import type { SalonClientCard } from '../../lib/pro/clients';
import { maskPhone, noShowBadge, noShowLabel } from '../../lib/pro/clients';
import { statusKey } from '../../lib/pro/journal';
import type { ProAppointment } from '../../lib/pro/today';
import { Button } from '../Button';

/// The journal side panel (module journal J1 §3.4): booking facts + the C2
/// client mini-card (audited read) + state-aware actions.
export function JournalPanel({
  providerId,
  appt,
  serviceName,
  onClose,
  onChanged,
  onToast,
}: {
  providerId: string;
  appt: ProAppointment;
  serviceName: (id: string) => string | undefined;
  onClose: () => void;
  onChanged: () => void;
  onToast: (msg: string) => void;
}) {
  const [card, setCard] = useState<SalonClientCard | null>(null);
  const [busy, setBusy] = useState(false);
  // « Reprogrammer » (parity 1.9) — cross-day from the panel too.
  const [reprog, setReprog] = useState(false);
  const [reprogDate, setReprogDate] = useState('');
  const [reprogTime, setReprogTime] = useState('');
  const key = statusKey(appt);

  // C2: the client mini-card (this GET is audited server-side, by design).
  useEffect(() => {
    let active = true;
    if (appt.salonClientId) {
      getClientCard(providerId, appt.salonClientId).then((r) => {
        if (active && r.status === 200) setCard(r.card ?? null);
      });
    }
    return () => {
      active = false;
    };
  }, [providerId, appt.salonClientId]);

  async function act(fn: () => Promise<{ ok: boolean; error?: string }>) {
    setBusy(true);
    const r = await fn();
    setBusy(false);
    if (r.ok) onChanged();
    else onToast('Action impossible. Réessayez.');
  }

  const services = (appt.serviceIds ?? [])
    .map((id) => serviceName(id) ?? id)
    .join(', ');

  return (
    <div className="fixed inset-y-0 right-0 z-40 flex w-full max-w-sm flex-col border-l border-border bg-secondary shadow-xl">
      <div className="flex items-center justify-between border-b border-border p-m">
        <h2 className="font-semibold text-textPrimary">
          Détails du rendez-vous
        </h2>
        <button
          type="button"
          onClick={onClose}
          aria-label="Fermer"
          className="text-textTertiary"
        >
          ✕
        </button>
      </div>

      <div className="flex-1 space-y-m overflow-auto p-m">
        {/* Client */}
        <div>
          <p className="flex items-center gap-s font-medium text-textPrimary">
            {appt.clientName ?? 'Client'}
            {noShowBadge(appt.clientNoShowCount) !== 'none' ? (
              <span
                className={`rounded-full px-s py-xs text-xs ${
                  noShowBadge(appt.clientNoShowCount) === 'red'
                    ? 'bg-error/10 text-error'
                    : 'bg-surface text-textSecondary'
                }`}
              >
                {noShowLabel(appt.clientNoShowCount ?? 0)}
              </span>
            ) : null}
          </p>
          {appt.clientPhone ? (
            <p className="text-sm text-textSecondary">
              {maskPhone(appt.clientPhone)}
            </p>
          ) : null}

          {card ? (
            <div className="mt-s rounded-lg bg-surface p-s text-xs text-textSecondary">
              <div className="flex justify-between">
                <span>{card.stats.visits} visites</span>
                <span>{formatFcfa(card.stats.spentFcfa)}</span>
                <span>{card.stats.noShows} absences</span>
              </div>
              {card.notes[0] ? (
                <p className="mt-xs truncate text-textTertiary">
                  « {card.notes[0].body} »
                </p>
              ) : null}
              <Link
                href={`/pro/clients/${appt.salonClientId}`}
                className="mt-xs inline-block text-textTertiary underline"
              >
                Voir la fiche
              </Link>
            </div>
          ) : null}
        </div>

        {/* Facts */}
        <dl className="space-y-xs text-sm">
          <Row label="Statut" value={statusLabelFr(key)} />
          <Row label="Date" value={formatDateTimeFr(appt.appointmentDate)} />
          <Row label="Prestations" value={services} />
          {typeof appt.totalPrice === 'number' ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice)} />
          ) : null}
        </dl>
      </div>

      {/* Actions by state */}
      <div className="space-y-s border-t border-border p-m">
        {appt.status === 'pending' ? (
          <div className="flex gap-s">
            <Button
              onClick={() => act(() => proAction(appt.id, 'accept'))}
              disabled={busy}
            >
              Accepter
            </Button>
            <Button
              variant="secondary"
              onClick={() => act(() => proAction(appt.id, 'reject'))}
              disabled={busy}
            >
              Refuser
            </Button>
          </div>
        ) : null}
        {appt.status === 'confirmed' ? (
          <div className="flex flex-wrap gap-s">
            {key !== 'arrived' ? (
              <Button
                onClick={() => act(() => arriveAppointment(appt.id))}
                disabled={busy}
              >
                Client arrivé
              </Button>
            ) : null}
            <Button
              variant="secondary"
              onClick={() => act(() => proAction(appt.id, 'complete'))}
              disabled={busy}
            >
              Terminé
            </Button>
            <Button
              variant="secondary"
              onClick={() => act(() => proAction(appt.id, 'no-show'))}
              disabled={busy}
            >
              Non présenté
            </Button>
          </div>
        ) : null}

        {appt.status === 'pending' || appt.status === 'confirmed' ? (
          !reprog ? (
            <Button
              variant="secondary"
              disabled={busy}
              onClick={() => {
                setReprog(true);
                setReprogDate(appt.appointmentDate.slice(0, 10));
                setReprogTime(appt.appointmentDate.slice(11, 16));
              }}
            >
              Reprogrammer
            </Button>
          ) : (
            <div className="w-full rounded-lg bg-surface p-s">
              <div className="flex flex-wrap gap-xs">
                <input
                  type="date"
                  aria-label="Nouvelle date"
                  value={reprogDate}
                  onChange={(e) => setReprogDate(e.target.value)}
                  className="rounded-lg border border-border bg-secondary px-s py-xs text-sm text-textPrimary"
                />
                <input
                  type="time"
                  aria-label="Nouvelle heure"
                  step={900}
                  value={reprogTime}
                  onChange={(e) => setReprogTime(e.target.value)}
                  className="rounded-lg border border-border bg-secondary px-s py-xs text-sm text-textPrimary"
                />
              </div>
              <div className="mt-s flex gap-s">
                <Button variant="secondary" onClick={() => setReprog(false)}>
                  Annuler
                </Button>
                <Button
                  disabled={busy || !reprogDate || !reprogTime}
                  onClick={() =>
                    act(() =>
                      rescheduleAppointment(
                        appt.id,
                        `${reprogDate}T${reprogTime}:00.000Z`,
                      ),
                    )
                  }
                >
                  OK
                </Button>
              </div>
            </div>
          )
        ) : null}
      </div>
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
