import { render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Faq } from '../components/provider/Faq';
import { Hours } from '../components/provider/Hours';
import { ReviewList } from '../components/provider/ReviewList';
import { ServiceList } from '../components/provider/ServiceList';
import { providerFixture } from './fixtures';

const norm = (s: string | null) => (s ?? '').replace(/\s/g, ' ');

describe('provider sections', () => {
  it('ServiceList shows name, duration and price range', () => {
    const { container } = render(
      <ServiceList services={providerFixture.services ?? []} />,
    );
    expect(screen.getByText('Tresses')).toBeInTheDocument();
    const text = norm(container.textContent);
    expect(text).toContain('2 h');
    expect(text).toContain('15 000 – 25 000 FCFA');
  });

  it('ReviewList shows the rating summary + a review', () => {
    render(
      <ReviewList
        reviews={providerFixture.reviews ?? []}
        rating={providerFixture.rating}
        reviewCount={providerFixture.reviewCount}
        slug="beaute-divine"
      />,
    );
    expect(screen.getByText(/Avis \(12\)/)).toBeInTheDocument();
    expect(screen.getByText('Awa')).toBeInTheDocument();
    expect(screen.getByText('Service impeccable.')).toBeInTheDocument();
  });

  it('Faq renders each question; hides when empty', () => {
    const { rerender } = render(
      <Faq items={[{ question: 'Comment réserver ?', answer: 'En ligne.' }]} />,
    );
    expect(screen.getByText('Comment réserver ?')).toBeInTheDocument();
    rerender(<Faq items={[]} />);
    expect(screen.queryByText('Comment réserver ?')).not.toBeInTheDocument();
  });
});

describe('Hours — the wire time renders as a time, never as the wire', () => {
  // The screenshot bug: « 2024-01-01T09:00:00.000Z – … » painted on the live
  // salon page. The fixture uses the REAL wire shape — the e2e stub's bare
  // '09:00' is exactly how this stayed green while production was wrong.
  it('renders HH:mm ranges, with no ISO residue anywhere', () => {
    const { container } = render(
      <Hours availability={providerFixture.availability} />,
    );
    const text = norm(container.textContent);
    expect(text).toContain('09:00 – 12:00, 14:00 – 18:00'); // split day kept
    expect(text).not.toContain('2024-01-01');
    expect(text).not.toContain('T09');
    expect(text).not.toContain('Z');
  });

  it('an unavailable slot is not an opening hour — its day reads Fermé', () => {
    // within(container): the file does not auto-cleanup, and even a render
    // result's own queries read document.body — only the container scopes.
    const { container } = render(
      <Hours availability={providerFixture.availability} />,
    );
    // Mardi holds only an isAvailable:false slot; Mercredi..Dimanche are
    // absent. Six « Fermé » rows in all — the unavailable day among them.
    expect(within(container).getAllByText('Fermé')).toHaveLength(6);
  });

  it('no availability at all → no section', () => {
    const { container } = render(<Hours availability={undefined} />);
    expect(container.textContent).toBe('');
  });
});
