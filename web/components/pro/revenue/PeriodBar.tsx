'use client';

import { useId } from 'react';
import { ChipButton } from '../../Chip';
import {
  type RevenueAnalytics,
  type RevenueCompare,
  type RevenuePeriod,
  type RevenueQuery,
  nextRevenuePeriod,
  previousRevenuePeriod,
  provisionalRevenueTitle,
  revenueComparisonLabel,
  revenuePeriodTitle,
} from '../../../lib/pro/revenue';
import { revenueCompareName } from '../../../lib/pro/revenue-wording';

const KINDS: { key: Exclude<RevenuePeriod, 'custom'>; label: string }[] = [
  { key: 'day', label: 'Jour' },
  { key: 'week', label: 'Semaine' },
  { key: 'month', label: 'Mois' },
  { key: 'year', label: 'Année' },
];

/// The period bar (docs/design/pro-revenue-analytics.md §4.3, §5.1): the
/// five chips (they wrap — every choice in sight, §21.1 item 2), ‹ the
/// period ›, and « Comparer à » as a labelled native `<select>` with the
/// resolved dates under it. ‹ › need the answer (the server owns the
/// calendar): while a period loads they wait.
export function PeriodBar({
  query,
  analytics,
  today,
  onPeriod,
  onCustom,
  onStep,
  onCompare,
}: {
  query: RevenueQuery;
  /// The answer to [query], or null while it loads.
  analytics: RevenueAnalytics | null;
  /// The salon's today (the last answer's, or the device's before the
  /// first) — the provisional title only.
  today: string;
  onPeriod: (period: Exclude<RevenuePeriod, 'custom'>) => void;
  onCustom: () => void;
  onStep: (q: RevenueQuery) => void;
  onCompare: (mode: RevenueCompare) => void;
}) {
  const compareId = useId();
  const a = analytics;
  const title = a ? revenuePeriodTitle(a) : provisionalRevenueTitle(query, today);
  const previous = a ? previousRevenuePeriod(a, query) : null;
  const next = a ? nextRevenuePeriod(a, query) : null;
  const compared =
    query.compare === 'none' ? null : a ? revenueComparisonLabel(a) : null;

  return (
    <div className="space-y-m">
      <div role="group" aria-label="Période" className="flex flex-wrap gap-s">
        {KINDS.map((k) => (
          <ChipButton
            key={k.key}
            selected={query.period === k.key}
            aria-pressed={query.period === k.key}
            onClick={() => {
              if (query.period !== k.key) onPeriod(k.key);
            }}
          >
            {k.label}
          </ChipButton>
        ))}
        <ChipButton
          selected={query.period === 'custom'}
          aria-pressed={query.period === 'custom'}
          aria-haspopup="dialog"
          onClick={onCustom}
        >
          Dates…
        </ChipButton>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-m">
        <div className="flex min-w-0 items-center gap-s">
          <button
            type="button"
            aria-label="Période précédente"
            title="Période précédente"
            disabled={previous == null}
            onClick={() => previous && onStep(previous)}
            className="flex min-h-12 min-w-12 items-center justify-center rounded-control text-iconM text-textPrimary hover:bg-surfaceVariant disabled:text-textDisabled disabled:hover:bg-transparent"
          >
            <span aria-hidden="true">‹</span>
          </button>
          <div className="min-w-0">
            {/* The period is a heading, and its change is announced (§12.3). */}
            <h2
              aria-live="polite"
              className="text-titleLarge font-semibold text-textPrimary"
            >
              {title ?? ''}
            </h2>
            {a?.inProgress ? (
              <p className="text-bodySmall text-textTertiary">(en cours)</p>
            ) : null}
          </div>
          <button
            type="button"
            aria-label="Période suivante"
            title="Période suivante"
            disabled={next == null}
            onClick={() => next && onStep(next)}
            className="flex min-h-12 min-w-12 items-center justify-center rounded-control text-iconM text-textPrimary hover:bg-surfaceVariant disabled:text-textDisabled disabled:hover:bg-transparent"
          >
            <span aria-hidden="true">›</span>
          </button>
        </div>

        <div className="min-w-0">
          <label htmlFor={compareId} className="block text-labelMedium text-textSecondary">
            Comparer à
          </label>
          <select
            id={compareId}
            value={query.compare}
            onChange={(e) => onCompare(e.target.value as RevenueCompare)}
            className="mt-xs block min-h-12 rounded-control border border-primary bg-surface px-m text-bodyMedium text-textPrimary"
          >
            {(['previous', 'year', 'none'] as const).map((m) => (
              <option key={m} value={m}>
                {revenueCompareName(m)}
              </option>
            ))}
          </select>
          {compared ? (
            <p className="mt-xs text-bodySmall text-textTertiary">Comparé à : {compared}</p>
          ) : null}
        </div>
      </div>
    </div>
  );
}
