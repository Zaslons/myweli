'use client';

import Link from 'next/link';
import { Chip } from '../Chip';
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
import { hhmm, minutesOfDay, statusKey } from '../../lib/pro/journal';
import { combineDateTime } from '../../lib/pro/manual-booking';
import { salonDayKey } from '../../lib/time';
import { type Membership, hasCap } from '../../lib/pro/team';
import type { ProAppointment } from '../../lib/pro/today';
import { Button } from '../Button';

/// The journal side panel (module journal J1 §3.4): booking facts + the C2
/// client mini-card (audited read) + state-aware actions.
export function JournalPanel({
  providerId,
  appt,
  membership,
  serviceName,
  onClose,
  onChanged,
  onToast,
  tz,
  currency,
}: {
  providerId: string;
  appt: ProAppointment;
  /// Team access R5b: gates the whole-journal acts (accept/reject/arrive/
  /// reschedule) and the client-fiche block. UI convenience — the server
  /// enforces T40 regardless.
  membership?: Membership | null;
  serviceName: (id: string) => string | undefined;
  onClose: () => void;
  onChanged: () => void;
  onToast: (msg: string, kind?: 'success' | 'info' | 'error') => void;
  /// The active salon's timezone/currency (multi-pays MP3) — wall-clocks and
  /// money render in the SALON's market, never the viewer's.
  tz?: string;
  currency?: string;
}) {
  const [card, setCard] = useState<SalonClientCard | null>(null);
  const [busy, setBusy] = useState(false);
  // « Reprogrammer » (parity 1.9) — cross-day from the panel too.
  const [reprog, setReprog] = useState(false);
  const [reprogDate, setReprogDate] = useState('');
  const [reprogTime, setReprogTime] = useState('');
  const key = statusKey(appt);
  const canManageAll = hasCap(membership, 'journal.manage.all');
  const canViewClients = hasCap(membership, 'clients.view');

  // C2: the client mini-card (this GET is audited server-side, by design).
  // Skipped without clients.view — the fetch would be a guaranteed 403.
  useEffect(() => {
    let active = true;
    if (appt.salonClientId && canViewClients) {
      getClientCard(providerId, appt.salonClientId).then((r) => {
        if (active && r.status === 200) setCard(r.card ?? null);
      });
    }
    return () => {
      active = false;
    };
  }, [providerId, appt.salonClientId, canViewClients]);

  async function act(fn: () => Promise<{ ok: boolean; error?: string }>) {
    setBusy(true);
    const r = await fn();
    setBusy(false);
    if (r.ok) onChanged();
    else onToast('Action impossible. Réessayez.', 'error');
  }

  const services = (appt.serviceIds ?? [])
    .map((id) => serviceName(id) ?? id)
    .join(', ');

  return (
    <div
      id="pro-journal-panel"
      // The panel is NOT modal — no scrim, doesn't block the page — so it sits
      // at `dropdown`, under the drawer's scrim (`overlay`) and the drawer
      // itself (`modal`). It used to be `z-40`, tying with the drawer and
      // painting over it on a phone (see tests/e2e/z-layers.spec.ts).
      className="fixed inset-y-0 right-0 z-dropdown flex w-full max-w-sm flex-col border-l border-border bg-secondary shadow-xl"
    >
      <div className="flex items-center justify-between border-b border-border p-m">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Détails du rendez-vous
        </h2>
        <button
          type="button"
          onClick={onClose}
          aria-label="Fermer"
          className="-m-m flex min-h-12 min-w-12 items-center justify-center text-iconXS text-textTertiary"
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
              <Chip
                variant={noShowBadge(appt.clientNoShowCount) === 'red' ? 'tinted' : 'neutral'}
                tint="error"
              >
                {noShowLabel(appt.clientNoShowCount ?? 0)}
              </Chip>
            ) : null}
          </p>
          {appt.clientPhone ? (
            <p className="text-bodyMedium text-textSecondary">
              {maskPhone(appt.clientPhone)}
            </p>
          ) : null}

          {card ? (
            <div className="mt-s rounded-lg bg-surface p-s text-bodySmall text-textSecondary">
              <div className="flex justify-between">
                <span>{card.stats.visits} visites</span>
                <span>{formatFcfa(card.stats.spentFcfa, currency)}</span>
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
        <dl className="space-y-xs text-bodyMedium">
          <Row label="Statut" value={statusLabelFr(key)} />
          <Row
            label="Date"
            value={formatDateTimeFr(appt.appointmentDate, tz)}
          />
          <Row label="Prestations" value={services} />
          {typeof appt.totalPrice === 'number' ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice, currency)} />
          ) : null}
        </dl>
      </div>

      {/* Actions by state */}
      <div className="space-y-s border-t border-border p-m">
        {appt.status === 'pending' && canManageAll ? (
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
            {key !== 'arrived' && canManageAll ? (
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

        {(appt.status === 'pending' || appt.status === 'confirmed') &&
        canManageAll ? (
          !reprog ? (
            <Button
              variant="secondary"
              disabled={busy}
              onClick={() => {
                setReprog(true);
                // Prefill with the SALON wall-clock (multi-pays MP3 — the old
                // ISO-prefix reads were the UTC clock face).
                setReprogDate(salonDayKey(new Date(appt.appointmentDate), tz));
                setReprogTime(
                  hhmm(minutesOfDay(appt.appointmentDate, tz)),
                );
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
                  className="min-h-12 rounded-lg border border-borderStrong bg-secondary px-s py-xs text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
                />
                <input
                  type="time"
                  aria-label="Nouvelle heure"
                  step={900}
                  value={reprogTime}
                  onChange={(e) => setReprogTime(e.target.value)}
                  className="min-h-12 rounded-lg border border-borderStrong bg-secondary px-s py-xs text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
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
                        // The picked wall-clock IS salon time — offset-aware
                        // build through the seam (multi-pays MP3).
                        combineDateTime(reprogDate, reprogTime, tz) ?? '',
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
