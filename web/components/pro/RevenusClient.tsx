'use client';

import { useRouter } from 'next/navigation';
import { Card } from '../Card';
import { DataTable } from '../DataTable';
import { ChipButton } from '../Chip';
import { EmptyState } from '../EmptyState';
import { ErrorState } from '../ErrorState';
import { SkeletonRows } from '../Skeleton';
import { useCallback, useEffect, useState } from 'react';
import { getEarnings, getMyProvider } from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import {
  type EarningsData,
  type PeriodKey,
  PERIODS,
  periodRange,
} from '../../lib/pro/earnings';

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
    <div>
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Revenus</h1>
      <p className="mt-xs text-bodyMedium text-textSecondary">
        Vos revenus réalisés (rendez-vous terminés).
      </p>

      {/* Was px-m py-xs with NO 48px floor — a row-7h leak the B4 sweep
          missed; ChipButton carries the floor and §16's borderStrong. */}
      <div className="mt-m flex flex-wrap gap-s">
        {PERIODS.map((p) => (
          <ChipButton
            key={p.key}
            selected={period === p.key}
            onClick={() => pick(p.key)}
          >
            {p.label}
          </ChipButton>
        ))}
      </div>

      {loading ? (
        <SkeletonRows count={5} className="mt-l" />
      ) : error ? (
        <div className="mt-l">
          <ErrorState
            message="Chargement impossible."
            // Retry the PERIOD the user picked — init() hard-codes 'all' and
            // the review watched « Semaine » stay selected over all-time
            // figures after a retry.
            onRetry={() =>
              providerId ? loadPeriod(providerId, period, salonTz) : init()
            }
          />
        </div>
      ) : earnings ? (
        <>
          <Card className="mt-l text-center">
            <p className="text-bodyMedium text-textSecondary">Total</p>
            <p className="mt-xs text-headlineMedium font-semibold text-textPrimary">
              {formatFcfa(earnings.totalEarnings, currency)}
            </p>
          </Card>

          {/* B7: the ledger as a DataTable — Date · Montant (right-aligned).
              The empty state lives inside the table's own four-state contract. */}
          <div className="mt-l">
            <DataTable
              columns={[
                { label: 'Date', flex: 2 },
                { label: 'Montant', flex: 1, align: 'right' },
              ]}
              emptyTitle="Aucune transaction"
              emptyIcon="depositReceived"
              emptyDescription="Les encaissements de la période choisie apparaîtront ici."
              minWidthClassName="min-w-0"
              rows={earnings.transactions.map((t) => ({
                key: t.id,
                cells: [
                  <span key="d" className="text-textPrimary">
                    {formatDateTimeFr(t.date, salonTz)}
                  </span>,
                  <span key="a" className="font-semibold text-textPrimary">
                    {formatFcfa(t.amount, t.currency ?? currency)}
                  </span>,
                ],
              }))}
            />
          </div>
        </>
      ) : null}
    </div>
  );
}
