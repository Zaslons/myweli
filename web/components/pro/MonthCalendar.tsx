'use client';

import {
  addMonths,
  anchorKey,
  dateKey,
  daysWithBookings,
  monthLabelFr,
  monthMatrix,
} from '../../lib/pro/agenda';
import type { ProAppointment } from '../../lib/pro/today';
import { Button } from '../Button';

const WEEKDAYS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Month grid (Monday-start) — mirrors the app's calendar view: today + days with
/// bookings are marked; clicking a day selects it. Cell identity is anchor
/// (UTC-field) math; « today » and the booking dots are SALON-day facts and
/// take the active salon's tz (multi-pays MP3).
export function MonthCalendar({
  items,
  focused,
  selected,
  onFocus,
  onSelect,
  tz,
}: {
  items: ProAppointment[];
  focused: Date;
  selected: string;
  onFocus: (d: Date) => void;
  onSelect: (key: string) => void;
  tz?: string | null;
}) {
  const weeks = monthMatrix(focused);
  const booked = daysWithBookings(items, tz ?? undefined);
  const month = focused.getUTCMonth();
  const todayK = dateKey(new Date(), tz ?? undefined);

  return (
    <div>
      <div className="flex items-center justify-between">
        <Button variant="secondary" onClick={() => onFocus(addMonths(focused, -1))}>
          ‹
        </Button>
        <p className="text-labelLarge font-medium capitalize text-textPrimary">
          {monthLabelFr(focused)}
        </p>
        <Button variant="secondary" onClick={() => onFocus(addMonths(focused, 1))}>
          ›
        </Button>
      </div>

      <div className="mt-m grid grid-cols-7 gap-xs text-center text-bodySmall text-textTertiary">
        {WEEKDAYS.map((d) => (
          <div key={d}>{d}</div>
        ))}
      </div>
      <div className="mt-xs grid grid-cols-7 gap-xs" data-testid="month-grid">
        {weeks.flat().map((d) => {
          const k = anchorKey(d);
          const inMonth = d.getUTCMonth() === month;
          // **Days outside the month are reserved space, not dimmed buttons**
          // (A14c, WEB-SYSTEM §15 row 34). They used to render `text-textTertiary`
          // and stay clickable, so tapping one selected a day the header does not
          // name — a defect rather than a style. Mobile's grid omits them
          // (`myweli_month_grid.dart`), and web matches mobile here rather than
          // the other way round; `textTertiary` is also already spent on
          // *disabled*, so dimmed-but-active and disabled were the same grey.
          //
          // Blank, not absent: the cell keeps its place so the grid stays
          // rectangular and the month does not reflow.
          if (!inMonth) return <div key={k} aria-hidden="true" />;
          const isSel = k === selected;
          const isToday = k === todayK;
          const hasBooking = booked.has(k);
          return (
            <button
              key={k}
              type="button"
              onClick={() => onSelect(k)}
              className={`min-h-12 flex aspect-square flex-col items-center justify-center rounded-lg text-bodyMedium ${
                isSel
                  ? 'bg-primary text-secondary'
                  : 'text-textPrimary hover:bg-surfaceVariant'
              } ${isToday && !isSel ? 'ring-1 ring-primary' : ''}`}
            >
              <span>{d.getUTCDate()}</span>
              {hasBooking ? (
                <span
                  className={`mt-xs h-xs w-xs rounded-pill ${
                    isSel ? 'bg-secondary' : 'bg-primary'
                  }`}
                />
              ) : null}
            </button>
          );
        })}
      </div>
    </div>
  );
}
