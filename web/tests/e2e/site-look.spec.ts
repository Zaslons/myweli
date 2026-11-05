import { expect, test, type Locator, type Page } from '@playwright/test';

import { signInConsumer } from './_auth';
import { PHOTO, PHOTO_COLOUR, paintedIn, routeNextImages } from './_pixel';

/// B11.1 — docs/design/web-swiss-direction.md §12. What the new look promises and
/// a unit test cannot see, because each of these is a fact about the rendered box:
/// one left edge, a panel that meets its rules, a logo that is never cut.
///
/// **What this cannot see:** whether it looks right. WEB-SYSTEM §9 says it plainly,
/// so each PR carries pictures, and they get looked at.

const size = (page: Page, width: number, height = 900) => page.setViewportSize({ width, height });
const box = async (page: Page, selector: string) => {
  const b = await page.locator(selector).first().boundingBox();
  expect(b, `no box for ${selector}`).not.toBeNull();
  return b!;
};

const logoLeft = async (page: Page) =>
  (await page.getByRole('banner').getByRole('img', { name: 'MyWeli' }).boundingBox())!.x;

test.describe('one left edge (§6.2)', () => {
  // 1536 and 1920 are where a centred container and a full-width one part ways.
  for (const width of [320, 375, 768, 1024, 1280, 1536, 1920]) {
    test(`/ at ${width}: the logo, the <h1> and the first section`, async ({ page }) => {
      await size(page, width);
      await page.goto('/');
      const logo = await logoLeft(page);
      const h1 = (await page.getByRole('heading', { level: 1 }).boundingBox())!.x;
      const section = (await page.getByRole('heading', { name: 'Catégories' }).boundingBox())!.x;
      expect(h1).toBeCloseTo(logo, 0);
      expect(section).toBeCloseTo(logo, 0);
    });

    test(`/professionnels at ${width}: the logo, the <h1> and the first section`, async ({ page }) => {
      await size(page, width);
      await page.goto('/professionnels');
      const logo = await logoLeft(page);
      const h1 = (await page.getByRole('heading', { level: 1 }).boundingBox())!.x;
      const section = (await page.getByRole('heading', { name: 'Tout ce qu’il faut pour votre salon' }).boundingBox())!.x;
      expect(h1).toBeCloseTo(logo, 0);
      expect(section).toBeCloseTo(logo, 0);
    });

    test(`the 404 at ${width}: the logo and the <h1>`, async ({ page }) => {
      await size(page, width);
      await page.goto('/page-qui-nexiste-pas');
      const h1 = page.getByRole('heading', { level: 1, name: 'Page introuvable' });
      expect((await h1.boundingBox())!.x).toBeCloseTo(await logoLeft(page), 0);
      expect(await h1.evaluate((el) => getComputedStyle(el).textAlign)).not.toBe('center');
    });

    test(`/recherche at ${width}: the logo and the list`, async ({ page }) => {
      await size(page, width);
      await page.goto('/recherche?commune=Cocody');
      const h1 = page.getByRole('heading', { level: 1 });
      await expect(h1).toBeVisible();
      expect((await h1.boundingBox())!.x).toBeCloseTo(await logoLeft(page), 0);
    });

    for (const path of ['/coiffure', '/coiffure/abidjan', '/coiffure/abidjan/cocody', '/coiffure/abidjan/plateau']) {
      test(`${path} at ${width}: the logo, the <h1> and the first section`, async ({ page }) => {
        await size(page, width);
        await page.goto(path);
        const logo = await logoLeft(page);
        expect((await page.getByRole('heading', { level: 1 }).boundingBox())!.x).toBeCloseTo(logo, 0);
        expect((await page.getByRole('heading', { level: 2 }).first().boundingBox())!.x).toBeCloseTo(logo, 0);
        if (path.endsWith('/plateau')) {
          // Nobody has a salon there, so this is the empty state. Flush left, with no box.
          const empty = page.getByText('Aucun salon de coiffure à Plateau pour le moment');
          expect((await empty.boundingBox())!.x).toBeCloseTo(logo, 0);
          expect(await empty.evaluate((el) => getComputedStyle(el).textAlign)).not.toBe('center');
        }
      });
    }
  }
});

test.describe('the pattern (§4.6)', () => {
  test('the home page shows exactly one: the band on a phone, the panel from lg', async ({ page }) => {
    await size(page, 375);
    await page.goto('/');
    await expect(page.locator('svg[data-weave]:visible')).toHaveCount(1);
    await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'band');
    await size(page, 1023);
    await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'band');
    await size(page, 1024);
    await expect(page.locator('svg[data-weave]:visible')).toHaveCount(1);
    await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'panel');
  });

  test('/professionnels shows exactly one too, and the 404 only ever the band', async ({ page }) => {
    await size(page, 375);
    await page.goto('/professionnels');
    await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'band');
    await size(page, 1024);
    await expect(page.locator('svg[data-weave]:visible')).toHaveCount(1);
    await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'panel');

    await page.goto('/page-qui-nexiste-pas');
    for (const width of [375, 1024, 1920]) {
      await size(page, width);
      await expect(page.locator('svg[data-weave]:visible')).toHaveCount(1);
      await expect(page.locator('svg[data-weave]:visible')).toHaveAttribute('data-weave', 'band');
    }
  });

  // §4.3 rule 4: « Fine, not chunky ». A phone-width band scaled up to a tablet
  // was 220 high with strokes like a road marking, and no other check could see it.
  test('the band stops growing past a phone, and fills one', async ({ page }) => {
    await size(page, 375);
    await page.goto('/');
    const phone = (await page.locator('svg[data-weave=band]').boundingBox())!;
    expect(phone.x).toBeCloseTo(16, 0);
    expect(phone.width).toBeCloseTo(375 - 32, 0);
    await size(page, 1023);
    const tablet = (await page.locator('svg[data-weave=band]').boundingBox())!;
    expect(tablet.width).toBeLessThanOrEqual(512);
  });

  test('what a visitor is sent stays under 4 KB, and hidden from a screen reader', async ({ page }) => {
    await page.goto('/');
    const { bytes, count, exposed } = await page.evaluate(() => {
      const all = [...document.querySelectorAll('svg[data-weave]')];
      return {
        count: all.length,
        bytes: all.reduce((sum, el) => sum + new Blob([el.outerHTML]).size, 0),
        exposed: all.filter((el) => el.getAttribute('aria-hidden') !== 'true').length,
      };
    });
    expect(count).toBe(2);
    expect(exposed).toBe(0);
    expect(bytes).toBeLessThanOrEqual(4096);
  });

  for (const path of [
    '/recherche?commune=Cocody',
    '/coiffure',
    '/coiffure/abidjan',
    '/coiffure/abidjan/cocody',
    '/beaute-divine',
    '/connexion',
    '/mon-compte',
    '/pro/connexion',
    '/pro/inscription',
    '/politique-confidentialite',
    '/support',
  ]) {
    test(`none on ${path}: the page's job is something else`, async ({ page }) => {
      await page.goto(path);
      await expect(page.getByRole('contentinfo')).toBeVisible();
      await expect(page.locator('svg[data-weave]')).toHaveCount(0);
    });
  }

  // The list above reads `/mon-compte` signed out, so it reaches the redirect.
  test('none on the account signed in, with a favourite on it', async ({ page }) => {
    await signInConsumer(page);
    await expect(page.getByRole('button', { name: 'Retirer des favoris' }).first()).toBeVisible();
    await expect(page.locator('svg[data-weave]')).toHaveCount(0);
  });
});

test.describe('the panel (§4.5)', () => {
  for (const [path, nextHeading, action] of [
    ['/', 'Catégories', 'main form'],
    ['/professionnels', 'Tout ce qu’il faut pour votre salon', 'main a[href="/pro/connexion"]'],
  ]) {
    for (const width of [1024, 1280, 1440, 1536, 1920, 2560]) {
      test(`${path} at ${width}: meets its rules and the container's edge, and the logo is never cut`, async ({ page }) => {
        await size(page, width);
        await page.goto(path);
        const panel = page.locator('[data-weave-panel]');
        const p = (await panel.boundingBox())!;

        const account = (await page.getByRole('banner').getByRole('link', { name: 'Mon compte', exact: true }).boundingBox())!;
        expect(p.x + p.width, 'the rows end where the header does').toBeCloseTo(account.x + account.width, 0);
        const header = await box(page, 'header');
        expect(p.y).toBeCloseTo(header.y + header.height, 0);
        const next = page.getByRole('heading', { name: nextHeading }).locator('xpath=ancestor::section[1]');
        expect((await next.boundingBox())!.y).toBeCloseTo(p.y + p.height, 0);

        const mark = (await page.locator('svg[data-weave=panel] svg').boundingBox())!;
        expect(mark.y + mark.height, 'the cloth is cut at the bottom, never through the logo').toBeLessThanOrEqual(
          p.y + p.height,
        );
        expect(mark.x + mark.width).toBeLessThanOrEqual(p.x + p.width);

        // Never behind text.
        for (const text of [page.getByRole('heading', { level: 1 }), page.locator(action).first()]) {
          const t = (await text.boundingBox())!;
          expect(t.x + t.width, 'text runs into the panel').toBeLessThanOrEqual(p.x);
        }
      });
    }
  }
});

test.describe('/professionnels (§7.2)', () => {
  test('one filled action per screen, in the hero, on a phone and a desktop', async ({ page }) => {
    for (const width of [375, 1280]) {
      await size(page, width);
      await page.goto('/professionnels');
      const filled = await page.locator('main a').evaluateAll((links) =>
        links
          .filter((a) => getComputedStyle(a).backgroundColor === 'rgb(0, 0, 0)')
          .map((a) => a.textContent?.trim()),
      );
      expect(filled).toEqual(['Inscrire mon salon']);
    }
  });

  test('the filled action is on screen without scrolling at 360 × 640', async ({ page }) => {
    await size(page, 360, 640);
    await page.goto('/professionnels');
    const action = (await page.getByRole('link', { name: 'Inscrire mon salon' }).first().boundingBox())!;
    expect(action.y + action.height).toBeLessThanOrEqual(640);
  });

  test('the steps have large numerals, not discs, in order, and hidden from a screen reader', async ({ page }) => {
    await size(page, 1280);
    await page.goto('/professionnels');
    const numerals = await page
      .getByRole('heading', { name: 'Comment ça marche' })
      .locator('xpath=ancestor::section[1]')
      .locator('ol li > span[aria-hidden="true"]')
      .evaluateAll((all) =>
        all.map((n) => {
          const s = getComputedStyle(n);
          return [n.textContent, parseFloat(s.fontSize) >= 36, s.borderTopLeftRadius, s.backgroundColor];
        }),
      );
    expect(numerals).toEqual([
      ['1', true, '0px', 'rgba(0, 0, 0, 0)'],
      ['2', true, '0px', 'rgba(0, 0, 0, 0)'],
      ['3', true, '0px', 'rgba(0, 0, 0, 0)'],
    ]);
  });

  test('what search engines read has not moved (§14)', async ({ page }) => {
    await page.goto('/professionnels');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(
      'Le logiciel de réservation des salons de beauté en Côte d’Ivoire',
    );
    await expect(page).toHaveTitle(
      'MyWeli Pro — logiciel de réservation pour salons de beauté en Côte d’Ivoire · MyWeli',
    );
    await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', /\/professionnels$/);
    const types = await page.locator('script[type="application/ld+json"]').evaluateAll((all) =>
      all.map((s) => JSON.parse(s.textContent as string)['@type']).sort(),
    );
    expect(types).toEqual(['FAQPage', 'Organization']);
    await expect(page.getByRole('heading', { level: 2 })).toHaveText([
      'Tout ce qu’il faut pour votre salon',
      'Comment ça marche',
      'Questions fréquentes',
      'Prêt à recevoir vos premières réservations ?',
    ]);
  });
});

test.describe('the hero on a phone', () => {
  test('the search is visible without scrolling at 360 × 640 (§7.1)', async ({ page }) => {
    await size(page, 360, 640);
    await page.goto('/');
    const button = (await page.getByRole('button', { name: 'Rechercher' }).boundingBox())!;
    expect(button.y + button.height).toBeLessThanOrEqual(640);
  });

  // Across widths, because it cannot break at 320: the second line is too short for
  // that. It breaks where a balanced heading wants a split in the middle, about 768.
  test('« bien-être » never breaks at its hyphen', async ({ page }) => {
    await page.goto('/');
    const word = page.getByRole('heading', { level: 1 }).locator('span', { hasText: 'bien-être' });
    for (const width of [320, 375, 640, 768, 900, 1024, 1280, 1440, 1920]) {
      await size(page, width);
      const lines = await word.evaluate((el) => new Set([...el.getClientRects()].map((r) => Math.round(r.top))).size);
      expect(lines, `at ${width}`).toBe(1);
    }
  });

  // The stub's city is Abidjan, so the longer name is put into the page: this asks
  // whether the layout holds it, which is what a Yamoussoukro launch needs to know.
  for (const width of [320, 375, 1024, 1280]) {
    test(`a long city name fits at ${width}`, async ({ page }) => {
      await size(page, width);
      await page.goto('/');
      const fits = await page.getByRole('heading', { level: 1 }).evaluate((h1) => {
        const last = [...h1.childNodes].reverse().find((n) => n.textContent?.includes('Abidjan'));
        if (!last) return 'no city in the heading';
        last.textContent = (last.textContent as string).replace('Abidjan', 'Yamoussoukro');
        const page_ = document.documentElement;
        return h1.scrollWidth <= h1.clientWidth && page_.scrollWidth <= page_.clientWidth ? 'fits' : 'spills';
      });
      expect(fits).toBe('fits');
    });
  }
});

test.describe('the directory (§7.1)', () => {
  const LINK = { name: 'Coiffure à Cocody' };

  test('a phone gets one closed disclosure per commune, and its links open with it', async ({ page }) => {
    await size(page, 375);
    await page.goto('/');
    await expect(page.getByRole('link', LINK)).toHaveCount(0);
    const cocody = page.locator('details', { hasText: 'Cocody' });
    await expect(cocody).not.toHaveAttribute('open', /.*/);
    await cocody.locator('summary').click();
    await expect(cocody.getByRole('link', LINK)).toBeVisible();
  });

  test('from lg every link is open, with no disclosure to press', async ({ page }) => {
    await size(page, 1280);
    await page.goto('/');
    await expect(page.locator('details:visible')).toHaveCount(0);
    await expect(page.getByRole('link', LINK)).toBeVisible();
  });

  test('the links stay in the served HTML, for search engines', async ({ request }) => {
    const html = await (await request.get('/')).text();
    expect(html).toContain('href="/coiffure/abidjan/cocody"');
  });
});

test.describe('the logo (§3)', () => {
  const WORDMARK = 'footer svg[data-wordmark]';

  for (const path of ['/', '/connexion', '/professionnels', '/politique-confidentialite']) {
    test(`${path}: the real lockup above, the large wordmark below`, async ({ page }) => {
      await page.goto(path);
      const loaded = await page
        .locator('header img[src="/brand/myweli_lockup_horizontal_black.svg"]')
        .evaluate(async (img: HTMLImageElement) => {
          await img.decode();
          return img.naturalWidth;
        });
      expect(loaded).toBeGreaterThan(0);
      await expect(page.locator(WORDMARK)).toBeVisible();
    });
  }

  test('/pro/connexion: the footer carries the lockup, not a poster under a form', async ({ page }) => {
    await page.goto('/pro/connexion');
    await expect(page.locator(WORDMARK)).toHaveCount(0);
    await expect(page.locator('footer img[src="/brand/myweli_lockup_horizontal_black.svg"]')).toBeVisible();
  });

  test('the wordmark takes 7 of 12 columns from lg, and the full width on a phone', async ({ page }) => {
    await size(page, 1440);
    await page.goto('/');
    const wide = (await page.locator(WORDMARK).boundingBox())!;
    expect(wide.width / 1440).toBeGreaterThan(0.5);
    expect(wide.width / 1440).toBeLessThan(0.62);
    await size(page, 375);
    const narrow = (await page.locator(WORDMARK).boundingBox())!;
    expect(narrow.width).toBeCloseTo(375 - 2 * 16, 0);
  });

  // The file's viewBox has space left of the M, which drawn large showed as an M
  // 19px right of the text below it. That the viewBox starts on the ink is pinned
  // against the file in tests/weave.test.tsx; this is where it lands on the page.
  for (const width of [375, 1440, 1920]) {
    test(`at ${width} the wordmark starts on the left edge`, async ({ page }) => {
      await size(page, width);
      await page.goto('/');
      const mark = (await page.locator(WORDMARK).boundingBox())!;
      const text = (await page.getByRole('contentinfo').getByText('MyWeli — réservation').boundingBox())!;
      expect(mark.x).toBeCloseTo(text.x, 0);
    });
  }

  test('/pro/connexion: its two logos share one left edge', async ({ page }) => {
    await size(page, 1920);
    await page.goto('/pro/connexion');
    const above = (await page.locator('header img').boundingBox())!;
    const below = (await page.locator('footer img').boundingBox())!;
    expect(above.x).toBeCloseTo(below.x, 0);
  });

  // Found by measuring: as an `<img>` the wordmark became the Largest Contentful
  // Paint under a short page, at Lighthouse's own 412 × 823. A decoration must not
  // decide a page's speed. Short pages are the ones at risk, so they are the list.
  for (const [width, height] of [
    [412, 823],
    [1440, 900],
  ]) {
    for (const path of ['/connexion', '/suppression-compte', '/mon-compte', '/support', '/coiffure/abidjan/cocody']) {
      test(`${path} at ${width}: nothing in the footer is the page's largest paint`, async ({ page }) => {
        await size(page, width, height);
        await page.addInitScript(() => {
          const seen: string[] = [];
          (window as unknown as { __lcp: string[] }).__lcp = seen;
          new PerformanceObserver((list) => {
            for (const entry of list.getEntries() as (PerformanceEntry & { element?: Element })[]) {
              seen.push(entry.element?.closest('footer') ? 'footer' : 'page');
            }
          }).observe({ type: 'largest-contentful-paint', buffered: true });
        });
        await page.goto(path);
        await expect(page.getByRole('contentinfo')).toBeVisible();
        await page.waitForLoadState('networkidle');
        const seen = await page.evaluate(() => (window as unknown as { __lcp: string[] }).__lcp);
        expect(seen.length, 'the observer saw nothing, so this proves nothing').toBeGreaterThan(0);
        // The last entry is the one reported. `/mon-compte` starts as a spinner, so
        // the footer's text is briefly the largest thing there, and that is fine.
        expect(seen.at(-1)).toBe('page');
      });
    }
  }
});

test.describe('rules instead of boxes (§6.3)', () => {
  test('black under the header, between sections and above the footer', async ({ page }) => {
    await page.goto('/');
    const rule = (selector: string, side: 'Top' | 'Bottom') =>
      page.locator(selector).first().evaluate((el, s) => {
        const css = getComputedStyle(el);
        return [css.getPropertyValue(`border-${s.toLowerCase()}-color`), css.getPropertyValue(`border-${s.toLowerCase()}-width`)];
      }, side);
    expect(await rule('header', 'Bottom')).toEqual(['rgb(0, 0, 0)', '1px']);
    expect(await rule('footer', 'Top')).toEqual(['rgb(0, 0, 0)', '1px']);
    const sections = page.locator('main > section').nth(1);
    expect(await sections.evaluate((el) => getComputedStyle(el).borderTopColor)).toBe('rgb(0, 0, 0)');
  });

  // Rooted on `main`, not `main section`: `/recherche` has no `<section>`, so the old
  // check read nothing there (measured: 0). Chips keep their pill, and a map's pins and
  // controls belong to the map, as in controls-shape.spec.ts.
  for (const [path, hasCard] of [
    ['/', true],
    ['/professionnels', false],
    ['/coiffure', true],
    ['/coiffure/abidjan', true],
    ['/coiffure/abidjan/cocody', true],
    ['/coiffure/abidjan/marcory', true],
    ['/recherche?q=vitrine', true],
  ] as const) {
    test(`no box is left on ${path}`, async ({ page }) => {
      await routeNextImages(page);
      await page.goto(path);
      if (hasCard) await expect(page.locator('main a img').first()).toBeAttached();
      const boxed = await page.locator('main').evaluateAll((all) =>
        all.flatMap((s) =>
          [s, ...s.querySelectorAll('div, li, a')]
            .filter((el) => !el.classList.contains('rounded-pill'))
            .filter((el) => el.closest('.maplibregl-map, .myweli-marker') === null)
            .filter((el) => {
              const css = getComputedStyle(el);
              return parseFloat(css.borderTopLeftRadius) > 0 && parseFloat(css.borderLeftWidth) > 0;
            })
            .map((el) => el.outerHTML.slice(0, 80)),
        ),
      );
      expect(boxed).toEqual([]);
    });
  }
});

/// A ruled index has no box to light up, so the pointer's one answer is the name's colour.
/// A child that sets its own colour stops the link's hover reaching it, and that reads as
/// a link that does nothing (web-swiss-cards.md §2.3).
test.describe('a ruled index answers the pointer', () => {
  for (const [path, name] of [
    ['/', /^Coiffure$/],
    ['/coiffure', /Coiffure à Abidjan/],
  ] as const) {
    test(`${path}: the name changes colour under the pointer`, async ({ page }) => {
      await page.goto(path);
      const link = page.locator('main').getByRole('link', { name }).first();
      // The first text in the link, wherever the link nests it.
      const colour = () =>
        link.evaluate((el) => {
          const text = document.createTreeWalker(el, NodeFilter.SHOW_TEXT).nextNode()!;
          return getComputedStyle(text.parentElement!).color;
        });
      const before = await colour();
      await link.hover();
      await expect.poll(colour).not.toBe(before);
    });
  }
});

/// B11.3 — docs/design/web-swiss-cards.md §8. A card is a salon's own photo, square and
/// uncovered, with flush-left text and one thin rule. The fixtures are in
/// card-fixtures.json: a fixture is a pixel, so whether it looks right is for the
/// pictures, and a real photo for the first public salon.
test.describe('the salon card', () => {
  /// The image's own box loses 1px to the rule, and reads 1.34–1.35, so the ratio is
  /// the media box's.
  const mediaOf = (img: Locator) => img.locator('..');
  const ratioOf = async (el: Locator) => {
    const b = (await el.boundingBox())!;
    return b.width / b.height;
  };
  /// What is on top at a point of a box. `elementFromPoint` needs it on screen.
  const topAt = async (box: Locator, at: 'centre' | 'bottom-left') => {
    await box.scrollIntoViewIfNeeded();
    return box.evaluate((el, where) => {
      const b = el.getBoundingClientRect();
      const [x, y] =
        where === 'centre' ? [b.x + b.width / 2, b.y + b.height / 2] : [b.x + 4, b.bottom - 6];
      return document.elementFromPoint(x, y)?.tagName;
    }, at);
  };
  // Inset by 2px: a box on a fractional x paints the page's colour in its first column,
  // and the bottom holds the rule. The corner is where Chromium's broken-image mark goes.
  const topLeft = () => ({ x: 2, y: 2, width: 30, height: 30 });
  const bottomLeft = ({ height }: { height: number }) => ({
    x: 2,
    y: height - 40,
    width: 38,
    height: 36,
  });

  for (const path of ['/recherche?q=vitrine', '/coiffure/abidjan/marcory']) {
    for (const width of [375, 1280]) {
      test(`${path} at ${width}: a photo at 4:3, with nothing on it`, async ({ page }) => {
        await size(page, width);
        await routeNextImages(page);
        await page.goto(path);
        const img = page.locator('main img[alt="Beauté Divine"]');
        const media = mediaOf(img);
        await expect(img).toBeVisible();
        expect(Math.abs((await ratioOf(media)) - 4 / 3)).toBeLessThanOrEqual(0.02);
        expect(
          await img.evaluate((el) => {
            const s = getComputedStyle(el);
            return [s.borderTopLeftRadius, s.filter, s.opacity, s.mixBlendMode];
          }),
        ).toEqual(['0px', 'none', '1', 'normal']);
        // A scrim on a pseudo-element is what `elementFromPoint` cannot see.
        for (const box of [media, img.locator('xpath=ancestor::a[1]')]) {
          expect(
            await box.evaluate((el) => [
              getComputedStyle(el, '::before').content,
              getComputedStyle(el, '::after').content,
            ]),
          ).toEqual(['none', 'none']);
        }
        expect(await topAt(media, 'centre')).toBe('IMG');
      });

      test(`${path} at ${width}: a failed photo is the salon's letter on the tile`, async ({ page }) => {
        await size(page, width);
        await routeNextImages(page);
        await page.goto(path);
        const img = page.locator('main img[alt="Atelier Prestige"]');
        const media = mediaOf(img);
        await img.scrollIntoViewIfNeeded();
        await expect
          .poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth === 0))
          .toBe(true);
        expect(Math.abs((await ratioOf(media)) - 4 / 3)).toBeLessThanOrEqual(0.02);
        expect((await paintedIn(media, topLeft)).colours).toEqual(['rgb(245,245,245)']);
        expect((await paintedIn(media, bottomLeft)).dark, 'no letter on the tile').toBeGreaterThan(0);
      });
    }
  }

  test('a slow photo holds its ratio and the letter, and paints over it with no shift', async ({ page }) => {
    await size(page, 390);
    let answer!: () => void;
    const released = new Promise<void>((r) => (answer = r));
    await page.route('**/_next/image**', async (r) => {
      await released;
      await r.fulfill({ status: 200, contentType: 'image/png', body: PHOTO });
    });
    // Not `load`: a photo held open holds that too.
    await page.goto('/recherche?q=vitrine', { waitUntil: 'domcontentloaded' });
    const img = page.locator('main img[alt="Beauté Divine"]');
    const media = mediaOf(img);
    await expect(img).toBeAttached();
    expect(await img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBe(0);
    expect(Math.abs((await ratioOf(media)) - 4 / 3)).toBeLessThanOrEqual(0.02);
    const before = (await media.boundingBox())!;
    expect((await paintedIn(media, bottomLeft)).dark, 'no letter while it loads').toBeGreaterThan(0);

    answer();
    await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
    expect(await topAt(media, 'bottom-left')).toBe('IMG');
    expect((await media.boundingBox())!).toEqual(before);
    // And in paint: a loaded photo covers the letter whole.
    expect((await paintedIn(media, bottomLeft)).colours).toEqual([PHOTO_COLOUR]);
  });

  test('neither a photo nor a logo: the letter, and a logo has none under it', async ({ page }) => {
    await size(page, 390);
    await routeNextImages(page);
    await page.goto('/recherche?q=vitrine');
    const row = (name: string) =>
      page.locator('main a').filter({ has: page.getByRole('heading', { level: 3, name }) });
    // `.absolute`: the heart's spacer beside the price is `aria-hidden` too.
    const letter = 'span.absolute[aria-hidden="true"]';
    await expect(row('Chez Awa').locator('img')).toHaveCount(0);
    await expect(row('Chez Awa').locator(letter)).toHaveText('C');
    await expect(row('Maison Nala').locator('img[alt="Logo Maison Nala"]')).toBeVisible();
    await expect(row('Maison Nala').locator(letter)).toHaveCount(0);
  });

  /// Every text rectangle in a row against its heart's box. Range rectangles, because an
  /// element's box can reach the heart with no text anywhere near it.
  const textUnderHearts = (page: Page) =>
    page.evaluate(() => {
      const met: string[] = [];
      const hearts = [...document.querySelectorAll('main button[aria-pressed]')];
      for (const heart of hearts) {
        const h = heart.getBoundingClientRect();
        const walker = document.createTreeWalker(heart.parentElement!, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (heart.contains(node) || !node.textContent?.trim()) continue;
          if (node.parentElement?.closest('.sr-only')) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          for (const r of range.getClientRects()) {
            const apart = r.right <= h.left || r.left >= h.right || r.bottom <= h.top || r.top >= h.bottom;
            if (!apart && r.width > 0) met.push(`${node.textContent.trim().slice(0, 30)} meets ${heart.getAttribute('aria-label')}`);
          }
        }
      }
      return { hearts: hearts.length, met };
    });
  // Against the width asked for, not `clientWidth`: with `isMobile` a page that spills
  // can have its layout viewport widened to fit, and the check would compare it to itself.
  const pageWidth = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth);

  for (const width of [320, 390]) {
    test(`at ${width} no text meets a heart, and the page does not scroll sideways`, async ({ page }) => {
      await size(page, width);
      await routeNextImages(page);
      await page.goto('/recherche?q=vitrine');
      await expect(page.getByRole('heading', { name: '8 salons' })).toBeVisible();
      const { hearts, met } = await textUnderHearts(page);
      expect(hearts, 'every fixture has its heart').toBe(8);
      expect(met).toEqual([]);
      expect(await pageWidth(page)).toBe(width);
    });
  }

  // Android's text scaling, which is what `text-size-adjust` does on a mobile page. iOS's
  // « aA » is page zoom, a 195-wide page, which is another question.
  test.describe('at 200% text', () => {
    test.use({ isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

    for (const width of [320, 390]) {
      test(`at ${width} no text meets a heart, and the page does not scroll sideways`, async ({ page }) => {
        await size(page, width, 800);
        await routeNextImages(page);
        await page.goto('/recherche?q=vitrine');
        await page.addStyleTag({
          content: 'html { -webkit-text-size-adjust: 200% !important; text-size-adjust: 200% !important; }',
        });
        // One short name, on one line: under 40 high, the text did not double, and
        // everything below would prove nothing.
        const one = page.locator('main h3').filter({ hasText: /^Salon$/ });
        await expect.poll(() => one.evaluate((el) => el.getBoundingClientRect().height)).toBeGreaterThanOrEqual(40);
        const { hearts, met } = await textUnderHearts(page);
        expect(hearts).toBe(8);
        expect(met).toEqual([]);
        expect(await pageWidth(page)).toBe(width);
      });

      // No price, so the commune sits in the heart's own band, and one word that cannot
      // wrap: nothing in `q=vitrine` is both.
      test(`at ${width} a commune too long for its column breaks, and stays off the heart`, async ({ page }) => {
        await size(page, width, 800);
        await routeNextImages(page);
        await page.goto('/recherche?q=commune-longue');
        await page.addStyleTag({
          content: 'html { -webkit-text-size-adjust: 200% !important; text-size-adjust: 200% !important; }',
        });
        const commune = page.locator('main p').filter({ hasText: /^Yamoussoukro$/ });
        const lines = () =>
          commune.evaluate((el) => {
            const range = document.createRange();
            range.selectNodeContents(el);
            return range.getClientRects().length;
          });
        await expect.poll(() => commune.evaluate((el) => parseFloat(getComputedStyle(el).fontSize))).toBeGreaterThanOrEqual(28);
        const { hearts, met } = await textUnderHearts(page);
        expect(hearts).toBe(1);
        expect(met).toEqual([]);
        expect(await lines(), 'one line: the word fits, and this proved nothing').toBeGreaterThanOrEqual(2);
        expect(await pageWidth(page)).toBe(width);
      });
    }
  });

  // §7's outcome, the owner's choice on applied throttling: on each of these four levels
  // the first photo, and only that one, is fetched first. « At most one » would stay green
  // with none, so this reads exactly one. Same bytes either way.
  test.describe('the first photo is fetched first (§7)', () => {
    const high = (page: Page) => page.locator('main img[fetchpriority="high"]');
    // Next writes `priority` as a preload too, which the `<img>` alone would not show.
    const preloads = async (page: Page) =>
      (
        await page
          .locator('head link[rel="preload"][as="image"]')
          .evaluateAll((links) => links.map((l) => l.getAttribute('imagesrcset') ?? l.getAttribute('href') ?? ''))
      ).filter((p) => p.includes('cdn.stub'));

    for (const path of ['/coiffure', '/coiffure/abidjan', '/coiffure/abidjan/marcory', '/recherche?q=vitrine']) {
      test(`${path}: exactly one, the first photo’s`, async ({ page }) => {
        await routeNextImages(page);
        await page.goto(path);
        await expect(page.locator('main img[data-initial]').first()).toHaveAttribute('fetchpriority', 'high');
        await expect(high(page)).toHaveCount(1);
        expect(await preloads(page)).toHaveLength(1);
      });
    }

    // « Load it first » means the first photo, not the first card (decision 6). As built at
    // first, a list opening on a logo-only salon preloaded nothing and lost the whole gain.
    test('a list that starts with a logo and a letter: the first salon with a photo holds it', async ({ page, request }) => {
      // From the served HTML: the preload scanner reads this before any script runs.
      const html = await (await request.get('/recherche?q=sans-photo-en-tete')).text();
      const inHtml = [...html.matchAll(/<link[^>]*rel="preload"[^>]*as="image"[^>]*>/g)]
        .map((m) => m[0])
        .filter((link) => link.includes('cdn.stub'));
      expect(inHtml).toHaveLength(1);
      expect(inHtml[0]).toContain('f1.jpg');
      await routeNextImages(page);
      await page.goto('/recherche?q=sans-photo-en-tete');
      await expect(page.locator('main [role="presentation"]:has(h3)')).toHaveCount(4);
      await expect(high(page)).toHaveCount(1);
      await expect(high(page)).toHaveAttribute('alt', 'Beauté Divine');
      await expect(page.locator('main img[alt="Logo Maison Nala"]')).toHaveAttribute('loading', 'lazy');
      await expect(page.locator('main img[alt="Chez Koffi Barber"]')).toHaveAttribute('loading', 'lazy');
      expect(await preloads(page)).toHaveLength(1);
    });

    test('a list with no photo at all: none, the logo included', async ({ page, request }) => {
      const html = await (await request.get('/recherche?q=sans-photo')).text();
      expect(html, 'the list itself, or this proves nothing').toContain('Maison Nala');
      expect([...html.matchAll(/<link[^>]*rel="preload"[^>]*as="image"[^>]*>/g)].filter((m) => m[0].includes('cdn.stub'))).toEqual([]);
      await routeNextImages(page);
      await page.goto('/recherche?q=sans-photo');
      await expect(page.locator('main img[alt="Logo Maison Nala"]')).toHaveAttribute('loading', 'lazy');
      await expect(high(page)).toHaveCount(0);
      expect(await preloads(page)).toEqual([]);
    });

    test('/: none, because a phone would preload a photo it has off-screen', async ({ page }) => {
      await routeNextImages(page);
      await page.goto('/');
      await expect(page.locator('main a img').first()).toBeAttached();
      await expect(high(page)).toHaveCount(0);
      expect(await preloads(page)).toEqual([]);
    });

    test('the favourites: none, behind a sign-in and with no budget', async ({ page }) => {
      await routeNextImages(page);
      await signInConsumer(page);
      await expect(page.locator('main img[data-initial]').first()).toBeAttached();
      await expect(high(page)).toHaveCount(0);
      expect(await preloads(page)).toEqual([]);
    });
  });

  // The owner moved it after seeing the before and after (web-swiss-cards.md §2.4): it sits
  // over a row's photo column and off the card's text, at normal text and at these widths.
  // A button floating over a list is only wrong at some scroll, so each row is brought
  // under it. This reads the card's text only: a refused heart's sentence is §2.4's to
  // state, and the footer is the next block's.
  test.describe('« Carte » over the list', () => {
    for (const [width, height] of [
      [320, 568],
      [360, 640],
      [390, 844],
      [768, 1024],
      [820, 1180],
    ] as const) {
      test(`at ${width}: it stays off every row’s text, and is 48 tall`, async ({ page }) => {
        await size(page, width, height);
        await routeNextImages(page);
        await page.goto('/recherche?q=vitrine');
        const toggle = page.getByRole('button', { name: 'Carte', exact: true });
        await expect(toggle).toBeVisible();
        // `:has(h3)`, because the map's own elements carry this role too, once it has mounted.
        const rows = page.locator('main [role="presentation"]:has(h3)');
        expect(await rows.count(), 'the fixtures’ eight rows').toBe(8);

        const atRest = (await toggle.boundingBox())!;
        let passedUnder = 0;
        for (let i = 0; i < 8; i++) {
          const row = rows.nth(i);
          const before = (await row.boundingBox())!;
          await page.evaluate(
            (top) => window.scrollBy({ top, behavior: 'instant' }),
            before.y + before.height / 2 - (atRest.y + atRest.height / 2),
          );
          const button = (await toggle.boundingBox())!;
          const rowBox = (await row.boundingBox())!;
          const column = (await row.locator('h3').locator('..').boundingBox())!;
          expect(button.x + button.width, `row ${i}: the button reaches its text column`).toBeLessThanOrEqual(column.x);
          expect(button.height, 'the button fell below the 48px floor').toBeGreaterThanOrEqual(48);
          const under = rowBox.y < button.y + button.height && button.y < rowBox.y + rowBox.height;
          if (under) passedUnder++;
          // A row wholly above the button at the top of the page can never reach it. Any
          // other row must really have passed under it, or this proves nothing about it.
          if (before.y + before.height > atRest.y) expect(under, `row ${i} never passed under the button`).toBe(true);
          await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
        }
        expect(passedUnder, 'no row passed under the button').toBeGreaterThan(0);
      });
    }

    test('at 390 the map view reads « Liste », on no map control, and its tap comes back', async ({ page }) => {
      await size(page, 390, 844);
      await page.route(/cartocdn\.com/, (r) => r.abort());
      await page.goto('/recherche?q=vitrine');
      await page.getByRole('button', { name: 'Carte', exact: true }).click();
      await expect(page.locator('.maplibregl-map')).toBeVisible();
      const liste = page.getByRole('button', { name: 'Liste', exact: true });
      await expect(liste).toBeVisible();
      const button = (await liste.boundingBox())!;
      expect(button.height).toBeGreaterThanOrEqual(48);
      // Attribution exists when the map is built and the zoom mounts a little later, so
      // counting before it could pass on attribution alone. « Autour de moi » is our own
      // button, not one of MapLibre's.
      await expect(page.locator('.maplibregl-ctrl-zoom-in')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Autour de moi' })).toBeVisible();
      const controls = page.locator(
        '.maplibregl-ctrl, .maplibregl-ctrl-attrib, .maplibregl-ctrl-logo, button:has-text("Autour de moi")',
      );
      const count = await controls.count();
      expect(count, 'no map control to read').toBeGreaterThan(0);
      for (let i = 0; i < count; i++) {
        const control = await controls.nth(i).boundingBox();
        if (!control) continue;
        const meets =
          control.x < button.x + button.width &&
          button.x < control.x + control.width &&
          control.y < button.y + button.height &&
          button.y < control.y + control.height;
        expect(meets, `« Liste » sits on a map control, number ${i}`).toBe(false);
      }
      await liste.click();
      await expect(page.locator('main [role="presentation"]:has(h3)').first()).toBeVisible();
      await expect(page.getByRole('button', { name: 'Carte', exact: true })).toBeVisible();
    });
  });

  // The owner's choice on 2026-11-05 (web-swiss-cards.md §11, decision 5): it rides the list
  // at the screen's foot and stops above the footer. Fixed, it stood on « Instagram » at every
  // width below `lg`: the link's centre answered the button and a press opened the map.
  test.describe('« Carte » stops above the footer', () => {
    const SIZES = [
      [320, 568],
      [360, 640],
      [390, 844],
      [768, 1024],
      [820, 1180],
      [1023, 768],
    ] as const;
    const toEnd = (page: Page) =>
      page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }));
    const toggleOn = (page: Page) => page.getByRole('button', { name: 'Carte', exact: true });

    for (const [width, height] of SIZES) {
      for (const path of ['/recherche?q=vitrine', '/recherche?q=vide']) {
        test(`${path} at ${width}: every footer link answers, and the button is above the footer`, async ({ page }) => {
          await size(page, width, height);
          await routeNextImages(page);
          await page.goto(path);
          await expect(toggleOn(page)).toBeVisible();
          await toEnd(page);
          const button = (await toggleOn(page).boundingBox())!;
          const footer = (await page.locator('footer').boundingBox())!;
          expect(button.y + button.height, 'the button reaches the footer').toBeLessThanOrEqual(footer.y);
          // Last link first, from the end of the page, each brought on-screen only if it is
          // not: the footer can be taller than the screen, and `elementFromPoint` answers
          // nothing outside it.
          const links = await page.locator('footer a').evaluateAll((els) =>
            els.reverse().map((el) => {
              el.scrollIntoView({ block: 'nearest', behavior: 'instant' });
              const r = el.getBoundingClientRect();
              const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
              return { name: el.textContent?.trim(), answers: !!hit && (hit === el || el.contains(hit)) };
            }),
          );
          expect(links.map((l) => l.name), 'the link it used to stand on').toContain('Instagram');
          expect(links.filter((l) => !l.answers)).toEqual([]);
        });
      }

      test(`at ${width}, mid-list: it stands at the screen’s foot, clear of the text column`, async ({ page }) => {
        await size(page, width, height);
        await routeNextImages(page);
        await page.goto('/recherche?q=vitrine');
        const row = page.locator('main [role="presentation"]:has(h3)').nth(3);
        await row.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
        const button = (await toggleOn(page).boundingBox())!;
        const column = (await row.locator('h3').locator('..').boundingBox())!;
        expect(button.y + button.height, 'it became a block in the page').toBe(height - 24);
        expect(button.x + button.width).toBeLessThanOrEqual(column.x);
      });

      // From far down a long list the page under the map is much shorter, so the browser held
      // it at its end: the footer alone, with the map and « Liste » above the screen. Read
      // before any press: Playwright's click scrolls its target into view by itself.
      test(`at ${width}, pressed far down the list: the map opens whole, and « Liste » goes back to the same place`, async ({ page }) => {
        await size(page, width, height);
        await page.route(/cartocdn\.com/, (r) => r.abort());
        await routeNextImages(page);
        await page.goto('/recherche?q=vitrine');
        const row = page.locator('main [role="presentation"]:has(h3)').nth(6);
        await row.evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
        const from = await page.evaluate(() => window.scrollY);
        expect(from, 'not far enough down, so this proves nothing').toBeGreaterThan(height);
        await toggleOn(page).click();
        const map = page.locator('.maplibregl-map');
        await expect(map).toBeVisible();
        const whole = (await map.boundingBox())!;
        expect(whole.y, 'the map’s top is off the screen').toBeGreaterThanOrEqual(0);
        expect(whole.y + whole.height, 'the map’s foot is off the screen').toBeLessThanOrEqual(height);
        const liste = page.getByRole('button', { name: 'Liste', exact: true });
        const button = (await liste.boundingBox())!;
        expect(button.y + button.height, '« Liste » is not at the screen’s foot').toBe(height - 24);
        await liste.click();
        await expect(toggleOn(page)).toBeVisible();
        expect(await page.evaluate(() => window.scrollY), 'the list lost its place').toBe(from);
      });
    }

    test('at 390 a press on « Instagram » opens the link, and not the map', async ({ page, context }) => {
      await size(page, 390, 844);
      await routeNextImages(page);
      await context.route(/instagram\.com/, (r) => r.fulfill({ status: 200, contentType: 'text/html', body: '' }));
      await page.goto('/recherche?q=vitrine');
      await expect(toggleOn(page)).toBeVisible();
      await toEnd(page);
      const link = (await page.locator('footer').getByRole('link', { name: 'Instagram' }).boundingBox())!;
      const opened = context.waitForEvent('page', { timeout: 5_000 });
      await page.mouse.click(link.x + link.width / 2, link.y + link.height / 2);
      const profile = await opened;
      await profile.waitForURL(/instagram\.com/);
      await expect(page.locator('.maplibregl-map')).toBeHidden();
      await expect(toggleOn(page)).toBeVisible();
    });

    // Where it has stopped, or rests under a short list, it can stand level with the toast.
    // The toast is on top and at most half the screen wide, so it reaches the button's right
    // padding and not its word, and a press there goes through to the button (§2.4).
    for (const [width, height] of SIZES.slice(0, 3)) {
      test(`at ${width}, level with the toast: its word stays clear and a press still answers`, async ({ page }) => {
        await size(page, width, height);
        await routeNextImages(page);
        await page.route('**/api/me/favorites**', (r) =>
          r.request().method() === 'GET'
            ? r.fulfill({ status: 200, contentType: 'application/json', body: '{"favorites":[]}' })
            : r.fulfill({ status: 204 }),
        );
        await page.goto('/recherche?q=tresses');
        const heart = page.getByRole('button', { name: 'Ajouter Beauté Divine aux favoris' });
        await expect(heart).toBeEnabled();
        await heart.click();
        const pill = page.getByRole('status').filter({ hasText: 'Ajouté aux favoris' }).locator('div').first();
        await expect(pill).toBeVisible();
        const toast = (await pill.boundingBox())!;
        const read = await toggleOn(page).evaluate((el, t) => {
          const end = document.documentElement.scrollHeight - innerHeight;
          for (let y = 0; y <= end; y += 2) {
            window.scrollTo({ top: y, behavior: 'instant' });
            const b = el.getBoundingClientRect();
            if (b.left < t.x + t.width && t.x < b.right && b.top < t.y + t.height && t.y < b.bottom) {
              const range = document.createRange();
              range.selectNodeContents(el);
              // Inside the part the toast covers, where a press has to reach the button.
              const under = document.elementFromPoint(
                (Math.max(b.left, t.x) + Math.min(b.right, t.x + t.width)) / 2,
                (Math.max(b.top, t.y) + Math.min(b.bottom, t.y + t.height)) / 2,
              );
              return { wordEnd: range.getBoundingClientRect().right, answers: under === el };
            }
          }
          return null;
        }, toast);
        expect(read, 'they never stood level, so this proves nothing').not.toBeNull();
        expect(read!.wordEnd).toBeLessThanOrEqual(toast.x);
        expect(read!.answers).toBe(true);
      });
    }
  });

  // Where a photo is cut in a fixed frame (web-swiss-cards.md §2.4, decisions 2 and 8), read
  // from the computed style: a token that never reaches the stylesheet reads 50% 50%, and the
  // class alone in the HTML would not show that.
  test.describe('where a photo is cut', () => {
    const position = (image: Locator) => image.evaluate((el) => getComputedStyle(el).objectPosition);

    test('a card’s photo is at 50% 20%, and a logo stays in its corner', async ({ page }) => {
      await routeNextImages(page);
      await page.goto('/recherche?q=vitrine');
      expect(await position(page.locator('main img[alt="Beauté Divine"]'))).toBe('50% 20%');
      expect(await position(page.locator('main img[alt="Logo Maison Nala"]'))).toBe('0% 100%');
    });

    test('the salon page’s cover is at 50% 20%, and its logo and gallery stay centred', async ({ page }) => {
      await routeNextImages(page);
      await page.goto('/salon-au-logo');
      expect(await position(page.locator('header img[alt="Salon Beauté Divine"]'))).toBe('50% 20%');
      expect(await position(page.locator('header img[alt="Logo Beauté Divine"]'))).toBe('50% 50%');
      const gallery = page.getByRole('button', { name: /^Agrandir la photo/ }).locator('img');
      expect(await gallery.count(), 'the gallery’s photos, or this proves nothing').toBeGreaterThan(0);
      expect(await position(gallery.first())).toBe('50% 50%');
    });
  });

  test('a row selected from the map has a square ring, with its offset', async ({ page }) => {
    await size(page, 1280);
    await page.route('**/basemaps.cartocdn.com/**', (r) => r.abort());
    await routeNextImages(page);
    await page.goto('/recherche?commune=Cocody');
    await page.locator('.myweli-marker').first().click();
    const ring = page.locator('main .ring-2');
    await expect(ring).toBeVisible();
    const { radius, shadow } = await ring.evaluate((el) => {
      const s = getComputedStyle(el);
      return { radius: s.borderTopLeftRadius, shadow: s.boxShadow };
    });
    expect(radius).toBe('0px');
    // The offset in `surface`, #FAFAFA, 2px, inside the 4px that draws the ring in black.
    expect(shadow).toContain('rgb(250, 250, 250) 0px 0px 0px 2px');
    expect(shadow).toContain('rgb(0, 0, 0) 0px 0px 0px 4px');
  });

  test.describe('the favourites, signed in', () => {
    const favourites = (page: Page) =>
      page.getByRole('heading', { name: 'Favoris' }).locator('xpath=ancestor::section[1]');
    const entry = (page: Page, name: string) =>
      favourites(page)
        .locator('.grid > div')
        .filter({ has: page.getByRole('heading', { level: 3, name }) });

    test('a row on a phone, a tile from sm', async ({ page }) => {
      await routeNextImages(page);
      await signInConsumer(page);
      const card = entry(page, 'Beauté Divine').locator('a');
      const media = card.locator('img').locator('..');
      await size(page, 390);
      await expect(media).toBeVisible();
      const phone = [(await media.boundingBox())!.width, (await card.boundingBox())!.width];
      expect(Math.abs(phone[0] / phone[1] - 1 / 3)).toBeLessThanOrEqual(0.02);
      await size(page, 820);
      const tablet = [(await media.boundingBox())!.width, (await card.boundingBox())!.width];
      expect(tablet[0]).toBeCloseTo(tablet[1], 0);
    });

    test('a stopped salon is no link and offers no « Annuler »; a live one has both', async ({ page }) => {
      await routeNextImages(page);
      await signInConsumer(page);
      const stopped = entry(page, 'Salon Arrêté');
      const live = entry(page, 'Beauté Divine');
      await expect(stopped).toBeVisible();
      await expect(stopped.locator('a')).toHaveCount(0);
      await expect(stopped.getByText('Ce salon ne prend plus de rendez-vous sur MyWeli.')).toBeVisible();
      await expect(live.locator('a')).toHaveAttribute('href', '/beaute-divine');

      await stopped.getByRole('button', { name: 'Retirer des favoris' }).click();
      await expect(page.getByText('Retiré des favoris')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Annuler' })).toHaveCount(0);

      await live.getByRole('button', { name: 'Retirer des favoris' }).click();
      await expect(page.getByRole('button', { name: 'Annuler' })).toBeVisible();
    });
  });

  // The fast failure every spec above stands on (`_cdn-stub-dns.cjs`). Unrouted, because
  // this is the request the Next server has to answer.
  test('the Next server refuses the stub’s unresolvable photo at once', async ({ request }) => {
    const started = Date.now();
    const answer = await request.get('/_next/image?url=https://cdn.stub/p1.jpg&w=640&q=75');
    expect(answer.status()).toBeGreaterThanOrEqual(400);
    // What it has to tell apart: 26 ms with the preload, against no answer in 6 s and a 30 s
    // stall on CI. 5 s still goes red on both, and stops measuring a busy runner, because a
    // required suite with `retries: 0` would go red on a pause with no defect.
    expect(Date.now() - started).toBeLessThan(5_000);
  });
});

/// The list was read from `main` at ea0c8f0c, built against the stub, before any edit to
/// the landing (web-swiss-cards.md §12): the words search engines read did not move.
test.describe('what search engines read on a landing has not moved', () => {
  for (const [path, h1, canonical, h2s] of [
    [
      '/coiffure',
      'Coiffure en Côte d\'Ivoire',
      /\/coiffure$/,
      ['Choisissez votre ville', '1 salon', 'Autres prestations en Côte d\'Ivoire', 'Questions fréquentes'],
    ],
    [
      '/coiffure/abidjan',
      'Coiffure à Abidjan',
      /\/coiffure\/abidjan$/,
      ['Choisissez votre commune', '1 salon', 'Autres prestations à Abidjan', 'Questions fréquentes'],
    ],
    [
      '/coiffure/abidjan/cocody',
      'Coiffure à Cocody',
      /\/coiffure\/abidjan\/cocody$/,
      ['1 salon', 'Coiffure dans d’autres communes', 'Autres prestations à Cocody', 'Questions fréquentes'],
    ],
  ] as const) {
    test(path, async ({ page }) => {
      await page.goto(path);
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(h1);
      await expect(page).toHaveTitle(`${h1} — réserver en ligne · MyWeli`);
      await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', canonical);
      const types = await page.locator('script[type="application/ld+json"]').evaluateAll((all) =>
        all.map((s) => JSON.parse(s.textContent as string)['@type']).sort(),
      );
      expect(types).toEqual(['BreadcrumbList', 'FAQPage', 'ItemList', 'Organization']);
      await expect(page.getByRole('heading', { level: 2 })).toHaveText([...h2s]);
    });
  }
});

test('what search engines read has not moved (§14)', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Réservez beauté & bien-être à Abidjan');
  await expect(page).toHaveTitle('MyWeli — réservez beauté & bien-être à Abidjan');
  await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', /^https?:\/\/[^/]+\/?$/);
  const types = await page.locator('script[type="application/ld+json"]').evaluateAll((all) =>
    all.map((s) => JSON.parse(s.textContent as string)['@type']).sort(),
  );
  expect(types).toEqual(['FAQPage', 'Organization', 'WebSite']);
  await expect(page.getByRole('heading', { level: 2 })).toHaveText(
    ['Catégories', 'Salons populaires', 'Partout à Abidjan', 'Vous êtes un salon ?', 'Questions fréquentes'],
    { useInnerText: true },
  );
});
