import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import SupportPage from '../app/support/page';
import { SUPPORT, supportMailto } from '../lib/support';

/// The page every support affordance now points at.
///
/// ## Why it exists at all
///
/// There was no support channel. `SUPPORT_WHATSAPP` had no default and was
/// passed by no build, so the app's « Aide & Support » showed « Contact bientôt
/// disponible. » in every artifact ever shipped; on web the row rendered only
/// when a number existed, so it never rendered; and the Pro app had no contact
/// affordance anywhere. Three legal documents named that dead path as the
/// contact of record.
///
/// So the property under test is not "the page renders" — it is **that a reader
/// leaves with a way to reach a person**.
describe('the support page', () => {
  it('publishes an address a reader can actually use', () => {
    render(<SupportPage />);
    // Not `getByText`: the address must be a mailto, not decoration. A page
    // that prints an address you cannot click is the same failure in a nicer
    // outfit.
    const link = screen.getByRole('link', { name: SUPPORT.email });
    expect(link).toHaveAttribute('href', supportMailto());
  });

  it('never leaves the reader with nothing', () => {
    render(<SupportPage />);
    const mailtos = screen
      .getAllByRole('link')
      .filter((a) => a.getAttribute('href')?.startsWith('mailto:'));
    expect(mailtos.length).toBeGreaterThan(0);
  });

  it('hides WhatsApp while the number is unset, rather than linking nowhere', () => {
    // NEXT_PUBLIC_MYWELI_WHATSAPP is unset in every build; an empty number
    // yields https://wa.me/?text=… — WhatsApp's own landing page, which looks
    // like it worked. The page must carry email regardless, which the tests
    // above assert.
    render(<SupportPage />);
    expect(screen.queryByRole('link', { name: /whatsapp/i })).toBeNull();
  });

  it('points at the answers that need no reply', () => {
    render(<SupportPage />);
    for (const path of [
      '/suppression-compte',
      '/politique-confidentialite',
      '/cgu',
    ]) {
      expect(
        screen.getAllByRole('link').some((a) => a.getAttribute('href') === path),
      ).toBe(true);
    }
  });

  it('the address is not the send-only sender', () => {
    // `no-reply@myweli.com` is the transactional sender and is not read by
    // anyone. Offering it as a contact is worse than offering none, because a
    // user believes they have been heard.
    expect(SUPPORT.email).not.toContain('no-reply');
    expect(SUPPORT.email).toMatch(/^[^@\s]+@myweli\.com$/);
  });
});
