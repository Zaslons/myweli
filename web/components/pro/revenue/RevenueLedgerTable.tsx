import { DataTable } from '../../DataTable';
import { formatFcfa } from '../../../lib/format';
import { formatLedgerWhen } from '../../../lib/pro/revenue';
import type { RevenueLedgerRow, RevenueLedgerStatus } from '../../../lib/pro/revenue';
import {
  revenueLedgerArtist,
  revenueLedgerClient,
  revenueLedgerEmpty,
  revenueLedgerServices,
} from '../../../lib/pro/revenue-wording';

/// The bookings behind a figure (docs/design/pro-revenue-analytics.md §4.9,
/// §5.1): date and time in salon time · client · prestations · collaborateur
/// · amount in the booking's own currency. Under a prestation's filter the
/// amount is that prestation's line, with « sur {total} » under it. Each row
/// opens the booking — `/pro/rendez-vous/[id]?salon=`, which switches salon
/// first when it must, as the app's `/pro/appointment/:id?salon=`.
export function RevenueLedgerTable({
  rows,
  salon,
  timezone,
  status,
  isLoading = false,
  error = null,
  onRetry,
}: {
  rows: RevenueLedgerRow[];
  salon: string;
  timezone: string;
  status: RevenueLedgerStatus;
  isLoading?: boolean;
  error?: string | null;
  onRetry?: () => void;
}) {
  return (
    <DataTable
      columns={[
        { label: 'Date', flex: 3 },
        { label: 'Client', flex: 3 },
        { label: 'Prestations', flex: 4 },
        { label: 'Collaborateur', flex: 3 },
        { label: 'Montant', flex: 3, align: 'right' },
      ]}
      isLoading={isLoading}
      error={error}
      onRetry={onRetry}
      emptyTitle="Aucun rendez-vous"
      emptyIcon="event"
      emptyDescription={revenueLedgerEmpty(status)}
      // ds-ignore: the ledger's column budget before its box scrolls — the
      // DataTable's own default (the Équipe precedent).
      rows={rows.map((r) => {
        const when = formatLedgerWhen(r.appointmentDate, timezone);
        const amount = formatFcfa(r.amount, r.currency);
        return {
          key: r.appointmentId,
          href: `/pro/rendez-vous/${encodeURIComponent(r.appointmentId)}?salon=${encodeURIComponent(salon)}`,
          rowLabel: `Ouvrir le rendez-vous du ${when}`,
          cells: [
            <span key="d" className="text-textPrimary">
              {when}
            </span>,
            <span key="c" className="break-words">
              {revenueLedgerClient(r)}
            </span>,
            <span key="s" className="break-words text-textSecondary">
              {revenueLedgerServices(r)}
            </span>,
            <span key="a" className="break-words text-textSecondary">
              {revenueLedgerArtist(r)}
            </span>,
            <div key="m" className="text-right">
              <p className="whitespace-nowrap font-semibold text-textPrimary">
                {amount}
                {r.estimated ? (
                  <span className="font-normal text-textSecondary"> · estimé</span>
                ) : null}
              </p>
              {r.amount !== r.totalPrice ? (
                <p className="whitespace-nowrap text-bodySmall text-textTertiary">
                  sur {formatFcfa(r.totalPrice, r.currency)}
                </p>
              ) : null}
            </div>,
          ],
        };
      })}
    />
  );
}
