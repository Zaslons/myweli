'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { getMyProvider, saveAvailability } from '../../lib/api/pro';
import {
  type Availability,
  type DayForm,
  BUFFER_PRESETS,
  toApi,
  toEditable,
  validateHours,
} from '../../lib/pro/availability';
import { formatDateFr } from '../../lib/format';
import { Button } from '../Button';

export function DisponibilitesClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState('');
  const [base, setBase] = useState<Availability | null>(null);
  const [days, setDays] = useState<DayForm[]>([]);
  const [buffer, setBuffer] = useState(0);
  const [blocked, setBlocked] = useState<string[]>([]);
  const [newDate, setNewDate] = useState('');
  const [loading, setLoading] = useState(true);
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
      setBuffer(a.bufferMinutes ?? 0);
      setBlocked(a.blockedDates ?? []);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [router]);

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
    const obj = toApi(days, {
      ...(base as Availability),
      bufferMinutes: buffer,
      blockedDates: blocked,
    });
    const r = await saveAvailability(providerId, obj);
    setBusy(false);
    if (!r.ok) {
      setError('L’enregistrement a échoué. Réessayez.');
      return;
    }
    setBase(obj);
    setSaved(true);
  }

  if (loading) return <p className="text-textSecondary">Chargement…</p>;
  if (loadError) {
    return <p className="text-error">Une erreur est survenue. Réessayez.</p>;
  }

  const inputCls =
    'rounded-lg border border-border bg-surface px-m py-s text-textPrimary';

  return (
    <div>
      <h1 className="text-2xl font-semibold text-textPrimary">Disponibilités</h1>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">Horaires</h2>
        <div className="mt-m space-y-s">
          {days.map((d, i) => (
            <div key={d.key} className="flex flex-wrap items-center gap-m">
              <span className="w-28 text-textPrimary">{d.label}</span>
              <label className="flex items-center gap-s text-sm text-textSecondary">
                <input
                  type="checkbox"
                  checked={d.open}
                  onChange={(e) => patchDay(i, { open: e.target.checked })}
                />
                Ouvert
              </label>
              {d.open ? (
                <span className="flex items-center gap-s">
                  <input
                    type="time"
                    aria-label={`${d.label} début`}
                    className={inputCls}
                    value={d.start}
                    onChange={(e) => patchDay(i, { start: e.target.value })}
                  />
                  <span className="text-textTertiary">à</span>
                  <input
                    type="time"
                    aria-label={`${d.label} fin`}
                    className={inputCls}
                    value={d.end}
                    onChange={(e) => patchDay(i, { end: e.target.value })}
                  />
                </span>
              ) : (
                <span className="text-sm text-textTertiary">Fermé</span>
              )}
            </div>
          ))}
        </div>
      </section>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <h2 className="text-lg font-semibold text-textPrimary">
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
              className={`rounded-lg border px-m py-s text-sm ${
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
        <h2 className="text-lg font-semibold text-textPrimary">Dates bloquées</h2>
        <div className="mt-m flex flex-wrap items-center gap-s">
          <input
            type="date"
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
                className="flex items-center justify-between gap-m text-sm"
              >
                <span className="text-textPrimary">{formatDateFr(date)}</span>
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
          <p className="mt-s text-sm text-textTertiary">Aucune date bloquée.</p>
        )}
      </section>

      {error ? <p className="mt-m text-sm text-error">{error}</p> : null}
      {saved ? (
        <p className="mt-m text-sm text-textSecondary">
          Disponibilités enregistrées.
        </p>
      ) : null}

      <div className="mt-l">
        <Button disabled={busy} onClick={save}>
          Enregistrer
        </Button>
      </div>
    </div>
  );
}
