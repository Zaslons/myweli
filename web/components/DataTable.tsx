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
/// The web upgrades over the twin: the loading skeleton PULSES (B6's
/// `animate-pulse`; the mobile one is static), and row activation is a real
/// focusable control wrapping the cells — a link (`href`) for navigation rows
/// so open-in-new-tab works, a button otherwise — so keyboard users get what
/// mouse users get — InkWell gives Flutter that for free; the web must earn it.
///
/// Below desktop widths the table scrolls horizontally inside its own box
/// (`overflow-x-auto` + `minWidthClassName` — the Équipe precedent); the page
/// never scrolls sideways.
export type DataColumn = {
  label: string;
  /** Relative width — the twin's `flex` (default 1). */
  flex?: number;
  align?: 'left' | 'right';
};

export type DataRow = {
  key: string;
  cells: ReactNode[];
  /** Navigation rows: renders the row as a link (open-in-new-tab works). */
  href?: string;
  /** Non-navigation activation (the twin's onTap). Renders the row as a button. */
  onClick?: () => void;
  /** Accessible name for the row control when href/onClick is set. */
  rowLabel?: string;
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
  const template = columns.map((c) => `${c.flex ?? 1}fr`).join(' ');

  const grid = (children: ReactNode, extra = '') => (
    <div
      className={`grid w-full items-center gap-m px-m ${extra}`}
      style={{ gridTemplateColumns: template }}
    >
      {children}
    </div>
  );

  return (
    <div className="overflow-x-auto rounded-xl border border-border bg-secondary">
      <div className={minWidthClassName}>
        {grid(
          columns.map((c, i) => (
            <p
              key={i}
              className={`py-sm text-bodySmall text-textTertiary ${
                c.align === 'right' ? 'text-right' : ''
              }`}
            >
              {c.label}
            </p>
          )),
          'border-b border-divider',
        )}

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
        ) : (
          <ul className="divide-y divide-divider">
            {rows.map((row) => {
              const cells = grid(
                row.cells.map((cell, i) => (
                  <div
                    key={i}
                    className={`flex min-h-12 items-center py-s text-bodyMedium text-textPrimary ${
                      columns[i]?.align === 'right' ? 'justify-end text-right' : ''
                    }`}
                  >
                    {cell}
                  </div>
                )),
              );
              /* The row control WRAPS the cells (keyboard-focusable, ≥48px,
                 named via rowLabel) — a link for navigation rows so
                 open-in-new-tab works, a button for other activation. The
                 CONTRACT: a row with href/onClick must not contain
                 interactive cells (give those rows explicit action buttons
                 instead — Équipe's ⋯ menu is the example). */
              return (
                <li key={row.key}>
                  {row.href ? (
                    <Link
                      href={row.href}
                      aria-label={row.rowLabel}
                      className="block hover:bg-surfaceVariant"
                    >
                      {cells}
                    </Link>
                  ) : row.onClick ? (
                    <button
                      type="button"
                      aria-label={row.rowLabel}
                      onClick={row.onClick}
                      className="block w-full text-left hover:bg-surfaceVariant"
                    >
                      {cells}
                    </button>
                  ) : (
                    cells
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
