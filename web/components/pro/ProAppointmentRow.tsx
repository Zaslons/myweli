import { statusLabelFr } from '../../lib/account/appointments';
import { formatFcfa } from '../../lib/format';
import type { ProAppointment } from '../../lib/pro/today';

const slotTime = (iso: string) =>
  new Intl.DateTimeFormat('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
  }).format(new Date(iso));

/// One booking row in the pro views (Aujourd'hui + Rendez-vous). Service names
/// are resolved by the caller from the salon's catalogue.
export function ProAppointmentRow({
  appt,
  serviceName,
}: {
  appt: ProAppointment;
  serviceName: (id: string) => string | undefined;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m">
      <div>
        <p className="font-medium text-textPrimary">
          {slotTime(appt.appointmentDate)} · {appt.clientName ?? 'Client'}
        </p>
        <p className="text-sm text-textTertiary">
          {(appt.serviceIds ?? [])
            .map(serviceName)
            .filter(Boolean)
            .join(', ')}
        </p>
      </div>
      <div className="text-right">
        <span className="rounded-full bg-surface px-s py-xs text-xs text-textSecondary">
          {statusLabelFr(appt.status)}
        </span>
        {typeof appt.totalPrice === 'number' ? (
          <p className="mt-s text-sm text-textPrimary">
            {formatFcfa(appt.totalPrice)}
          </p>
        ) : null}
      </div>
    </div>
  );
}
