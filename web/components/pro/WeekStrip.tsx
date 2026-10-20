'use client';

import { dateKey } from '../../lib/pro/agenda';
import type { JournalDay } from '../../lib/pro/journal';
import type { ProAppointment } from '../../lib/pro/today';
import {
  loadDotClass,
  weekCounts,
  weekOf,
  weekStripDay,
  weekStripLabel,
} from '../../lib/pro/week-strip';

/// The week above the Journée (docs/design/web-pro-week-strip.md) — the app's
/// `_WeekStrip`: Monday → Sunday of the shown day, a dot that grows with each
/// day's load, a click shows that day. It follows the shown day, so ‹ › across
/// a Monday change the week; no request of its own.
export function WeekStrip({
  shown,
  items,
  loaded,
  tz,
  onSelect,
}: {
  /// The Journée's salon day (AAAA-MM-JJ).
  shown: string;
  /// The salon's bookings, as the page read them.
  items: ProAppointment[];
  /// The journal day on screen — fresher than [items] for its own date.
  loaded: JournalDay | null;
  tz?: string;
  onSelect: (key: string) => void;
}) {
  const week = weekOf(shown);
  const counts = weekCounts(items, week, tz, loaded);
  const today = dateKey(new Date(), tz);

  return (
    // The seven share the width with no gap — the app's `Expanded` slots. That
    // alone measured 46.7px at 375 (the shell's 24px padding leaves 327), so
    // the strip reaches 8px into that padding each side: the TARGETS grow,
    // the pills stay where they were (§13.2) — 49px at 375 (tap-targets.spec).
    <div
      role="group"
      aria-label={weekStripLabel(week, tz)}
      className="-mx-s mt-m grid grid-cols-7"
    >
      {week.map((key) => {
        const isShown = key === shown;
        const isToday = key === today;
        const { short, day, rest } = weekStripDay(key, counts[key], isToday, tz);
        const dot = loadDotClass(counts[key]);
        return (
          <button
            key={key}
            type="button"
            aria-pressed={isShown}
            onClick={() => onSelect(key)}
            className="flex min-h-12 min-w-0 flex-col items-center gap-xs rounded-lg py-xs hover:bg-surfaceVariant"
          >
            <span className="text-labelSmall text-textTertiary">{short}</span>{' '}
            {/* The Calendrier's marks: the shown day filled, today ringed. */}
            <span
              className={`flex min-h-8 min-w-8 items-center justify-center rounded-pill px-xs text-bodyMedium ${
                isShown
                  ? 'bg-primary text-secondary'
                  : `text-textPrimary ${isToday ? 'ring-1 ring-primary' : ''}`
              }`}
            >
              {day}
            </span>
            {/* The name goes on from what is seen (WCAG 2.5.3). */}
            <span className="sr-only">{` ${rest}`}</span>
            {/* The load, by length — its number is in the name. */}
            <span
              aria-hidden="true"
              className={`h-1 rounded-pill ${dot ? `${dot} bg-primary` : 'w-1'}`}
            />
          </button>
        );
      })}
    </div>
  );
}
