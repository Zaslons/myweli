import { expect, test } from '@playwright/test';

/// B2b — the type scale must not overflow anything (WEB-SYSTEM §3).
///
/// Why this file exists: B2b deliberately makes text wider (it mirrors the app's
/// `letterSpacing`, which the web never had) and grows 51 headings to 22px. French
/// copy is long and at 375px there is nowhere for it to go. The unit suite asserts
/// roles and text, never geometry; there is no screenshot harness on web.
///
/// **BE HONEST ABOUT WHAT THIS CATCHES.** I mutation-tested it: cranking
/// `bodyMedium`'s tracking from 0.25px to **6px** does NOT make it fail — because
/// text *wraps*. A wider string takes more lines; it does not overflow. So this
/// cannot see tracking, and that is the finding, not a gap: extra tracking reflows,
/// and reflow is not a bug.
///
/// What it does catch is the class of bug that *is* a bug — an element wide enough
/// to push the page sideways (a `nowrap` heading, a fixed-width chrome element that
/// stopped fitting). That is a real failure mode for the 18→22px sidebar wordmark
/// and the hero, so the guard is worth its seconds.
///
/// The journal test below is the one that bites hardest: it asserts an exact
/// computed line-height, and it goes red the moment `leading-tight` stops winning.

test.use({ viewport: { width: 375, height: 812 } });

const PUBLIC_ROUTES = [
  ['the marketing home — all 15 of the h2s that grew 20 → 22px live here', '/'],
  ['discovery', '/recherche?commune=Cocody'],
  ['a salon page — the h1 that went 30 → 28px', '/salon/salon-excellence'],
];

/// The document must not scroll sideways. This is the blunt, honest check: if any
/// string got wide enough to push the layout, the body reports it here.
async function noHorizontalScroll(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const d = document.documentElement;
    // +1 for sub-pixel rounding; we are hunting real overflow, not 0.5px.
    return d.scrollWidth <= d.clientWidth + 1;
  });
}

/// Any element whose own text spills horizontally out of its box. Skips the
/// legitimately-scrollable (the journal grid, the roster table, chip strips) by
/// honouring `overflow-x`.
async function overflowingText(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const bad: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('h1,h2,h3,p,span,button,a,label'))) {
      if (!el.textContent?.trim()) continue;
      const s = getComputedStyle(el);
      if (s.overflowX !== 'visible') continue; // it is meant to scroll/clip
      if (s.textOverflow === 'ellipsis') continue; // it is meant to truncate
      if (el.scrollWidth > el.clientWidth + 1) {
        bad.push(`<${el.tagName.toLowerCase()}> "${el.textContent.trim().slice(0, 40)}" ${el.scrollWidth}>${el.clientWidth}`);
      }
    }
    return bad;
  });
}

for (const [name, url] of PUBLIC_ROUTES) {
  test(`${name} — no horizontal overflow at 375px`, async ({ page }) => {
    await page.goto(url);
    await page.waitForLoadState('networkidle');
    expect(await noHorizontalScroll(page), `the page scrolls sideways at 375px`).toBe(true);
    expect(await overflowingText(page), 'text spills out of its own box').toEqual([]);
  });
}

test('the pro journal — the 11px block label still fits its ~15px row', async ({
  page,
}) => {
  // The tightest box in the product, and the one B2b touched most riskily:
  // `text-[11px]` → `text-labelSmall`, which carries a 16px line the arbitrary
  // value never had. `leading-tight` overrides it back to 13.75px — this is what
  // proves that actually happens in a browser rather than only in the cascade.
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.goto('/pro/rendez-vous');
  await expect(page.getByText('Awa').first()).toBeVisible();

  const line = await page
    .getByRole('button', { name: /Koffi/ })
    .first()
    .evaluate((el) => getComputedStyle(el).lineHeight);
  expect(line, 'leading-tight must still beat the token’s baked 16px line').toBe(
    '13.75px',
  );
});
