'use client';

import { type DayRanges, type Range, nextRange, openDay } from '../../lib/pro/availability';

const inputCls =
  'min-h-12 rounded-lg border border-borderStrong bg-surface px-s py-xs text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus disabled:border-border disabled:text-textDisabled';
const linkBtn = 'min-h-12 text-bodyMedium text-textTertiary underline disabled:no-underline disabled:opacity-50';

/// The salon's opening hours, EVERY range of each day
/// (docs/design/web-pro-availability-ranges.md §2.1) — the app's day editor,
/// laid out as one row per day on the desktop page: « Ouvert », then each
/// range « début à fin · Retirer », then « Ajouter une plage » and « Copier
/// sur les autres jours ». The breaks and the per-artist hours stay one range
/// a day (`DayHoursEditor`), as they are in the app.
export function WeekRangesEditor({
  days,
  onChange,
  onCopyToAll,
}: {
  days: DayRanges[];
  onChange: (index: number, day: DayRanges) => void;
  onCopyToAll: (index: number) => void;
}) {
  return (
    <div className="space-y-m">
      {days.map((d, i) => {
        const day = d.label.toLowerCase();
        const several = d.ranges.length > 1;
        // « Lundi début » for a single range (unchanged names); with several,
        // each says which — « Lundi, plage 2, début ».
        const name = (j: number, end: 'début' | 'fin') =>
          several ? `${d.label}, plage ${j + 1}, ${end}` : `${d.label} ${end}`;
        const setRange = (j: number, patch: Partial<Range>) =>
          onChange(i, {
            ...d,
            ranges: d.ranges.map((r, k) => (k === j ? { ...r, ...patch } : r)),
          });
        const next = nextRange(d.ranges);
        return (
          <div key={d.key} className="flex flex-wrap items-start gap-m">
            <span className="flex min-h-12 w-28 items-center text-textPrimary">{d.label}</span>
            <label className="flex min-h-12 cursor-pointer items-center gap-s text-bodyMedium text-textSecondary">
              <input
                type="checkbox"
                className="h-5 w-5 shrink-0 accent-primary"
                checked={d.open}
                onChange={(e) => onChange(i, e.target.checked ? openDay(d) : { ...d, open: false })}
              />
              Ouvert
            </label>
            {d.open ? (
              <div className="flex flex-col gap-xs">
                {d.ranges.map((r, j) => (
                  // Wraps: two time inputs and « à » measured wider than a
                  // 320px row on CI (B11, DayHoursEditor).
                  <span key={j} className="flex flex-wrap items-center gap-s">
                    <input
                      type="time"
                      aria-label={name(j, 'début')}
                      className={inputCls}
                      value={r.start}
                      onChange={(e) => setRange(j, { start: e.target.value })}
                    />
                    <span className="text-textTertiary">à</span>
                    <input
                      type="time"
                      aria-label={name(j, 'fin')}
                      className={inputCls}
                      value={r.end}
                      onChange={(e) => setRange(j, { end: e.target.value })}
                    />
                    <button
                      type="button"
                      aria-label={`Retirer la plage ${j + 1} du ${day}`}
                      className={linkBtn}
                      // The last range out closes the day — never an open day
                      // with no hours.
                      onClick={() =>
                        onChange(
                          i,
                          d.ranges.length === 1
                            ? { ...d, open: false, ranges: [] }
                            : { ...d, ranges: d.ranges.filter((_, k) => k !== j) },
                        )
                      }
                    >
                      Retirer
                    </button>
                  </span>
                ))}
                <span className="flex flex-wrap items-center gap-m">
                  <button
                    type="button"
                    aria-label={`Ajouter une plage le ${day}`}
                    className={linkBtn}
                    disabled={next === null}
                    onClick={() => next && onChange(i, { ...d, ranges: [...d.ranges, next] })}
                  >
                    Ajouter une plage
                  </button>
                  <button
                    type="button"
                    aria-label={`Copier ${d.label} sur les autres jours`}
                    className={linkBtn}
                    onClick={() => onCopyToAll(i)}
                  >
                    Copier sur les autres jours
                  </button>
                </span>
              </div>
            ) : (
              <span className="flex min-h-12 items-center text-bodyMedium text-textTertiary">Fermé</span>
            )}
          </div>
        );
      })}
    </div>
  );
}
