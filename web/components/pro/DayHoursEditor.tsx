'use client';

import type { DayForm } from '../../lib/pro/availability';

const inputCls =
  'min-h-12 rounded-lg border border-borderStrong bg-surface px-s py-xs text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';

/// One weekly-schedule editor for the three places that edit day ranges:
/// salon hours, breaks (« Pauses ») and per-artist hours (audit 3.4/3.8).
/// Renders DayForm rows — checkbox + start/end time inputs.
export function DayHoursEditor({
  days,
  onLabel = 'Ouvert',
  offLabel = 'Fermé',
  onPatch,
  onCopyToAll,
}: {
  days: DayForm[];
  onLabel?: string;
  offLabel?: string;
  onPatch: (index: number, patch: Partial<DayForm>) => void;
  /// « Copier sur les autres jours » on each OPEN row — provided by the call
  /// sites whose mobile twin has the gesture (salon hours, artist hours);
  /// absent on breaks (parity: the app has no copy there).
  onCopyToAll?: (index: number) => void;
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
            // B11: two `type="time"` inputs and « à » in a row that could not
            // wrap. Measured 332px of the 291 available at 320 — **on CI, not
            // locally**: a UA time input's intrinsic width is font- and
            // platform-dependent, and Linux renders it wider than macOS, so the
            // local suite reported green on a page that scrolls sideways. The
            // parent row already wraps; this one now does too.
            //
            // (A `//` comment, not `{/* */}` — inside a ternary's parentheses
            // this is an expression position and a JSX comment is a syntax
            // error. Third time in this slice.)
            <span className="flex flex-wrap items-center gap-s">
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
              {onCopyToAll ? (
                // A visible-name control per open row; the accessible name
                // carries the day so seven of them stay distinguishable.
                <button
                  type="button"
                  aria-label={`Copier ${d.label} sur les autres jours`}
                  className="min-h-12 text-bodyMedium text-textTertiary underline"
                  onClick={() => onCopyToAll(i)}
                >
                  Copier sur les autres jours
                </button>
              ) : null}
            </span>
          ) : (
            <span className="text-bodyMedium text-textTertiary">{offLabel}</span>
          )}
        </div>
      ))}
    </div>
  );
}
