import { expect, test } from '@playwright/test';

import { hermetic } from './_message';
import { routeNextImages } from './_pixel';

/// D11 (web-swiss-salon.md §3.3, §3.9): below `lg` the salon page's booking bar is fixed and
/// `w-screen max-w-full`, as wide as the screen and never wider. `100vw` keeps it to the screen
/// when Chrome lays a page out wider than the screen (salon-page.spec.ts's D10); but a window's
/// classic scrollbar, the kind that takes room (Windows, or macOS set to always show them), is
/// part of `100vw`, so without `max-w-full` the bar would run under it, « Réserver » with it.
///
/// Its own file, because the scrollbar has to take room: Playwright starts Chromium with its
/// scrollbars hidden for the whole browser (`--hide-scrollbars`), which a page cannot undo, so
/// this file's browser starts without that switch, and the page gives its scrollbar a width.

test.use({ launchOptions: { ignoreDefaultArgs: ['--hide-scrollbars'] } });

const CLASSIC = '::-webkit-scrollbar { width: 15px; height: 15px; } ::-webkit-scrollbar-thumb { background: #888; }';

for (const [width, height] of [
  [1023, 768],
  [640, 400],
] as const) {
  test(`at ${width}×${height} with a scrollbar that takes room, the bar stops at the scrollbar and « Réserver » stays clear of it`, async ({ page }) => {
    await hermetic(page);
    await page.setViewportSize({ width, height });
    await routeNextImages(page);
    await page.goto('/beaute-divine');
    await expect(page.getByRole('button', { name: 'Ajouter aux favoris' })).toBeEnabled();
    await page.addStyleTag({ content: CLASSIC });
    await expect
      .poll(() => page.evaluate(() => window.innerWidth - document.documentElement.clientWidth), {
        message: 'the scrollbar takes no room, so this proves nothing',
      })
      .toBeGreaterThanOrEqual(10);
    const at = await page.evaluate(() => {
      const bar = document.querySelector('main > :last-child')!;
      const cta = [...bar.querySelectorAll('a')].find((a) => a.textContent?.trim() === 'Réserver')!;
      const b = bar.getBoundingClientRect();
      return {
        screen: document.documentElement.clientWidth,
        window: window.innerWidth,
        display: getComputedStyle(bar).display,
        bar: { left: b.left, right: b.right, bottom: b.bottom },
        cta: cta.getBoundingClientRect().right,
      };
    });
    test.info().annotations.push({ type: 'scrollbar', description: JSON.stringify(at) });
    expect(at.display, 'the bar is not shown at this width, so this proves nothing').toBe('flex');
    expect(Math.abs(at.bar.bottom - height), `the bar’s foot is at ${at.bar.bottom}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(at.bar.left), `the bar starts at ${at.bar.left}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(at.bar.right - at.screen), `the bar ends at ${at.bar.right}, the scrollbar starts at ${at.screen}`).toBeLessThanOrEqual(0.5);
    expect(at.cta, '« Réserver » runs under the scrollbar').toBeLessThanOrEqual(at.screen);
  });
}
