import Link from 'next/link';
import { Chip } from '../Chip';
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
          <p className="mt-xs text-bodyMedium text-textSecondary">
            {formatDateTimeFr(
              appt.appointmentDate,
              appt.providerTimezone ?? undefined,
            )}
          </p>
          {appt.serviceNames && appt.serviceNames.length > 0 ? (
            <p className="mt-xs text-bodyMedium text-textTertiary">
              {appt.serviceNames.join(', ')}
            </p>
          ) : null}
          {appt.salonEntered ? (
            <p className="mt-xs text-bodySmall text-textTertiary">
              Réservé par votre salon
            </p>
          ) : null}
        </div>
        <div className="text-right">
          <Chip>
            {statusLabelFr(appt.status)}
          </Chip>
          {typeof appt.totalPrice === 'number' ? (
            <p className="mt-s text-bodyMedium text-textPrimary">
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
