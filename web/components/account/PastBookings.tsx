import { ButtonLink } from '../ButtonLink';
import { Card } from '../Card';
import { AppointmentCard } from './AppointmentCard';
import {
  type Appointment,
  groupByMonth,
  rebookHref,
  visitSummary,
} from '../../lib/account/appointments';
import { canRebook } from '../../lib/account/extras';
import { formatFcfa, pluralFr } from '../../lib/format';
import { UNNAMED_SALON_IN_SENTENCE, salonNameOr } from '../../lib/salon-name';

/// « Passés », as in the app's history (docs/design/web-account-bookings-truth.md
/// §2.4, decisions 167 and 182; mobile `my_bookings_screen.dart` `_buildHistory`):
/// the summary of « Terminé » visits, then the months, then under each booking
/// « Réserver à nouveau » when its salon is still open.
///
/// `items` are the tab's bookings (`bookingsForTab(…, 'past', now)`), never
/// empty: the caller shows the tab's empty state instead.
export function PastBookings({
  items,
  now,
}: {
  items: Appointment[];
  now: Date;
}) {
  const summary = visitSummary(items);
  const months = groupByMonth(items);
  return (
    <div>
      {/* Only what the salon marked « Terminé » is a visit we can count. A
          past booking nobody closed, or an absence, is listed below with its
          own chip and counted nowhere; with none, the summary is hidden
          rather than read « 0 visite ». */}
      {summary ? (
        <dl className="flex flex-wrap gap-m">
          {/* `grow` keeps the auto basis, so the two cards wrap to one per
              row when a long total no longer fits beside the count — the
              number never breaks inside itself (its group separator is a
              no-break space). The value is SHOWN first and READ second: a
              screen reader says « visites, 3 ». */}
          <Card className="flex grow flex-col-reverse">
            <dt className="text-bodySmall text-textSecondary">
              {pluralFr(summary.count, 'visite', 'visites')}
            </dt>
            <dd className="text-titleLarge font-semibold text-textPrimary">
              {summary.count}
            </dd>
          </Card>
          <Card className="flex grow flex-col-reverse">
            <dt className="text-bodySmall text-textSecondary">dépensés</dt>
            <dd className="text-titleLarge font-semibold text-textPrimary">
              {formatFcfa(summary.total, summary.currency)}
            </dd>
          </Card>
        </dl>
      ) : null}
      {months.map((month, i) => (
        <div key={month.key} className={summary || i > 0 ? 'mt-l' : ''}>
          {/* The month in the salon's zone, the zone of the card's own date
              line. Upper case is CSS: a screen reader reads the words. */}
          <h3 className="text-labelMedium font-medium uppercase text-textTertiary">
            {month.label}
          </h3>
          <ul className="mt-s space-y-m">
            {month.items.map((a) => (
              <li key={a.id}>
                <AppointmentCard appt={a} now={now} />
                {/* A stopped salon gets no button: its card already says
                    why. A salon status this build does not know, or a booking
                    missing its slug, gets neither (`rebookHref` is null). */}
                {canRebook(a, now) ? (
                  <ButtonLink
                    href={rebookHref(a)!}
                    variant="secondary"
                    className="mt-s w-full sm:w-auto"
                  >
                    Réserver à nouveau
                    {/* N identical « Réserver à nouveau » links would read as
                        one in a screen reader's list of links. */}
                    <span className="sr-only">
                      {' '}
                      chez {salonNameOr(a.providerName, UNNAMED_SALON_IN_SENTENCE)}
                    </span>
                  </ButtonLink>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}
