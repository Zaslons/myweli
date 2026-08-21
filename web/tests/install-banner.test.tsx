import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AppInstallBanner } from '../components/AppInstallBanner';
import * as appStore from '../lib/appStore';

/// **This file used to assert the defect.** It rendered the banner with no
/// store URL configured and expected « Réservez plus vite — téléchargez l'app
/// MyWeli » to be present — which is exactly what production served: an offer
/// above a dismiss button, with nothing to download. The test was green because
/// it pinned the behaviour rather than the intent.
describe('AppInstallBanner', () => {
  beforeEach(() => window.localStorage.clear());
  afterEach(() => vi.restoreAllMocks());

  it('SAYS NOTHING WHEN THERE IS NO APP TO INSTALL', () => {
    vi.spyOn(appStore, 'appStoreUrl').mockReturnValue(null);
    const { container } = render(<AppInstallBanner />);
    expect(
      container,
      'promising an app with no way to get it is the defect, not the fallback',
    ).toBeEmptyDOMElement();
  });

  it('shows the install push once a store URL exists, then hides on dismiss (remembered)', () => {
    vi.spyOn(appStore, 'appStoreUrl').mockReturnValue(
      'https://play.google.com/store/apps/details?id=com.myweli',
    );

    const { unmount } = render(<AppInstallBanner />);
    expect(screen.getByText(/Réservez plus vite/i)).toBeInTheDocument();
    // The copy and the link arrive together — the invariant the homepage guard
    // asserts at page level.
    expect(screen.getByRole('link', { name: /Télécharger/i })).toHaveAttribute(
      'href',
      expect.stringContaining('play.google.com'),
    );

    fireEvent.click(screen.getByLabelText('Fermer'));
    expect(screen.queryByText(/Réservez plus vite/i)).not.toBeInTheDocument();
    unmount();

    // Dismissal persists across renders.
    render(<AppInstallBanner />);
    expect(screen.queryByText(/Réservez plus vite/i)).not.toBeInTheDocument();
  });
});
