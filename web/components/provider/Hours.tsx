import type { Provider } from '../../lib/api/providers';
import { weekdaysFr } from '../../lib/format';

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
          const windows = schedule[String(i)] ?? [];
          return (
            <li key={day} className="flex justify-between py-xs text-bodyMedium">
              <span className="text-textSecondary">{day}</span>
              <span className="text-textPrimary">
                {windows.length
                  ? windows
                      .map((w) => `${w.startTime} – ${w.endTime}`)
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
