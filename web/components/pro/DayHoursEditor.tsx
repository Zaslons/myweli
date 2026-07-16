'use client';

import type { DayForm } from '../../lib/pro/availability';

const inputCls =
  'min-h-12 rounded-lg border border-borderStrong bg-surface px-s py-xs text-bodyMedium text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

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
          <label className="flex min-h-12 cursor-pointer items-center gap-s text-bodyMedium text-textSecondary">
            <input
              type="checkbox"
              className="h-5 w-5 shrink-0 accent-primary"
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
            <span className="text-bodyMedium text-textTertiary">{offLabel}</span>
          )}
        </div>
      ))}
    </div>
  );
}
