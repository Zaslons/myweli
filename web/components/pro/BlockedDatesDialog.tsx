'use client';

import { useMemo, useState } from 'react';
import { Button } from '../Button';
import { Modal } from '../Modal';
import { addMonths, anchorKey, monthLabelFr, monthMatrix } from '../../lib/pro/agenda';
import {
  type BlockedChange,
  blockedChange,
  blockedConfirm,
  blockedDayKey,
  blockedPickerSummary,
} from '../../lib/pro/availability';
import { formatDateFr } from '../../lib/format';
import { addSalonDays, salonDayKey, salonToday } from '../../lib/time';

const WEEKDAYS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// How far ahead a day can be blocked — the app's `kBookingHorizon` (a year):
/// blocking is PLANNING, not booking, so not the salon's own window.
const PLANNING_DAYS = 365;

/// A day key's French date (« 25 octobre 2026 ») — midday anchor, so the
/// salon's offset never tips it into the next or previous day.
export function dayLabel(key: string, tz?: string): string {
  return formatDateFr(`${key}T12:00:00.000Z`, tz);
}

const monthAnchor = (key: string) => {
  const [y, m] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, 1));
};

/// « Gérer les dates bloquées » — the app's multi-date picker and its
/// confirmation, in one dialog (docs/design/web-pro-availability-ranges.md
/// §2.2): a month calendar from the salon's today to a year out (the past is
/// not selectable — it stays in the page's list with its own « Débloquer »),
/// the app's live summary, then « Enregistrer » → the confirmation that names
/// the direction → [onSave] (the page writes the DATES only). Closing with
/// changes asks first. The confirmation is a second STEP of this dialog,
/// not a second dialog: the shared Modal is not built to stack.
export function BlockedDatesDialog({
  blocked,
  tz,
  onClose,
  onSave,
}: {
  /// The stored list (both formats — `blockedDayKey` reads them).
  blocked: string[];
  tz?: string;
  onClose: () => void;
  /// Writes [change]; resolves to an error sentence, or null on success.
  onSave: (change: BlockedChange) => Promise<string | null>;
}) {
  const now = useMemo(() => new Date(), []);
  const today = salonToday(now, tz);
  const last = salonDayKey(addSalonDays(now, PLANNING_DAYS, tz), tz);

  // Seeded with the blocked days INSIDE the selectable range only — a past
  // day would paint selected and refuse to toggle (the app's rule).
  const initial = useMemo(() => {
    const keys = blocked
      .map((s) => blockedDayKey(s, tz))
      .filter((k): k is string => k !== null && k >= today && k <= last);
    return new Set(keys);
  }, [blocked, tz, today, last]);

  const [selected, setSelected] = useState<Set<string>>(() => new Set(initial));
  const [month, setMonth] = useState(() => monthAnchor(today));
  const [step, setStep] = useState<'pick' | 'confirm' | 'discard'>('pick');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const change = blockedChange(initial, selected);
  const changed = change.added.length + change.removed.length > 0;
  const summary = blockedPickerSummary(selected.size, change);
  const confirm = blockedConfirm(change, (k) => dayLabel(k, tz));

  function toggle(key: string) {
    setSelected((cur) => {
      const next = new Set(cur);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  // Escape, the scrim and « Annuler » all go through here.
  function requestClose() {
    if (busy) return;
    if (step === 'pick' && changed) setStep('discard');
    else onClose();
  }

  async function save() {
    setBusy(true);
    setError(null);
    const failure = await onSave(change);
    setBusy(false);
    if (failure) setError(failure);
    // Success: the page closes the dialog.
  }

  const firstMonth = monthAnchor(today);
  const lastMonth = monthAnchor(last);
  const weeks = monthMatrix(month);

  return (
    <Modal
      title="Jours bloqués"
      onClose={requestClose}
      panelClassName="w-full max-w-md rounded-xl border border-border bg-secondary p-m sm:p-l"
    >
      {step === 'pick' ? (
        <div className="mt-m">
          <div className="flex items-center justify-between gap-s">
            <Button
              variant="secondary"
              aria-label="Mois précédent"
              disabled={month.getTime() <= firstMonth.getTime()}
              onClick={() => setMonth((m) => addMonths(m, -1))}
            >
              ‹
            </Button>
            <p className="text-labelLarge font-medium capitalize text-textPrimary">
              {monthLabelFr(month, tz)}
            </p>
            <Button
              variant="secondary"
              aria-label="Mois suivant"
              disabled={month.getTime() >= lastMonth.getTime()}
              onClick={() => setMonth((m) => addMonths(m, 1))}
            >
              ›
            </Button>
          </div>
          <div className="mt-s grid grid-cols-7 gap-xs text-center text-bodySmall text-textTertiary" aria-hidden="true">
            {WEEKDAYS.map((d) => (
              <div key={d}>{d}</div>
            ))}
          </div>
          <div className="mt-xs grid grid-cols-7 gap-xs">
            {weeks.flat().map((d) => {
              const key = anchorKey(d);
              // Days of the neighbouring months keep their place, blank (the
              // agenda calendar's rule).
              if (d.getUTCMonth() !== month.getUTCMonth()) {
                return <div key={key} aria-hidden="true" />;
              }
              const isOn = selected.has(key);
              const outside = key < today || key > last;
              return (
                <button
                  key={key}
                  type="button"
                  aria-label={dayLabel(key, tz)}
                  aria-pressed={isOn}
                  disabled={outside}
                  onClick={() => toggle(key)}
                  className={`flex min-h-12 items-center justify-center rounded-lg text-bodyMedium ${
                    isOn ? 'bg-primary text-secondary' : 'text-textPrimary hover:bg-surfaceVariant'
                  } ${key === today && !isOn ? 'ring-1 ring-primary' : ''} disabled:text-textDisabled disabled:hover:bg-transparent`}
                >
                  {d.getUTCDate()}
                </button>
              );
            })}
          </div>
          {/* The cells announce themselves; the COUNT is what « Enregistrer »
              acts on, so it is a live region (the app's Semantics). */}
          <div role="status" aria-live="polite" className="mt-m">
            <p className="text-bodyMedium text-textPrimary">{summary.state}</p>
            {summary.delta ? (
              <p className="mt-xs text-bodySmall text-textSecondary">{summary.delta}</p>
            ) : null}
          </div>
          <div className="mt-m flex flex-wrap justify-end gap-s">
            <Button variant="secondary" onClick={requestClose}>
              Annuler
            </Button>
            <Button disabled={!changed} onClick={() => setStep('confirm')}>
              Enregistrer
            </Button>
          </div>
        </div>
      ) : step === 'confirm' ? (
        <div className="mt-m">
          <p className="text-titleMedium font-semibold text-textPrimary">{confirm.title}</p>
          {confirm.lines.map((line) => (
            <p key={line} className="mt-xs text-bodyMedium text-textSecondary">
              {line}
            </p>
          ))}
          <div className="mt-l flex flex-wrap justify-end gap-s">
            <Button variant="secondary" disabled={busy} onClick={() => setStep('pick')}>
              Retour
            </Button>
            <Button
              isLoading={busy}
              onClick={save}
              // The house's destructive confirm (EquipeClient's revoke):
              // blocking closes the salon's calendar; unblocking does not.
              className={confirm.destructive ? '!bg-error hover:!bg-error' : ''}
            >
              {confirm.confirm}
            </Button>
          </div>
          {error ? (
            <p role="alert" className="mt-s text-bodyMedium text-error">
              {error}
            </p>
          ) : null}
        </div>
      ) : (
        <div className="mt-m">
          <p className="text-titleMedium font-semibold text-textPrimary">
            Abandonner les modifications ?
          </p>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Les dates que vous venez de choisir ne seront pas enregistrées.
          </p>
          <div className="mt-l flex flex-wrap justify-end gap-s">
            <Button variant="secondary" onClick={() => setStep('pick')}>
              Continuer
            </Button>
            <Button onClick={onClose}>Abandonner</Button>
          </div>
        </div>
      )}
    </Modal>
  );
}
