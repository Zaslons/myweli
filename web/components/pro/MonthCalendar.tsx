'use client';

import {
  addMonths,
  dateKey,
  daysWithBookings,
  monthLabelFr,
  monthMatrix,
} from '../../lib/pro/agenda';
import type { ProAppointment } from '../../lib/pro/today';
import { Button } from '../Button';

const WEEKDAYS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Month grid (Monday-start) — mirrors the app's calendar view: today + days with
/// bookings are marked; clicking a day selects it.
export function MonthCalendar({
  items,
  focused,
  selected,
  onFocus,
  onSelect,
}: {
  items: ProAppointment[];
  focused: Date;
  selected: string;
  onFocus: (d: Date) => void;
  onSelect: (key: string) => void;
}) {
  const weeks = monthMatrix(focused);
  const booked = daysWithBookings(items);
  const month = focused.getUTCMonth();
  const todayK = dateKey(new Date());

  return (
    <div>
      <div className="flex items-center justify-between">
        <Button variant="secondary" onClick={() => onFocus(addMonths(focused, -1))}>
          ‹
        </Button>
        <p className="text-sm font-medium capitalize text-textPrimary">
          {monthLabelFr(focused)}
        </p>
        <Button variant="secondary" onClick={() => onFocus(addMonths(focused, 1))}>
          ›
        </Button>
      </div>

      <div className="mt-m grid grid-cols-7 gap-xs text-center text-xs text-textTertiary">
        {WEEKDAYS.map((d) => (
          <div key={d}>{d}</div>
        ))}
      </div>
      <div className="mt-xs grid grid-cols-7 gap-xs">
        {weeks.flat().map((d) => {
          const k = dateKey(d);
          const inMonth = d.getUTCMonth() === month;
          const isSel = k === selected;
          const isToday = k === todayK;
          const hasBooking = booked.has(k);
          return (
            <button
              key={k}
              type="button"
              onClick={() => onSelect(k)}
              className={`flex aspect-square flex-col items-center justify-center rounded-lg text-sm ${
                isSel
                  ? 'bg-primary text-secondary'
                  : inMonth
                    ? 'text-textPrimary hover:bg-surfaceVariant'
                    : 'text-textTertiary'
              } ${isToday && !isSel ? 'ring-1 ring-primary' : ''}`}
            >
              <span>{d.getUTCDate()}</span>
              {hasBooking ? (
                <span
                  className={`mt-xs h-xs w-xs rounded-full ${
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
