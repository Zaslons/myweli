import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import HomePage from '../app/page';

describe('HomePage', () => {
  it('renders the hero heading + the discover CTA', () => {
    render(<HomePage />);
    expect(
      screen.getByRole('heading', { level: 1 }),
    ).toHaveTextContent(/Réservez votre beauté/i);
    expect(screen.getByText(/Découvrir les salons/i)).toBeInTheDocument();
  });
});
