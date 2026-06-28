import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Faq } from '../components/provider/Faq';
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
