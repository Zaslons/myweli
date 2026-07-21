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
