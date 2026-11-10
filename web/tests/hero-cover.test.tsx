import { cleanup, render } from '@testing-library/react';
import { afterEach, expect, it } from 'vitest';
import { ProviderCover } from '../components/provider/Hero';
import { COVER_SIZES } from '../components/provider/ProviderView';
import { providerFixture } from './fixtures';

/// The salon page's cover is 3:2 at every width, cut where the card's photo is, a little
/// above the centre, and the logo over it is neither reshaped nor moved
/// (docs/design/web-swiss-salon.md §1.6; web-swiss-cards.md §11, decision 8). What the
/// browser computes from these classes is tests/e2e/site-look.spec.ts.
afterEach(cleanup);

const withLogo = { ...providerFixture, logoUrl: 'https://cdn.example/logo.png' };

it('the cover’s box is the 3:2 token, the cover takes `object-subject`, and the logo neither', () => {
  const { container } = render(<ProviderCover provider={withLogo} sizes={COVER_SIZES} />);
  const [cover, logo] = [...container.querySelectorAll('img')];
  expect(cover).toHaveAttribute('alt', `Salon ${providerFixture.name}`);
  expect(cover.parentElement!.className.split(' ')).toContain('aspect-cover');
  expect(cover.className.split(' ')).toContain('object-subject');
  expect(logo).toHaveAttribute('alt', `Logo ${providerFixture.name}`);
  expect(logo.className.split(' ')).not.toContain('object-subject');
  // The logo's own box is the 64px ring, not a second cover.
  expect(logo.parentElement!.className.split(' ')).not.toContain('aspect-cover');
});

it('no photo, no cover: nothing is drawn, the logo included', () => {
  const { container } = render(
    <ProviderCover provider={{ ...withLogo, imageUrls: [] }} sizes={COVER_SIZES} />,
  );
  expect(container).toBeEmptyDOMElement();
});
