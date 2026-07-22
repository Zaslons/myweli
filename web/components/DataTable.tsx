'use client';

import Link from 'next/link';
import type { ReactNode } from 'react';
import { EmptyState } from './EmptyState';
import { ErrorState } from './ErrorState';
import type { IconName } from './Icon';

/// The shared data table (§11.2, B7) — the web twin of the admin console's
/// `AdminDataTable`, "the reference implementation of the four-state
/// contract": header row · four states · 52px comfortable rows with 1px
/// dividers and a `surfaceVariant` hover · optional row activation.
///
/// Mirrored from the CODE (admin_data_table.dart), not the admin doc — the B3
/// lesson: header is bodySmall/textTertiary (the doc said labelMedium; the
/// widget never did), and there is NO in-widget pagination/sorting (the doc's
/// footer was never built in the reference either; callers own paging —
/// ClientsClient's « Charger plus » stays a caller concern).
///
/// **Real table semantics** (B7's review): the markup is an ARIA table —
/// `table → rowgroup → row → columnheader/cell` — so screen readers keep the
/// column↔cell association Équipe's hand-rolled `<table>` used to give (a div
/// grid without roles reads as unlabelled noise on a 5-column roster). The
/// three non-success states render OUTSIDE the `role="table"` element: a
/// skeleton/error/empty block is not a table child.
///
/// **Row activation** = a control in the FIRST cell stretched over the row
/// (an absolutely positioned span inside it; the row is the positioning
/// context) — a link for navigation (`href`; open-in-new-tab works), a button
/// otherwise. Cells stay OUTSIDE the control, so table navigation reads each
/// cell cleanly. The CONTRACT: an activatable row must not contain other
/// interactive cells (give those rows explicit action buttons instead —
/// Équipe's ⋯ menu is the example).
///
/// Tracks are `minmax(0, Nfr)` so every row resolves the SAME column widths —
/// a plain `Nfr` lets one row's long unbreakable cell (an email) widen its
/// own column and misalign the grid; long content is the caller's `truncate`.
///
/// The web upgrades over the twin: the loading skeleton PULSES (B6's
/// `animate-pulse`; the mobile one is static). Below desktop widths the table
/// scrolls horizontally inside its own box (`overflow-x-auto` +
/// `minWidthClassName` — the Équipe precedent); the page never scrolls
/// sideways. Callers whose tables can overflow keep at least one focusable
/// control per row (all four do) — a control-less overflowing table would
/// need the focusable-region pattern; add it with its first real consumer.
export type DataColumn = {
  label: string;
  /** Relative width — the twin's `flex` (default 1). */
  flex?: number;
  align?: 'left' | 'right';
};

export type DataRow = {
  key: string;
  cells: ReactNode[];
  /** Navigation rows: a link in the first cell, stretched over the row. */
  href?: string;
  /** Non-navigation activation (the twin's onTap): a stretched button. */
  onClick?: () => void;
  /** Accessible name for the row control when href/onClick is set. */
  rowLabel?: string;
  /** The row a below-table editor is editing — highlighted + aria-current. */
  current?: boolean;
};

export function DataTable({
  columns,
  rows,
  isLoading = false,
  error = null,
  onRetry,
  emptyTitle,
  emptyIcon,
  emptyDescription,
  // ds-ignore: the table's minimum column budget before its wrapper scrolls —
  // a table-specific measure, not a shared size (the Équipe precedent).
  // eslint-disable-next-line tailwindcss/no-arbitrary-value
  minWidthClassName = 'min-w-[640px]',
}: {
  columns: DataColumn[];
  rows: DataRow[];
  isLoading?: boolean;
  error?: string | null;
  onRetry?: () => void;
  emptyTitle: string;
  emptyIcon?: IconName;
  emptyDescription?: string;
  /** The horizontal-scroll floor below desktop (Tailwind min-w-* class). */
  minWidthClassName?: string;
}) {
  const template = columns.map((c) => `minmax(0, ${c.flex ?? 1}fr)`).join(' ');

  const cellCls = (i: number) =>
    `flex min-h-12 items-center py-s text-bodyMedium text-textPrimary ${
      columns[i]?.align === 'right' ? 'justify-end text-right' : ''
    }`;

  return (
    <div className="overflow-x-auto rounded-xl border border-border bg-secondary">
      <div className={minWidthClassName}>
        <div role="table">
          <div role="rowgroup">
            <div
              role="row"
              className="grid w-full items-center gap-m border-b border-divider px-m"
              style={{ gridTemplateColumns: template }}
            >
              {columns.map((c, i) => (
                <div
                  key={i}
                  role="columnheader"
                  className={`py-sm text-bodySmall text-textTertiary ${
                    c.align === 'right' ? 'text-right' : ''
                  }`}
                >
                  {c.label}
                </div>
              ))}
            </div>
          </div>

          {rows.length > 0 ? (
            <div role="rowgroup" className="divide-y divide-divider">
              {rows.map((row) => {
                const activatable = Boolean(row.href || row.onClick);
                return (
                  <div
                    key={row.key}
                    role="row"
                    aria-current={row.current || undefined}
                    className={`relative grid w-full items-center gap-m px-m ${
                      row.current ? 'bg-surfaceVariant' : ''
                    } ${
                      activatable
                        ? 'hover:bg-surfaceVariant focus-within:bg-surfaceVariant'
                        : ''
                    }`}
                    style={{ gridTemplateColumns: template }}
                  >
                    {row.cells.map((cell, i) => (
                      <div key={i} role="cell" className={cellCls(i)}>
                        {i === 0 && row.href ? (
                          <Link href={row.href} aria-label={row.rowLabel}>
                            {cell}
                            {/* The stretch: extends the control's hit area
                                over the whole row (anchored to the row, the
                                nearest positioned ancestor). */}
                            <span aria-hidden="true" className="absolute inset-0" />
                          </Link>
                        ) : i === 0 && row.onClick ? (
                          <button
                            type="button"
                            aria-label={row.rowLabel}
                            onClick={row.onClick}
                            className="text-left"
                          >
                            {cell}
                            <span aria-hidden="true" className="absolute inset-0" />
                          </button>
                        ) : (
                          cell
                        )}
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
          ) : null}
        </div>

        {isLoading && rows.length === 0 ? (
          <div aria-hidden="true">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="border-b border-divider px-m py-s last:border-b-0">
                <div className="h-8 animate-pulse rounded-sm bg-surfaceVariant motion-reduce:animate-none" />
              </div>
            ))}
          </div>
        ) : error && rows.length === 0 ? (
          <div className="p-l">
            <ErrorState message={error} onRetry={onRetry} />
          </div>
        ) : rows.length === 0 ? (
          <EmptyState
            plain
            icon={emptyIcon}
            title={emptyTitle}
            description={emptyDescription}
          />
        ) : null}
      </div>
    </div>
  );
}
