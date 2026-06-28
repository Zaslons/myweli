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
