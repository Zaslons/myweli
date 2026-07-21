import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { EmptyState } from '../components/EmptyState';
import { ErrorState } from '../components/ErrorState';

/// B6 — EmptyState/ErrorState contracts (§12), pinned.

afterEach(cleanup);

describe('EmptyState', () => {
  it('renders the full anatomy: icon · title · why · action', () => {
    render(
      <EmptyState
        icon="star"
        title="Aucun avis"
        description="Les avis de vos clients apparaîtront ici."
        action={<a href="/x">Agir</a>}
      />,
    );
    expect(screen.getByText('Aucun avis')).toBeInTheDocument();
    expect(
      screen.getByText('Les avis de vos clients apparaîtront ici.'),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Agir' })).toBeInTheDocument();
  });

  it('is server-safe: action is a node, and title alone renders', () => {
    render(<EmptyState title="Aucun résultat" />);
    expect(screen.getByText('Aucun résultat')).toBeInTheDocument();
  });
});

describe('ErrorState', () => {
  it('message is an alert; retry is a REAL control (§12: never a dead end)', () => {
    const retry = vi.fn();
    render(<ErrorState onRetry={retry} />);
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Une erreur est survenue. Réessayez.',
    );
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(retry).toHaveBeenCalledTimes(1);
  });

  it('title renders the page h1 — the heading skeleton survives the error state', () => {
    render(<ErrorState title="Avis" onRetry={() => {}} />);
    expect(screen.getByRole('heading', { level: 1, name: 'Avis' })).toBeInTheDocument();
  });

  it('section-level use: no title, no h1', () => {
    render(<ErrorState message="Chargement impossible." />);
    expect(screen.queryByRole('heading')).not.toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Chargement impossible.');
  });
});
