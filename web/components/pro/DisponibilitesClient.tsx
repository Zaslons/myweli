'use client';

import { useRouter } from 'next/navigation';
import { ErrorState } from '../ErrorState';
import { useEffect, useState } from 'react';
import { getMyProvider, saveAvailability } from '../../lib/api/pro';
import { DayHoursEditor } from './DayHoursEditor';
import {
  type Availability,
  type DayForm,
  BUFFER_PRESETS,
  daysToSchedule,
  scheduleToDays,
  toApi,
  toEditable,
  validateHours,
} from '../../lib/pro/availability';
import { formatDateFr } from '../../lib/format';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';

export function DisponibilitesClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [base, setBase] = useState<Availability | null>(null);
  const [days, setDays] = useState<DayForm[]>([]);
  // Audit 3.8: « Pauses » — one recurring break per day (ex. déjeuner);
  // hatches the journal grid and blocks slots.
  const [breakDays, setBreakDays] = useState<DayForm[]>([]);
  const [buffer, setBuffer] = useState(0);
  const [blocked, setBlocked] = useState<string[]>([]);
  const [newDate, setNewDate] = useState('');
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);
  const [loadError, setLoadError] = useState(false);
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
        setLoadError(true);
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
      setBase(a);
      setDays(toEditable(a));
      setBreakDays(scheduleToDays(a?.breaks, { start: '12:30', end: '13:30' }));
      setBuffer(a.bufferMinutes ?? 0);
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

  function patchDay(i: number, patch: Partial<DayForm>) {
    setDays((ds) => ds.map((d, idx) => (idx === i ? { ...d, ...patch } : d)));
    setSaved(false);
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
    });
    const r = await saveAvailability(providerId, { ...obj, breaks });
    setBusy(false);
    if (!r.ok) {
      setError('L’enregistrement a échoué. Réessayez.');
      return;
    }
    setBase(obj);
    setSaved(true);
  }

  if (loading) return <SkeletonRows count={5} className="mt-l" />;
  if (loadError) {
    return <ErrorState title="Disponibilités" onRetry={() => { setLoadError(false); setLoading(true); setReloadKey((k) => k + 1); }} />;
  }

  const inputCls =
    'min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

  return (
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Disponibilités</h1>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Horaires</h2>
        <div className="mt-m space-y-s">
          <DayHoursEditor days={days} onPatch={patchDay} />
        </div>
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
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
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">
          Tampon entre rendez-vous
        </h2>
        <div className="mt-m flex flex-wrap gap-s">
          {BUFFER_PRESETS.map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => {
                setBuffer(m);
                setSaved(false);
              }}
              className={`rounded-lg border px-m py-s text-bodyMedium ${
                buffer === m
                  ? 'border-primary bg-primary text-secondary'
                  : 'border-border bg-surface text-textPrimary'
              }`}
            >
              {m} min
            </button>
          ))}
        </div>
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-titleLarge font-semibold text-textPrimary">Dates bloquées</h2>
        <div className="mt-m flex flex-wrap items-center gap-s">
          <input
            type="date"
            aria-label="Date à bloquer"
            className={inputCls}
            value={newDate}
            onChange={(e) => setNewDate(e.target.value)}
          />
          <Button
            variant="secondary"
            disabled={!newDate || blocked.includes(newDate)}
            onClick={() => {
              setBlocked((b) => [...b, newDate].sort());
              setNewDate('');
              setSaved(false);
            }}
          >
            Bloquer
          </Button>
        </div>
        {blocked.length > 0 ? (
          <ul className="mt-m space-y-xs">
            {blocked.map((date) => (
              <li
                key={date}
                className="flex items-center justify-between gap-m text-bodyMedium"
              >
                <span className="text-textPrimary">
                  {/* Midday anchor: a blocked DATE is a salon-day identifier,
                      stable at any wave offset (multi-pays MP3). */}
                  {formatDateFr(`${date}T12:00:00.000Z`)}
                </span>
                <button
                  type="button"
                  className="text-textTertiary underline"
                  onClick={() => {
                    setBlocked((b) => b.filter((x) => x !== date));
                    setSaved(false);
                  }}
                >
                  Retirer
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-s text-bodyMedium text-textTertiary">Aucune date bloquée.</p>
        )}
      </section>

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
