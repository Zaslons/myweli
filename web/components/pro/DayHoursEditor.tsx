'use client';

import type { DayForm } from '../../lib/pro/availability';

const inputCls =
  'rounded-lg border border-border bg-surface px-s py-xs text-sm text-textPrimary';

/// One weekly-schedule editor for the three places that edit day ranges:
/// salon hours, breaks (« Pauses ») and per-artist hours (audit 3.4/3.8).
/// Renders DayForm rows — checkbox + start/end time inputs.
export function DayHoursEditor({
  days,
  onLabel = 'Ouvert',
  offLabel = 'Fermé',
  onPatch,
}: {
  days: DayForm[];
  onLabel?: string;
  offLabel?: string;
  onPatch: (index: number, patch: Partial<DayForm>) => void;
}) {
  return (
    <div className="space-y-s">
      {days.map((d, i) => (
        <div key={d.key} className="flex flex-wrap items-center gap-m">
          <span className="w-28 text-textPrimary">{d.label}</span>
          <label className="flex items-center gap-s text-sm text-textSecondary">
            <input
              type="checkbox"
              checked={d.open}
              onChange={(e) => onPatch(i, { open: e.target.checked })}
            />
            {onLabel}
          </label>
          {d.open ? (
            <span className="flex items-center gap-s">
              <input
                type="time"
                aria-label={`${d.label} début`}
                className={inputCls}
                value={d.start}
                onChange={(e) => onPatch(i, { start: e.target.value })}
              />
              <span className="text-textTertiary">à</span>
              <input
                type="time"
                aria-label={`${d.label} fin`}
                className={inputCls}
                value={d.end}
                onChange={(e) => onPatch(i, { end: e.target.value })}
              />
            </span>
          ) : (
            <span className="text-sm text-textTertiary">{offLabel}</span>
          )}
        </div>
      ))}
    </div>
  );
}
