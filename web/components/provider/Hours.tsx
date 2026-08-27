import type { Provider } from '../../lib/api/providers';
import { weekdaysFr } from '../../lib/format';
import { timeOfDay } from '../../lib/time-of-day';

export function Hours({
  availability,
}: {
  availability: Provider['availability'];
}) {
  const schedule = availability?.weeklySchedule;
  if (!schedule) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Horaires</h2>
      <ul className="mt-m">
        {weekdaysFr.map((day, i) => {
          // isAvailable honoured like the app's detail page: a slot marked
          // unavailable is not an opening hour, and a day with none left is
          // « Fermé ». The wire value is `2024-01-01T09:00:00.000Z` — the
          // date a carrier, the time-of-day the datum — so it renders
          // through timeOfDay, never raw and never through new Date().
          const windows = (schedule[String(i)] ?? []).filter(
            (w) => w.isAvailable !== false,
          );
          return (
            <li key={day} className="flex justify-between py-xs text-bodyMedium">
              <span className="text-textSecondary">{day}</span>
              <span className="text-textPrimary">
                {windows.length
                  ? windows
                      .map(
                        (w) =>
                          `${timeOfDay(w.startTime)} – ${timeOfDay(w.endTime)}`,
                      )
                      .join(', ')
                  : 'Fermé'}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
