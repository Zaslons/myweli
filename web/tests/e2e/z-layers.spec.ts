import { expect, test } from '@playwright/test';

/// B2a — the named z-index scale actually stacks (WEB-SYSTEM §9).
///
/// Why this file exists: B2a remapped every z-index from a bare number to a named
/// layer, which MOVED four surfaces. Nothing in the suite could have caught a
/// mistake — `pro-mobile-nav.spec.ts` asserts the drawer's *geometry*, and a
/// bounding box reads identically whether the drawer is on top or buried.
///
/// So these assert the thing a number never says out loud: **who is on top**.
/// They are hit-tests (`elementFromPoint`), not bounding boxes, because that is
/// the only question that matches the user's finger.

test.use({ viewport: { width: 375, height: 812 } });

async function proLogin(page: import('@playwright/test').Page) {
  await page.goto('/pro/connexion');
  await page.locator('input[type=email]').fill('salon@example.com');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();
  await page.locator('input[type=text]').fill('123456');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await expect(page).toHaveURL(/\/pro(\/)?$/);
}

/// Is `locator` (or a descendant) the element actually painted at the centre of
/// its own box? If anything covers it, this is false however visible it looks.
async function isOnTopAtCentre(
  locator: import('@playwright/test').Locator,
): Promise<boolean> {
  return locator.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return !!hit && (el === hit || el.contains(hit));
  });
}

// 768, not 375: at 375 the panel is `w-full max-w-sm` = the whole screen and
// covers the hamburger, so the two cannot coexist. The window where they CAN is
// ~384px (the panel stops growing) to 1023px (`lg:`, where the drawer becomes a
// static column) — which is exactly where the tie used to be visible.
test.describe(() => {
  test.use({ viewport: { width: 768, height: 1024 } });

  test('the drawer + its scrim cover the journal panel, not the other way round', async ({
    page,
  }) => {
  // THE REGRESSION THIS PINS. Before B2a the panel and the drawer were BOTH
  // `z-40`, and the panel renders later in the DOM — so on a phone, opening an
  // appointment and then the hamburger painted the panel over the drawer AND its
  // scrim. A tie at one layer means one of them is at the wrong layer: the panel
  // is not modal (no scrim, doesn't block the page) → `z-dropdown`; the drawer is
  // page chrome over everything → `z-modal`.
    await proLogin(page);
    // Navigate directly: the nav link lives INSIDE the drawer we are about to
    // test, and clicking it would close the drawer on navigation.
    await page.goto('/pro/rendez-vous');
    await expect(page.getByText('Awa').first()).toBeVisible();

    await page.getByRole('button', { name: /Koffi/ }).first().click();
    await expect(page.locator('#pro-journal-panel')).toBeVisible();

    const hamburger = page.getByRole('button', { name: 'Ouvrir le menu' });
    await hamburger.click();
    await expect(hamburger).toHaveAttribute('aria-expanded', 'true');

    // The drawer's nav must be reachable while the panel is open. `poll` waits
    // out the 200ms slide rather than racing it.
    await expect
      .poll(() => isOnTopAtCentre(page.locator('#pro-sidebar-nav')))
      .toBe(true);

    // ...and the panel must sit UNDER the drawer's scrim, so it dims with the
    // rest of the page. THIS is the assertion that pins the old tie, and it has
    // to compare computed LAYERS rather than hit-test:
    //
    //   * the panel and the drawer sit on opposite edges and never overlap, so
    //     "is the drawer covered" can't see the bug;
    //   * `ProShell` marks <main> inert while the drawer is open, and inert
    //     content is not hit-tested at all — so elementFromPoint returns the
    //     scrim whatever the panel's z-index is, and can't see it either.
    //
    // `inert` does not change PAINTING, though. At the old z-40 the panel still
    // painted above the z-30 scrim: it stayed bright while the whole page dimmed
    // around it. Comparing the computed values is the only thing that catches it.
    const layers = await page.evaluate(() => {
      const z = (sel: string) => {
        const el = document.querySelector(sel);
        return el ? Number(getComputedStyle(el).zIndex) : NaN;
      };
      return {
        panel: z('#pro-journal-panel'),
        scrim: z('[class*="z-overlay"]'),
        drawer: z('#pro-sidebar-nav'),
      };
    });
    expect(
      layers.panel,
      `the journal panel (z ${layers.panel}) must sit UNDER the drawer's scrim ` +
        `(z ${layers.scrim}) so it dims with the page — they were both 40 before B2a`,
    ).toBeLessThan(layers.scrim);
    expect(
      layers.scrim,
      `the scrim (z ${layers.scrim}) must sit under the drawer (z ${layers.drawer})`,
    ).toBeLessThan(layers.drawer);
  });
});

// NO TEST for /recherche's `z-[1100]` → `z-sticky` remap, deliberately. One was
// written and then deleted: mutation testing showed it passed with `z-base`, and
// passed with the z-class removed entirely. The toggle is bottom-centre and
// maplibre's own controls are in the corners, so at this viewport they never
// overlap and the z-index is simply not load-bearing — the toggle wins on paint
// order regardless. A test that cannot fail is not coverage, it is furniture.
// What actually holds that change: the pin (no arbitrary `z-` survives) and the
// emitted-CSS diff.
