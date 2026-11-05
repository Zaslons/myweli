import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { CARD_SIZES, ProviderCard } from '../components/provider/ProviderCard';
import type { Provider } from '../lib/api/providers';
import { providerFixture } from './fixtures';

const norm = (s: string | null) => (s ?? '').replace(/\s/g, ' ');

afterEach(cleanup);

describe('ProviderCard', () => {
  it('shows name, rating, price-from and links to the provider', () => {
    const { container } = render(<ProviderCard provider={providerFixture} />);
    expect(screen.getByText('Beauté Divine')).toBeInTheDocument();
    expect(container.querySelector('a')?.getAttribute('href')).toBe(
      '/beaute-divine',
    );
    expect(norm(container.textContent)).toContain('à partir de 15 000 FCFA');
  });
});

it('shows the « Vérifié » badge only for verified salons (T52/15.1)', () => {
  const { rerender } = render(
    <ProviderCard provider={{ ...providerFixture, verified: true }} />,
  );
  expect(screen.getByLabelText('Salon vérifié')).toBeInTheDocument();
  rerender(<ProviderCard provider={{ ...providerFixture, verified: false }} />);
  expect(screen.queryByLabelText('Salon vérifié')).toBeNull();
});

it('a salon with no review shows « Nouveau », a reviewed one its rating (salon-rating-new-and-visits-card.md)', () => {
  const { container, rerender } = render(
    <ProviderCard provider={{ ...providerFixture, rating: 0, reviewCount: 0 }} />,
  );
  expect(screen.getByText('Nouveau')).toBeInTheDocument();
  expect(container.textContent).not.toMatch(/0,0/);
  rerender(
    <ProviderCard provider={{ ...providerFixture, rating: 4.8, reviewCount: 32 }} />,
  );
  expect(screen.queryByText('Nouveau')).toBeNull();
  expect(container.textContent).toMatch(/★ 4,8/);
});

/// docs/design/web-swiss-cards.md §2.2, §2.4 and §8: what the card promises and a
/// unit test can see. What it looks like in a browser is tests/e2e/site-look.spec.ts.
const PHOTO = 'https://cdn.stub/p1.jpg';
const LOGO = 'https://cdn.stub/logo.png';
const photoAndLogo: Provider = { ...providerFixture, imageUrls: [PHOTO], logoUrl: LOGO };
const logoOnly: Provider = { ...providerFixture, imageUrls: [], logoUrl: LOGO };
const nothing: Provider = { ...providerFixture, imageUrls: [], logoUrl: null };
const heart = { favorite: false, onToggleFavorite: vi.fn() };

/// The letter: the only `aria-hidden` element in a card that holds text.
const letterOf = (container: HTMLElement) =>
  [...container.querySelectorAll('[aria-hidden="true"]')].filter(
    (el) => el.tagName === 'SPAN' && el.classList.contains('absolute'),
  );

describe('the three media forms, one at a time', () => {
  it('a photo wins over a logo: one image, the salon’s name as its alt', () => {
    render(<ProviderCard provider={photoAndLogo} />);
    const images = screen.getAllByRole('img');
    expect(images).toHaveLength(1);
    expect(images[0]).toHaveAttribute('alt', 'Beauté Divine');
    expect(images[0].getAttribute('src')).toContain(encodeURIComponent(PHOTO));
  });

  it('a photo’s letter is hidden from readers, comes before the image and matches it', () => {
    const { container } = render(<ProviderCard provider={photoAndLogo} />);
    const letters = letterOf(container);
    expect(letters).toHaveLength(1);
    expect(letters[0]).toHaveTextContent('B');
    const img = container.querySelector('img')!;
    expect(img.getAttribute('data-initial')).toBe(letters[0].textContent);
    // Before it in the DOM, so a loaded photo covers it whole.
    expect(letters[0].compareDocumentPosition(img) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('no photo: the logo, « Logo {name} », with no letter', () => {
    const { container } = render(<ProviderCard provider={logoOnly} />);
    const images = screen.getAllByRole('img');
    expect(images).toHaveLength(1);
    expect(images[0]).toHaveAttribute('alt', 'Logo Beauté Divine');
    expect(images[0].getAttribute('src')).toContain(encodeURIComponent(LOGO));
    expect(letterOf(container)).toHaveLength(0);
  });

  it('neither: the letter alone, and no image', () => {
    const { container } = render(<ProviderCard provider={nothing} />);
    expect(container.querySelector('img')).toBeNull();
    const letters = letterOf(container);
    expect(letters).toHaveLength(1);
    expect(letters[0]).toHaveTextContent('B');
  });

  it('an unnamed salon: « Salon » as the alt and the heart’s label, and « S »', () => {
    const { container } = render(
      <ProviderCard provider={{ ...photoAndLogo, name: '   ' }} {...heart} />,
    );
    const img = container.querySelector('img')!;
    expect(img).toHaveAttribute('alt', 'Salon');
    expect(img).toHaveAttribute('data-initial', 'S');
    expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('Salon');
    expect(screen.getByRole('button', { name: 'Ajouter Salon aux favoris' })).toBeInTheDocument();
  });

  // `next dev` throws on an `asset:` seed (`image-loader.js:48-53`).
  it.each([
    ['an asset: seed', 'asset:mock/salon.png'],
    ['an empty string', ''],
  ])('%s reads as no photo, and as no logo', (_what, value) => {
    const { container, rerender } = render(
      <ProviderCard provider={{ ...nothing, imageUrls: [value] }} />,
    );
    expect(container.querySelector('img')).toBeNull();
    expect(letterOf(container)).toHaveLength(1);
    rerender(<ProviderCard provider={{ ...nothing, logoUrl: value }} />);
    expect(container.querySelector('img')).toBeNull();
  });

  it('a favourite’s salon with no gallery at all does not throw: lib/api/account.ts validates only id and name', () => {
    const bare = { id: 'p9', name: 'Awa', slug: 'awa' } as unknown as Provider;
    const { container } = render(<ProviderCard provider={bare} />);
    expect(container.querySelector('img')).toBeNull();
    expect(letterOf(container)[0]).toHaveTextContent('A');
  });
});

describe('no box, no pattern', () => {
  it('the link has no corners, no border and no fill', () => {
    const { container } = render(<ProviderCard provider={photoAndLogo} />);
    const link = container.querySelector('a')!;
    expect(link.className).not.toMatch(/rounded-/);
    expect(link.className).not.toMatch(/(^|\s)border(\s|$)/);
    expect(link.className).not.toContain('bg-secondary');
  });

  it.each([
    ['photo', photoAndLogo],
    ['logo', logoOnly],
    ['neither', nothing],
  ])('no weave on the card, %s (direction §6.4)', (_what, provider) => {
    const { container } = render(<ProviderCard provider={provider} />);
    expect(container.querySelector('svg[data-weave]')).toBeNull();
  });
});

describe('the photo’s files', () => {
  const sizesOf = (el: HTMLElement) => el.querySelector('img')!.getAttribute('sizes');

  it('each layout has its own default `sizes`, and a caller can name another', () => {
    const { container, rerender } = render(<ProviderCard provider={photoAndLogo} />);
    expect(sizesOf(container)).toBe(CARD_SIZES.site);
    rerender(<ProviderCard provider={photoAndLogo} layout="rowOnPhone" />);
    expect(sizesOf(container)).toBe(CARD_SIZES.site);
    rerender(<ProviderCard provider={photoAndLogo} layout="row" />);
    expect(sizesOf(container)).toBe(CARD_SIZES.row);
    rerender(<ProviderCard provider={photoAndLogo} imageSizes={CARD_SIZES.account} />);
    expect(sizesOf(container)).toBe(CARD_SIZES.account);
  });

  // The trap in §2.2: Next keeps only the candidates at or above `640 × the smallest
  // vw` it finds in `sizes`, so `…, 92vw` here would make a 119-wide row download 640w.
  it('the favourites’ `sizes` keeps a file small enough for a phone’s row', () => {
    const { container } = render(
      <ProviderCard provider={photoAndLogo} layout="rowOnPhone" imageSizes={CARD_SIZES.account} />,
    );
    const widths = container
      .querySelector('img')!
      .getAttribute('srcset')!
      .split(',')
      .map((c) => parseInt(c.trim().split(/\s+/)[1], 10));
    expect(Math.min(...widths)).toBeLessThanOrEqual(256);
  });

  it('lazy by default; `imagePriority` is a high fetch priority with no `loading`', () => {
    const { container, rerender } = render(<ProviderCard provider={photoAndLogo} />);
    const img = () => container.querySelector('img')!;
    expect(img()).toHaveAttribute('loading', 'lazy');
    expect(img().getAttribute('fetchpriority')).not.toBe('high');
    rerender(<ProviderCard provider={photoAndLogo} imagePriority />);
    expect(img().getAttribute('fetchpriority')).toBe('high');
    expect(img().hasAttribute('loading')).toBe(false);
  });
});

describe('the text', () => {
  it('the heart’s spacer exists only with a heart, as tall as the heart', () => {
    const spacer = (el: HTMLElement) => el.querySelector('span.shrink-0[aria-hidden="true"]');
    const { container, rerender } = render(<ProviderCard provider={photoAndLogo} />);
    expect(spacer(container)).toBeNull();
    rerender(<ProviderCard provider={photoAndLogo} {...heart} />);
    expect(spacer(container)).toHaveClass('h-12', 'w-12');
    expect(container.querySelector('button')).toHaveClass('h-12', 'w-12');
  });

  it('nothing is clipped, and the name and its mark are one inline run', () => {
    const { container } = render(
      <ProviderCard provider={{ ...photoAndLogo, verified: true }} {...heart} />,
    );
    expect(container.innerHTML).not.toMatch(/\btruncate\b|whitespace-nowrap/);
    const h3 = screen.getByRole('heading', { level: 3 });
    expect(h3.className).not.toMatch(/\bflex\b/);
    expect(h3.textContent).toBe('Beauté Divine ✔︎');
  });

  it('« (32 avis) » with reviews, « Nouveau » without', () => {
    const { container, rerender } = render(
      <ProviderCard provider={{ ...photoAndLogo, rating: 4.8, reviewCount: 32 }} />,
    );
    expect(container.textContent).toContain('★ 4,8 (32 avis)');
    rerender(<ProviderCard provider={{ ...photoAndLogo, rating: 0, reviewCount: 0 }} />);
    expect(screen.getByText('Nouveau')).toBeInTheDocument();
    expect(container.textContent).not.toContain('avis)');
  });
});

describe('`linked`', () => {
  it('the default is a link to the salon, with a name that answers hover and focus', () => {
    const { container } = render(<ProviderCard provider={photoAndLogo} />);
    expect(container.querySelector('a')).toHaveAttribute('href', '/beaute-divine');
    expect(container.innerHTML).toContain('group-hover:underline');
    expect(container.innerHTML).toContain('group-focus-visible:underline');
  });

  it('false: the same card with no link and no hover, for a salon that stopped', () => {
    const { container } = render(<ProviderCard provider={photoAndLogo} linked={false} />);
    expect(container.querySelector('a')).toBeNull();
    expect(container.innerHTML).not.toContain('group-hover');
    expect(container.innerHTML).not.toContain('group-focus-visible');
    expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('Beauté Divine');
    expect(container.querySelector('img')).toHaveAttribute('alt', 'Beauté Divine');
  });
});
