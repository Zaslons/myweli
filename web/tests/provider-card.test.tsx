import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ProviderCard } from '../components/provider/ProviderCard';
import { providerFixture } from './fixtures';

const norm = (s: string | null) => (s ?? '').replace(/\s/g, ' ');

describe('ProviderCard', () => {
  it('shows name, rating, price-from and links to the provider', () => {
    const { container } = render(<ProviderCard provider={providerFixture} />);
    expect(screen.getByText('Beauté Divine')).toBeInTheDocument();
    expect(container.querySelector('a')?.getAttribute('href')).toBe(
      '/beaute-divine',
    );
    expect(norm(container.textContent)).toContain('à partir de 15 000 FCFA');
  });
});

it('shows the « Vérifié » badge only for verified salons (T52/15.1)', () => {
  const { rerender } = render(
    <ProviderCard provider={{ ...providerFixture, verified: true }} />,
  );
  expect(screen.getByLabelText('Salon vérifié')).toBeInTheDocument();
  rerender(<ProviderCard provider={{ ...providerFixture, verified: false }} />);
  expect(screen.queryByLabelText('Salon vérifié')).toBeNull();
});

it('a salon with no review shows « Nouveau », a reviewed one its rating (salon-rating-new-and-visits-card.md)', () => {
  const { container, rerender } = render(
    <ProviderCard provider={{ ...providerFixture, rating: 0, reviewCount: 0 }} />,
  );
  expect(screen.getByText('Nouveau')).toBeInTheDocument();
  expect(container.textContent).not.toMatch(/0,0/);
  rerender(
    <ProviderCard provider={{ ...providerFixture, rating: 4.8, reviewCount: 32 }} />,
  );
  expect(screen.queryByText('Nouveau')).toBeNull();
  expect(container.textContent).toMatch(/★ 4,8/);
});
