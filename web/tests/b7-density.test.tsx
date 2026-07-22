import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Card } from '../components/Card';
import { DataTable } from '../components/DataTable';
import { StatusChip, statusChipKind, statusChipLabel } from '../components/StatusChip';

/// B7 — Card / StatusChip / DataTable contracts (web-b7-desktop.md), pinned.

afterEach(cleanup);

describe('Card (§11.3)', () => {
  it('is the spec box: secondary · rounded-xl · border · p-m density', () => {
    const { container } = render(<Card>x</Card>);
    const el = container.firstElementChild!;
    for (const cls of ['bg-secondary', 'rounded-xl', 'border-border', 'p-m']) {
      expect(el.className).toContain(cls);
    }
  });

  it('renders semantic hosts via as=', () => {
    const { container } = render(<Card as="section">x</Card>);
    expect(container.querySelector('section')).not.toBeNull();
  });
});

describe('statusChipKind — kind, not color, is the API (§11.2)', () => {
  it('maps the complete cross-surface inventory', () => {
    for (const s of ['verified', 'active', 'confirmed', 'resolved', 'paid', 'arrived'])
      expect(statusChipKind(s), s).toBe('ok');
    for (const s of ['pending', 'open', 'trial', 'invited', 'grace'])
      expect(statusChipKind(s), s).toBe('pending');
    for (const s of ['rejected', 'suspended', 'banned', 'hidden', 'cancelled', 'noShow', 'no_show', 'expired', 'revoked'])
      expect(statusChipKind(s), s).toBe('danger');
    for (const s of ['completed', 'draft', 'anything-else', '', undefined, null] as const)
      expect(statusChipKind(s as string), String(s)).toBe('neutral');
  });

  it('is case- and separator-insensitive (NoShow, NO_SHOW, no-show)', () => {
    for (const s of ['NoShow', 'NO_SHOW', 'no-show']) expect(statusChipKind(s)).toBe('danger');
  });

  it('speaks French: the appointment vocabulary + the wider inventory', () => {
    expect(statusChipLabel('pending')).toBe('En attente');
    expect(statusChipLabel('noShow')).toBe('Absent');
    expect(statusChipLabel('verified')).toBe('Vérifié');
    expect(statusChipLabel('revoked')).toBe('Accès révoqué');
  });

  it('labels are normalization-robust like kinds (NO_SHOW, no-show, EXPIRED)', () => {
    // The review's catch: a variant spelling tinted the pill red (kind is
    // normalized) while printing the raw enum beside it (label was not).
    expect(statusChipLabel('NO_SHOW')).toBe('Absent');
    expect(statusChipLabel('no-show')).toBe('Absent');
    expect(statusChipLabel('EXPIRED')).toBe('Expirée');
  });

  it('renders the kind tint (pending = warning amber, danger = error red)', () => {
    const { rerender } = render(<StatusChip status="pending" />);
    expect(screen.getByText('En attente').className).toContain('text-warning');
    rerender(<StatusChip status="cancelled" />);
    expect(screen.getByText('Annulé').className).toContain('text-error');
    rerender(<StatusChip status="completed" />);
    expect(screen.getByText('Terminé').className).toContain('bg-surface');
  });
});

describe('DataTable — the four-state twin (§11.2/§12)', () => {
  const cols = [{ label: 'Nom' }, { label: 'Montant', align: 'right' as const }];

  it('loading = 4 pulsing skeleton rows, hidden from AT', () => {
    const { container } = render(
      <DataTable columns={cols} rows={[]} isLoading emptyTitle="Vide" />,
    );
    const skeleton = container.querySelector('[aria-hidden="true"]')!;
    expect(skeleton.children).toHaveLength(4);
    expect(skeleton.innerHTML).toContain('animate-pulse');
  });

  it('error = message + a REAL « Réessayer »', () => {
    const retry = vi.fn();
    render(
      <DataTable columns={cols} rows={[]} error="Chargement impossible." onRetry={retry} emptyTitle="Vide" />,
    );
    expect(screen.getByRole('alert')).toHaveTextContent('Chargement impossible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(retry).toHaveBeenCalled();
  });

  it('empty = the plain EmptyState anatomy', () => {
    render(
      <DataTable columns={cols} rows={[]} emptyTitle="Aucun client" emptyDescription="Ils apparaîtront ici." />,
    );
    expect(screen.getByText('Aucun client')).toBeInTheDocument();
    expect(screen.getByText('Ils apparaîtront ici.')).toBeInTheDocument();
  });

  it('is a REAL ARIA table: rowgroups, columnheaders, cells, shared tracks', () => {
    const { container } = render(
      <DataTable
        columns={[{ label: 'Nom', flex: 3 }, { label: 'Montant', flex: 1, align: 'right' as const }]}
        rows={[
          { key: 'a', cells: ['Awa', '5 000 FCFA'] },
          { key: 'b', cells: ['Koffi', '8 000 FCFA'] },
        ]}
        emptyTitle="Vide"
      />,
    );
    // The review's regression: Équipe's hand-rolled <table> gave AT the
    // column↔cell association; the div grid must keep it via ARIA roles.
    screen.getByRole('table');
    expect(screen.getAllByRole('columnheader').map((h) => h.textContent)).toEqual(['Nom', 'Montant']);
    expect(screen.getAllByRole('row')).toHaveLength(3); // header + 2
    expect(screen.getAllByRole('cell')).toHaveLength(4);
    // minmax(0, Nfr) tracks: every row resolves the SAME widths — a plain Nfr
    // lets one long unbreakable cell misalign its own row's columns.
    const row = container.querySelector('[role="rowgroup"] [role="row"]') as HTMLElement;
    expect(row.style.gridTemplateColumns).toBe('minmax(0, 3fr) minmax(0, 1fr)');
  });

  it('a navigation row = a NAMED first-cell link stretched over the row', () => {
    const { container } = render(
      <DataTable
        columns={cols}
        rows={[{ key: 'a', cells: ['Awa', '5 000 FCFA'], href: '/pro/clients/a', rowLabel: 'Ouvrir la fiche de Awa' }]}
        emptyTitle="Vide"
      />,
    );
    const link = screen.getByRole('link', { name: 'Ouvrir la fiche de Awa' });
    expect(link).toHaveAttribute('href', '/pro/clients/a');
    // The first cell's content lives INSIDE the control; the stretch span
    // (absolute inset-0, anchored to the row) extends its hit area row-wide.
    expect(link).toContainElement(screen.getByText('Awa'));
    expect(link.querySelector('[aria-hidden="true"]')!.className).toContain('inset-0');
    // The OTHER cells stay outside the control — table nav reads them clean.
    expect(link).not.toContainElement(screen.getByText('5 000 FCFA'));
    const bodyRow = container.querySelectorAll('[role="rowgroup"]')[1].querySelector('[role="row"]')!;
    expect(bodyRow.className).toContain('relative');
  });

  it('current marks the edited row: aria-current + the surfaceVariant tint', () => {
    render(
      <DataTable
        columns={cols}
        rows={[
          { key: 'a', cells: ['Tresses', '5 000'], current: true },
          { key: 'b', cells: ['Coupe', '3 000'] },
        ]}
        emptyTitle="Vide"
      />,
    );
    const rows = screen.getAllByRole('row').slice(1);
    expect(rows[0]).toHaveAttribute('aria-current', 'true');
    expect(rows[0].className).toContain('bg-surfaceVariant');
    expect(rows[1]).not.toHaveAttribute('aria-current');
  });

  it('success = header + rows; a clickable row is a NAMED, focusable control', () => {
    const onClick = vi.fn();
    render(
      <DataTable
        columns={cols}
        rows={[
          { key: 'a', cells: ['Awa', '5 000 FCFA'], onClick, rowLabel: 'Ouvrir la fiche de Awa' },
          { key: 'b', cells: ['Koffi', '8 000 FCFA'] },
        ]}
        emptyTitle="Vide"
      />,
    );
    expect(screen.getByText('Nom')).toBeInTheDocument();
    const rowBtn = screen.getByRole('button', { name: 'Ouvrir la fiche de Awa' });
    fireEvent.click(rowBtn);
    expect(onClick).toHaveBeenCalled();
    expect(screen.getByText('Koffi')).toBeInTheDocument();
  });
});
