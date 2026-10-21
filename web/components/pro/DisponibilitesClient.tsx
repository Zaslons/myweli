'use client';

import { useRouter } from 'next/navigation';
import { Card } from '../Card';
import { ErrorState } from '../ErrorState';
import { useEffect, useState } from 'react';
import { getMyProvider, saveAvailability } from '../../lib/api/pro';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { DayHoursEditor } from './DayHoursEditor';
import { BlockedDatesDialog, dayLabel } from './BlockedDatesDialog';
import { WeekRangesEditor } from './WeekRangesEditor';
import { Modal } from '../Modal';
import { writeFailureMessage } from '../../lib/api/network';
import {
  type Availability,
  type BlockedChange,
  type DayForm,
  type DayRanges,
  applyBlockedChange,
  blockedConfirm,
  blockedDayKey,
  blockedSavedSummary,
  BUFFER_PRESETS,
  CRENEAUX_COPY,
  HORIZON_PRESETS,
  NOTICE_PRESETS,
  SCHEDULE_PRESETS,
  applyPreset,
  copyDayToAll,
  horizonLabel,
  noticeLabel,
  daysToSchedule,
  presetMatches,
  scheduleToDays,
  toApi,
  toEditable,
  validateHours,
} from '../../lib/pro/availability';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';
import { ChipButton } from '../Chip';
import {
  DEFAULT_HORIZON_DAYS,
  DEFAULT_NOTICE_MINUTES,
} from '../../lib/booking/window';

export function DisponibilitesClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [base, setBase] = useState<Availability | null>(null);
  const [days, setDays] = useState<DayRanges[]>([]);
  const [tz, setTz] = useState<string | undefined>(undefined);
  // Audit 3.8: « Pauses » — one recurring break per day (ex. déjeuner);
  // hatches the journal grid and blocks slots.
  const [breakDays, setBreakDays] = useState<DayForm[]>([]);
  const [buffer, setBuffer] = useState(0);
  // A14d — the bookable window, both ends. Defaults mirror the server's.
  const [horizon, setHorizon] = useState(DEFAULT_HORIZON_DAYS);
  const [notice, setNotice] = useState(DEFAULT_NOTICE_MINUTES);
  const [blocked, setBlocked] = useState<string[]>([]);
  // The blocked dates write ON THEIR OWN (the app's flow, §2.2): the dialog,
  // the per-row « Débloquer » and its confirm, and the line after a write.
  const [datesOpen, setDatesOpen] = useState(false);
  const [unblock, setUnblock] = useState<string | null>(null);
  const [unblockError, setUnblockError] = useState<string | null>(null);
  const [unblockBusy, setUnblockBusy] = useState(false);
  const [datesStatus, setDatesStatus] = useState('');
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState<LoadFailure | false>(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const me = await getMyProvider();
      if (me.status === 401) {
        router.replace('/pro/connexion');
        return;
      }
      if (!active) return;
      if (me.status !== 200 || !me.profile) {
        setLoadError(loadFailure(me.status));
        setLoading(false);
        return;
      }
      const a: Availability =
        me.profile.provider.availability ?? {
          providerId: me.profile.provider.id,
          weeklySchedule: {},
          blockedDates: [],
          bufferMinutes: 0,
        };
      setProviderId(me.profile.provider.id);
      setTz(me.profile.provider.timezone ?? undefined);
      setBase(a);
      setDays(toEditable(a));
      setBreakDays(scheduleToDays(a?.breaks, { start: '12:30', end: '13:30' }));
      setBuffer(a.bufferMinutes ?? 0);
    setHorizon(a.bookingHorizonDays ?? DEFAULT_HORIZON_DAYS);
    setNotice(a.minimumNoticeMinutes ?? DEFAULT_NOTICE_MINUTES);
      setBlocked(a.blockedDates ?? []);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router, reloadKey]);

  function patchBreak(i: number, patch: Partial<DayForm>) {
    setBreakDays((d) => d.map((x, j) => (j === i ? { ...x, ...patch } : x)));
    setSaved(false);
  }

  function setDay(i: number, day: DayRanges) {
    setDays((ds) => ds.map((d, idx) => (idx === i ? day : d)));
    setSaved(false);
  }

  /// Writes the DATES only (§2.2): from the last SAVED document — hours,
  /// breaks, window, buffer as the server has them — so a staged hours edit is
  /// neither written nor lost; it still waits for « Enregistrer ». Resolves to
  /// an error sentence, or null.
  async function writeBlocked(change: BlockedChange): Promise<string | null> {
    if (!base) return 'L’enregistrement a échoué. Réessayez.';
    const next: Availability = {
      ...base,
      blockedDates: applyBlockedChange(base.blockedDates ?? [], change, tz),
    };
    const r = await saveAvailability(providerId, next);
    if (!r.ok) return writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.');
    setBase(next);
    setBlocked(next.blockedDates);
    setDatesStatus(blockedSavedSummary(change));
    return null;
  }

  async function confirmUnblock() {
    if (!unblock) return;
    setUnblockBusy(true);
    setUnblockError(null);
    const failure = await writeBlocked({ added: [], removed: [unblock] });
    setUnblockBusy(false);
    if (failure) setUnblockError(failure);
    else setUnblock(null);
  }

  async function save() {
    const v = validateHours(days);
    if (v) {
      setError(v);
      return;
    }
    setBusy(true);
    setError(null);
    const breaks = daysToSchedule(breakDays, (base as Availability)?.breaks);
    const obj = toApi(days, {
      ...(base as Availability),
      bufferMinutes: buffer,
      blockedDates: blocked,
      bookingHorizonDays: horizon,
      minimumNoticeMinutes: notice,
      // A14d fixes a live staleness bug here. `breaks` used to be merged into
      // the REQUEST only (`{ ...obj, breaks }`) while `setBase(obj)` below
      // stored the object without it — so `base.breaks` held the pre-save value
      // and the next save recomputed from one generation behind. Any field
      // added that way inherits it; the window rides inside the object instead,
      // and `breaks` now does too.
      breaks,
    });
    const r = await saveAvailability(providerId, obj);
    setBusy(false);
    if (!r.ok) {
      setError(writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'));
      return;
    }
    setBase(obj);
    setSaved(true);
  }

  if (loading) return <SkeletonRows count={5} className="mt-l" />;
  if (loadError) {
    return <ErrorState title="Disponibilités" message={loadFailureMessage(loadError)} onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  const inputCls =
    'min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Disponibilités</h1>

      <Card as="section" className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Horaires</h2>
        {/* The one card of five without an explanatory line — and the
            derived-créneaux question is the one salons actually ask
            (availability-presets.md §2). Same French as the app, pinned. */}
        <p className="mt-xs text-bodySmall text-textSecondary">
          {CRENEAUX_COPY}
        </p>
        {/* H5 — the way to the second range, where the pro looks for it. */}
        <p className="mt-xs text-bodySmall text-textSecondary">
          Fermé à midi ? Ajoutez une deuxième plage.
        </p>
        <p className="mt-m text-bodySmall text-textPrimary">Modèles</p>
        <div className="mt-xs flex flex-wrap gap-s">
          {SCHEDULE_PRESETS.map((p) => (
            <ChipButton
              key={p.label}
              selected={presetMatches(days, p)}
              onClick={() => {
                setDays((d) => applyPreset(d, p));
                setSaved(false);
              }}
            >
              {p.label}
            </ChipButton>
          ))}
        </div>
        <div className="mt-m space-y-s">
          <WeekRangesEditor
            days={days}
            onChange={setDay}
            onCopyToAll={(i) => {
              setDays((d) => copyDayToAll(d, i));
              setSaved(false);
            }}
          />
        </div>
      </Card>

      <Card as="section" className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Pauses</h2>
        <p className="mt-xs text-bodyMedium text-textSecondary">
          Une pause récurrente par jour (ex. déjeuner). Elle bloque les
          créneaux et apparaît hachurée dans la journée.
        </p>
        <div className="mt-m">
          <DayHoursEditor
            days={breakDays}
            onLabel="Pause"
            offLabel="Aucune"
            onPatch={patchBreak}
          />
        </div>
      </Card>

      <Card as="section" className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Fenêtre de réservation
        </h2>
        <p className="mt-xs text-bodySmall text-textSecondary">
          Jusqu’où vos clients peuvent réserver à l’avance, et le délai minimum
          avant un rendez-vous. Vos propres réservations ne sont pas concernées.
        </p>
        <p className="mt-m text-bodySmall text-textPrimary">
          Réservations jusqu’à
        </p>
        <div className="mt-xs flex flex-wrap gap-s">
          {HORIZON_PRESETS.map((d) => (
            <ChipButton
              key={d}
              selected={horizon === d}
              onClick={() => {
                setHorizon(d);
                setSaved(false);
              }}
            >
              {horizonLabel(d)}
            </ChipButton>
          ))}
        </div>
        <p className="mt-m text-bodySmall text-textPrimary">Délai minimum</p>
        <div className="mt-xs flex flex-wrap gap-s">
          {NOTICE_PRESETS.map((m) => (
            <ChipButton
              key={m}
              selected={notice === m}
              onClick={() => {
                setNotice(m);
                setSaved(false);
              }}
            >
              {noticeLabel(m)}
            </ChipButton>
          ))}
        </div>
      </Card>

      <Card as="section" className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Tampon entre rendez-vous
        </h2>
        {/* B9's adversarial review found this: a five-item, mutually-exclusive
            selection row — the same control family as the tab strips — at
            **38px**, ten under §13.2's floor, on a route B9's own overflow
            matrix now visits. It escaped the class-string sweep only because it
            already wraps, which is why row 7h's "0 remaining" was wrong a fifth
            time. `ChipButton` is the primitive for exactly this (its docstring:
            "an INTERACTIVE chip: selection, filter, toggle"), it carries the
            floor, and `RevenusClient.tsx:95` already uses it in this identical
            `flex flex-wrap gap-s` shape. The hand-rolled version also used
            `border-border` where §16 requires `borderStrong` on an outlined
            chip. */}
        <div className="mt-m flex flex-wrap gap-s">
          {BUFFER_PRESETS.map((m) => (
            <ChipButton
              key={m}
              selected={buffer === m}
              onClick={() => {
                setBuffer(m);
                setSaved(false);
              }}
            >
              {m} min
            </ChipButton>
          ))}
        </div>
      </Card>

      <Card as="section" className="mt-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Dates bloquées</h2>
        {blocked.length > 0 ? (
          <ul className="mt-m space-y-xs">
            {[...blocked]
              .map((stored) => ({ stored, key: blockedDayKey(stored, tz) }))
              .sort((a, b) => (a.key ?? a.stored).localeCompare(b.key ?? b.stored))
              .map(({ stored, key }) => {
                // An unreadable entry is shown as stored, never thrown on —
                // the app's format used to crash this list (§1.3).
                const label = key ? dayLabel(key, tz) : stored;
                return (
                  <li key={stored} className="flex items-center justify-between gap-m text-bodyMedium">
                    <span className="text-textPrimary">{label}</span>
                    {key ? (
                      <button
                        type="button"
                        aria-label={`Débloquer le ${label}`}
                        className="min-h-12 text-textTertiary underline"
                        onClick={() => {
                          setUnblockError(null);
                          setUnblock(key);
                        }}
                      >
                        Débloquer
                      </button>
                    ) : null}
                  </li>
                );
              })}
          </ul>
        ) : (
          <p className="mt-s text-bodyMedium text-textTertiary">Aucune date bloquée.</p>
        )}
        <div className="mt-m">
          <Button variant="secondary" onClick={() => setDatesOpen(true)}>
            Gérer les dates bloquées
          </Button>
        </div>
        {/* The app's snackbar after a write, as a persistent status line. */}
        <p role="status" className={datesStatus ? 'mt-s text-bodyMedium text-textSecondary' : 'sr-only'}>
          {datesStatus}
        </p>
      </Card>

      {datesOpen ? (
        <BlockedDatesDialog
          blocked={blocked}
          tz={tz}
          onClose={() => setDatesOpen(false)}
          onSave={async (change) => {
            const failure = await writeBlocked(change);
            if (!failure) setDatesOpen(false);
            return failure;
          }}
        />
      ) : null}

      {unblock ? (
        (() => {
          const c = blockedConfirm({ added: [], removed: [unblock] }, (k) => dayLabel(k, tz));
          return (
            <Modal title={c.title} onClose={() => !unblockBusy && setUnblock(null)}>
              <p className="mt-s text-bodyMedium text-textSecondary">{c.lines[0]}</p>
              <div className="mt-l flex flex-wrap justify-end gap-s">
                <Button variant="secondary" disabled={unblockBusy} onClick={() => setUnblock(null)}>
                  Annuler
                </Button>
                <Button isLoading={unblockBusy} onClick={confirmUnblock}>
                  {c.confirm}
                </Button>
              </div>
              {unblockError ? (
                <p role="alert" className="mt-s text-bodyMedium text-error">
                  {unblockError}
                </p>
              ) : null}
            </Modal>
          );
        })()
      ) : null}

      {error ? <p role="alert" className="mt-m text-bodyMedium text-error">{error}</p> : null}
      <p
        role="status"
        className={saved ? 'mt-m text-bodyMedium text-textSecondary' : 'sr-only'}
      >
        {saved ? 'Disponibilités enregistrées.' : ''}
      </p>

      <div className="mt-l">
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </div>
    </div>
  );
}
