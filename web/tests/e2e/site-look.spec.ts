import { expect, test, type Page } from '@playwright/test';

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

    test(`/recherche at ${width}: the logo and the list`, async ({ page }) => {
      await size(page, width);
      await page.goto('/recherche?commune=Cocody');
      const h1 = page.getByRole('heading', { level: 1 });
      await expect(h1).toBeVisible();
      expect((await h1.boundingBox())!.x).toBeCloseTo(await logoLeft(page), 0);
    });
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
});

test.describe('the panel (§4.5)', () => {
  for (const width of [1024, 1280, 1440, 1536, 1920, 2560]) {
    test(`at ${width}: meets its rules and the container's edge, and the logo is never cut`, async ({ page }) => {
      await size(page, width);
      await page.goto('/');
      const panel = page.locator('[data-weave-panel]');
      const p = (await panel.boundingBox())!;

      const account = (await page.getByRole('banner').getByRole('link', { name: 'Mon compte', exact: true }).boundingBox())!;
      expect(p.x + p.width, 'the rows end where the header does').toBeCloseTo(account.x + account.width, 0);
      const header = await box(page, 'header');
      expect(p.y).toBeCloseTo(header.y + header.height, 0);
      const next = page.getByRole('heading', { name: 'Catégories' }).locator('xpath=ancestor::section[1]');
      expect((await next.boundingBox())!.y).toBeCloseTo(p.y + p.height, 0);

      const mark = (await page.locator('svg[data-weave=panel] svg').boundingBox())!;
      expect(mark.y + mark.height, 'the cloth is cut at the bottom, never through the logo').toBeLessThanOrEqual(
        p.y + p.height,
      );
      expect(mark.x + mark.width).toBeLessThanOrEqual(p.x + p.width);

      // Never behind text.
      for (const text of [page.getByRole('heading', { level: 1 }), page.locator('main form').first()]) {
        const t = (await text.boundingBox())!;
        expect(t.x + t.width, 'text runs into the panel').toBeLessThanOrEqual(p.x);
      }
    });
  }
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

  test('no boxed section is left on the home page', async ({ page }) => {
    await page.goto('/');
    const boxed = await page.locator('main section').evaluateAll((all) =>
      all.flatMap((s) =>
        // Not every `a`: a button keeps its corners (§3), and salon cards lose
        // theirs in S3. The category links are what were boxes here.
        [s, ...s.querySelectorAll('div, li a')].filter((el) => {
          const css = getComputedStyle(el);
          return parseFloat(css.borderTopLeftRadius) > 0 && parseFloat(css.borderLeftWidth) > 0;
        }).map((el) => el.outerHTML.slice(0, 80)),
      ),
    );
    expect(boxed).toEqual([]);
  });
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
