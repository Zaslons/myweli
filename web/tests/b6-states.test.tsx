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
    const why = screen.getByText('Les avis de vos clients apparaîtront ici.');
    // B8 (row 17): the WHY is reading copy — it reads at 16, never 14.
    expect(why.className).toContain('text-bodyLarge');
    expect(why.className).not.toContain('text-bodyMedium');
    expect(screen.getByRole('link', { name: 'Agir' })).toBeInTheDocument();
  });

  it('is server-safe: action is a node, and title alone renders', () => {
    render(<EmptyState title="Aucun résultat" />);
    expect(screen.getByText('Aucun résultat')).toBeInTheDocument();
  });
});

/// docs/design/web-swiss-cards.md §5: flush left for the public pages, and nothing
/// moves for the pro pages and the account, which keep the default.
describe('EmptyState `align`', () => {
  const full = (align?: 'center' | 'start', plain?: boolean) =>
    render(
      <EmptyState
        align={align}
        plain={plain}
        icon="search"
        title="Aucun résultat"
        action={<a href="/recherche">Agir</a>}
      />,
    ).container;

  it('the default is byte for byte what it was', () => {
    const c = full();
    expect((c.firstChild as HTMLElement).className).toBe(
      'rounded-xl border border-border bg-secondary p-xl text-center ',
    );
    expect(c.querySelector('[class*="mx-auto"]')).not.toBeNull();
    expect(screen.getByRole('link', { name: 'Agir' }).parentElement!.className).toBe(
      'mt-l flex justify-center',
    );
  });

  it('plain, and a caller’s class, are too', () => {
    const plain = full('center', true);
    expect((plain.firstChild as HTMLElement).className).toBe('p-xl text-center ');
    const placed = render(<EmptyState title="Vide" className="mt-s" />).container;
    expect((placed.firstChild as HTMLElement).className).toBe(
      'rounded-xl border border-border bg-secondary p-xl text-center mt-s',
    );
  });

  it('`start` has no box, no padding and nothing centred, and the lens stands on the edge', () => {
    const c = full('start');
    const root = c.firstChild as HTMLElement;
    for (const gone of ['rounded-xl', 'border', 'bg-secondary', 'p-xl', 'text-center']) {
      expect(root.className).not.toContain(gone);
    }
    expect(c.innerHTML).not.toContain('mx-auto');
    expect(c.innerHTML).not.toContain('justify-center');
    expect(c.querySelector('[class*="-ml-s"]')).not.toBeNull();
    expect(screen.getByRole('link', { name: 'Agir' }).parentElement!.className).toBe('mt-l flex');
  });
});

describe('ErrorState', () => {
  it('message is an alert; retry is a REAL control (§12: never a dead end)', () => {
    const retry = vi.fn();
    render(<ErrorState onRetry={retry} />);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('Une erreur est survenue. Réessayez.');
    // B8 (row 17): a page-level error body is reading copy — 16, never 14
    // (the role=alert FIELD errors stay small; this is not one of them).
    expect(alert.className).toContain('text-bodyLarge');
    expect(alert.className).not.toContain('text-bodyMedium');
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
