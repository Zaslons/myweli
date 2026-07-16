'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { getEarnings, getMyProvider } from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import {
  type EarningsData,
  type PeriodKey,
  PERIODS,
  periodRange,
} from '../../lib/pro/earnings';
import { Button } from '../Button';

/// « Revenus » (parity 9.1 — the app's earnings_screen, web-adapted): period
/// tabs → realized total (completed bookings only) → transaction ledger.
/// Design: docs/design/web-notifications-revenus.md.
export function RevenusClient() {
  const router = useRouter();
  const [providerId, setProviderId] = useState<string | null>(null);
  // The ACTIVE salon's market (multi-pays MP3): its timezone shapes the
  // period boundaries; its currency labels the ledger (earnings.currency is
  // the backend-stamped authority, this is the fallback).
  const [salonTz, setSalonTz] = useState<string | undefined>(undefined);
  const [salonCurrency, setSalonCurrency] = useState<string | undefined>(
    undefined,
  );
  const [period, setPeriod] = useState<PeriodKey>('all');
  const [earnings, setEarnings] = useState<EarningsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const loadPeriod = useCallback(
    async (pid: string, key: PeriodKey, tz?: string) => {
      setLoading(true);
      setError(false);
      const r = await getEarnings(pid, periodRange(key, new Date(), tz));
      if (r.status !== 200 || !r.earnings) {
        setError(true);
        setLoading(false);
        return;
      }
      setEarnings(r.earnings);
      setLoading(false);
    },
    [],
  );

  const init = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(true);
      setLoading(false);
      return;
    }
    const pid = me.profile.provider.id;
    const tz = me.profile.provider.timezone ?? undefined;
    setProviderId(pid);
    setSalonTz(tz);
    setSalonCurrency(me.profile.provider.currency ?? undefined);
    await loadPeriod(pid, 'all', tz);
  }, [router, loadPeriod]);

  useEffect(() => {
    init();
  }, [init]);

  function pick(key: PeriodKey) {
    setPeriod(key);
    if (providerId) loadPeriod(providerId, key, salonTz);
  }

  const currency = earnings?.currency ?? salonCurrency;

  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-semibold text-textPrimary">Revenus</h1>
      <p className="mt-xs text-sm text-textSecondary">
        Vos revenus réalisés (rendez-vous terminés).
      </p>

      <div className="mt-m flex flex-wrap gap-s">
        {PERIODS.map((p) => (
          <button
            key={p.key}
            type="button"
            onClick={() => pick(p.key)}
            className={`rounded-pill border px-m py-xs text-sm ${
              period === p.key
                ? 'border-primary bg-primary text-secondary'
                : 'border-border bg-secondary text-textPrimary'
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="mt-l text-textSecondary">Chargement…</p>
      ) : error ? (
        <div className="mt-l">
          <p className="text-error">Chargement impossible.</p>
          <div className="mt-s">
            <Button variant="secondary" onClick={init}>
              Réessayer
            </Button>
          </div>
        </div>
      ) : earnings ? (
        <>
          <div className="mt-l rounded-xl border border-border bg-secondary p-l text-center">
            <p className="text-sm text-textSecondary">Total</p>
            <p className="mt-xs text-3xl font-semibold text-textPrimary">
              {formatFcfa(earnings.totalEarnings, currency)}
            </p>
          </div>

          {earnings.transactions.length === 0 ? (
            <p className="mt-l rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
              Aucune transaction sur cette période.
            </p>
          ) : (
            <ul className="mt-l space-y-s">
              {earnings.transactions.map((t) => (
                <li
                  key={t.id}
                  className="flex items-center justify-between gap-m rounded-xl border border-border bg-secondary p-m"
                >
                  <span className="text-sm text-textPrimary">
                    {formatDateTimeFr(t.date, salonTz)}
                  </span>
                  <span className="text-sm font-semibold text-textPrimary">
                    {formatFcfa(t.amount, t.currency ?? currency)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </>
      ) : null}
    </div>
  );
}
