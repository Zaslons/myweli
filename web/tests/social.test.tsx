import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { SiteFooter } from '../components/SiteFooter';
import { organizationJsonLd } from '../lib/seo/jsonld';
import { SOCIAL_PROFILES } from '../lib/social';

/// The brand's social profiles, held to one list.
///
/// Two consumers make the same claim in two languages — `sameAs` to machines,
/// a footer link to people — and the failure mode is that one of them drifts or
/// picks up a share token. Both are silent: a `?igsi=` in `sameAs` still
/// validates as JSON-LD, and a footer link to last month's URL still renders.
///
/// `globals` is off in `vitest.config.ts`, so RTL's auto-cleanup never runs and
/// renders stack in one document (see `legal.test.tsx`).
afterEach(cleanup);

describe('social profiles', () => {
  /// Vacuity guard. Every assertion below iterates the list, so an empty list
  /// passes all of them — the shape of "a check that cannot fire".
  it('declares at least one profile', () => {
    expect(SOCIAL_PROFILES.length).toBeGreaterThan(0);
  });

  it.each(SOCIAL_PROFILES.map((p) => [p.name, p.url]))(
    '%s is a canonical https URL with no tracking parameter',
    (_name, url) => {
      const parsed = new URL(url);
      expect(parsed.protocol).toBe('https:');
      // `?igsi=…` is what Instagram's share sheet appends. It identifies the
      // share, not the profile, so it must never reach either consumer.
      expect(parsed.search).toBe('');
      expect(parsed.hash).toBe('');
    },
  );

  it('sameAs declares exactly the profiles, in order', () => {
    expect(organizationJsonLd().sameAs).toEqual(
      SOCIAL_PROFILES.map((p) => p.url),
    );
  });

  it('the footer links every declared profile, and nothing else', () => {
    render(<SiteFooter />);
    const nav = screen.getByRole('navigation', { name: 'Réseaux sociaux' });
    const links = [...nav.querySelectorAll('a')];
    expect(links.map((a) => a.getAttribute('href'))).toEqual(
      SOCIAL_PROFILES.map((p) => p.url),
    );
    expect(links.map((a) => a.textContent)).toEqual(
      SOCIAL_PROFILES.map((p) => p.name),
    );
    // The microformat half of the same claim.
    for (const a of links) {
      expect(a.getAttribute('rel')).toContain('me');
    }
  });
});
