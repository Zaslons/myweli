import { cleanup, render } from '@testing-library/react';
import { afterEach, expect, it } from 'vitest';
import { ProviderHero } from '../components/provider/Hero';
import { providerFixture } from './fixtures';

/// The salon page's cover is cut where the card's photo is, a little above the centre, and
/// the logo over it is not moved (docs/design/web-swiss-cards.md §11, decision 8). What the
/// browser computes from these classes is tests/e2e/site-look.spec.ts.
afterEach(cleanup);

it('the cover takes `object-subject`, and the logo over it does not', () => {
  const { container } = render(
    <ProviderHero provider={{ ...providerFixture, logoUrl: 'https://cdn.example/logo.png' }} />,
  );
  const [cover, logo] = [...container.querySelectorAll('img')];
  expect(cover).toHaveAttribute('alt', `Salon ${providerFixture.name}`);
  expect(cover.className.split(' ')).toContain('object-subject');
  expect(logo).toHaveAttribute('alt', `Logo ${providerFixture.name}`);
  expect(logo.className.split(' ')).not.toContain('object-subject');
});
