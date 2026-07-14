import Link from 'next/link';
import {
  type Appointment,
  statusLabelFr,
} from '../../lib/account/appointments';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';

/// One booking in the account list. Links to the detail page.
export function AppointmentCard({ appt }: { appt: Appointment }) {
  return (
    <Link
      href={`/mon-compte/${appt.id}`}
      className="block rounded-xl border border-border bg-secondary p-m hover:bg-surfaceVariant"
    >
      <div className="flex items-start justify-between gap-m">
        <div>
          <p className="font-medium text-textPrimary">
            {appt.providerName ?? 'Salon'}
          </p>
          <p className="mt-xs text-sm text-textSecondary">
            {formatDateTimeFr(
              appt.appointmentDate,
              appt.providerTimezone ?? undefined,
            )}
          </p>
          {appt.serviceNames && appt.serviceNames.length > 0 ? (
            <p className="mt-xs text-sm text-textTertiary">
              {appt.serviceNames.join(', ')}
            </p>
          ) : null}
          {appt.salonEntered ? (
            <p className="mt-xs text-xs text-textTertiary">
              Réservé par votre salon
            </p>
          ) : null}
        </div>
        <div className="text-right">
          <span className="rounded-full bg-surface px-s py-xs text-xs text-textSecondary">
            {statusLabelFr(appt.status)}
          </span>
          {typeof appt.totalPrice === 'number' ? (
            <p className="mt-s text-sm text-textPrimary">
              {formatFcfa(
                appt.totalPrice,
                appt.currency ?? appt.providerCurrency ?? undefined,
              )}
            </p>
          ) : null}
        </div>
      </div>
    </Link>
  );
}
