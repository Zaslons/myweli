import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it } from 'vitest';
import { AppInstallBanner } from '../components/AppInstallBanner';

describe('AppInstallBanner', () => {
  beforeEach(() => window.localStorage.clear());

  it('shows the install push, then hides on dismiss (remembered)', () => {
    const { unmount } = render(<AppInstallBanner />);
    expect(screen.getByText(/Réservez plus vite/i)).toBeInTheDocument();

    fireEvent.click(screen.getByLabelText('Fermer'));
    expect(screen.queryByText(/Réservez plus vite/i)).not.toBeInTheDocument();
    unmount();

    // Dismissal persists across renders.
    render(<AppInstallBanner />);
    expect(screen.queryByText(/Réservez plus vite/i)).not.toBeInTheDocument();
  });
});
