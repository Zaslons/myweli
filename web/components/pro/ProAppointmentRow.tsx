import Link from 'next/link';
import { statusLabelFr } from '../../lib/account/appointments';
import { formatFcfa } from '../../lib/format';
import type { ProAppointment } from '../../lib/pro/today';
import { salonFormatter } from '../../lib/time';

const slotTime = (iso: string, tz?: string) =>
  salonFormatter({ hour: '2-digit', minute: '2-digit' }, tz).format(
    new Date(iso),
  );

/// One booking row in the pro views (Aujourd'hui + Rendez-vous). Service names
/// are resolved by the caller from the salon's catalogue. When `href` is set the
/// row links to the booking detail. The active salon's timezone/currency come
/// from the caller's provider payload (multi-pays MP3).
export function ProAppointmentRow({
  appt,
  serviceName,
  href,
  tz,
  currency,
}: {
  appt: ProAppointment;
  serviceName: (id: string) => string | undefined;
  href?: string;
  tz?: string | null;
  currency?: string | null;
}) {
  const card = (
    <div className="flex items-center justify-between rounded-xl border border-border bg-secondary p-m hover:bg-surfaceVariant">
      <div>
        <p className="font-medium text-textPrimary">
          {slotTime(appt.appointmentDate, tz ?? undefined)} ·{' '}
          {appt.clientName ?? 'Client'}
        </p>
        <p className="text-sm text-textTertiary">
          {(appt.serviceIds ?? [])
            .map(serviceName)
            .filter(Boolean)
            .join(', ')}
        </p>
      </div>
      <div className="text-right">
        <span className="rounded-pill bg-surface px-s py-xs text-xs text-textSecondary">
          {statusLabelFr(appt.status)}
        </span>
        {typeof appt.totalPrice === 'number' ? (
          <p className="mt-s text-sm text-textPrimary">
            {formatFcfa(appt.totalPrice, currency ?? undefined)}
          </p>
        ) : null}
      </div>
    </div>
  );

  return href ? (
    <Link href={href} className="block">
      {card}
    </Link>
  ) : (
    card
  );
}
