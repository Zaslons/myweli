import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, expect, it } from 'vitest';
import { MiniCard } from '../components/discovery/ResultsMap';
import { ProviderHero } from '../components/provider/Hero';
import { providerFixture } from './fixtures';

/// docs/design/salon-rating-new-and-visits-card.md §2.1 — the web's three
/// rating sites. They HID the rating of a salon nobody had reviewed (three
/// `reviewCount > 0` guards); the app printed « ★ 0.0 · 0 avis ». Both now say
/// « Nouveau ».

afterEach(cleanup);

it('the salon page header: « Nouveau » at 0 reviews, the count otherwise', () => {
  const { container, rerender } = render(
    <ProviderHero provider={{ ...providerFixture, rating: 0, reviewCount: 0 }} />,
  );
  const pill = screen.getByText('Nouveau');
  // A pill with a shape: the ink tint, not the page-coloured `neutral`.
  expect(pill.className).toContain('bg-textSecondary/10');
  expect(container.textContent).not.toMatch(/0,0|0 avis/);

  rerender(
    <ProviderHero provider={{ ...providerFixture, rating: 4.8, reviewCount: 32 }} />,
  );
  expect(screen.queryByText('Nouveau')).toBeNull();
  expect(container.textContent).toContain('Note ★ 4,8 (32 avis)');
});

it('the map popup: « Nouveau · {commune} » at 0 reviews', () => {
  const { container } = render(
    <MiniCard
      provider={{ ...providerFixture, rating: 0, reviewCount: 0, latitude: 5.3, longitude: -4 }}
    />,
  );
  expect(screen.getByText('Nouveau')).toBeInTheDocument();
  expect(container.textContent).not.toMatch(/0,0/);
});
