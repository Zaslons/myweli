import { render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { OpenInAppButton } from '../components/OpenInAppButton';

/// **A dead link wearing a CTA.** Production served
/// `<a href="#">Ouvrir dans l'app</a>` on the homepage until 2026-08-20 — the
/// store URLs do not exist until the apps are listed, and the component fell
/// back to '#'. `AppInstallBanner` had already reasoned this out and renders
/// nothing instead; this one had not.
///
/// LAUNCH.md asks that install prompts "point somewhere real, or are hidden
/// until the apps exist". Both halves are asserted here.
describe('OpenInAppButton', () => {
  afterEach(() => vi.unstubAllEnvs());

  it('renders nothing when no store URL exists', () => {
    const { container } = render(<OpenInAppButton />);
    expect(container).toBeEmptyDOMElement();
  });

  it('never renders href="#"', () => {
    const { container } = render(<OpenInAppButton />);
    expect(container.querySelector('a[href="#"]')).toBeNull();
  });

  it('renders a real link once a store URL exists', () => {
    vi.stubEnv('NEXT_PUBLIC_ANDROID_APP_URL', 'https://play.google.com/store/apps/details?id=x');
    render(<OpenInAppButton />);
    const a = screen.getByRole('link', { name: /Ouvrir dans l’app/i });
    expect(a).toHaveAttribute('href', 'https://play.google.com/store/apps/details?id=x');
  });
});
