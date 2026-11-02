import { expect, test, type Page } from '@playwright/test';

import { signInConsumer, signInPro } from './_auth';

/// B11.6 — docs/design/web-swiss-fields.md §5. Anything you type in or press is
/// square, with a thin black line, read from what the browser computes, on the
/// pages people use. Dialogs this can't reach are held by tests/controls-shape.test.ts.
///
/// **What this cannot see:** iOS, which can round a field by itself. That gets looked
/// at in the simulator on the deployed site.

const TYPING =
  'input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=file]):not([type=hidden]), textarea, select';
const PRESSING = 'button, a[class*="min-h-12"]';

/// The spec's §1 exceptions, by what they are. A pill is a chip or a round icon on a
/// photo, and `rounded-sm` is only Google's and Apple's own buttons.
const notSquare = (page: Page) =>
  page.evaluate(
    ([typing, pressing]) => {
      const visible = (el: Element) => {
        const b = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return b.width > 1 && b.height > 1 && s.visibility !== 'hidden' && s.opacity !== '0';
      };
      const exempt = (el: Element) =>
        el.classList.contains('rounded-pill') ||
        /Continuer avec|S[’']inscrire avec/.test(el.textContent ?? '') ||
        // A map's pins and controls belong to the map (spec §1).
        el.closest('.maplibregl-map, .myweli-marker') !== null ||
        // A photo you press is a photo: no words, only its image (spec §1).
        (el.querySelector('img') !== null && (el.textContent ?? '').trim() === '') ||
        // An agenda block is content on a grid, pressed as content (spec §1).
        (el.classList.contains('rounded-md') && getComputedStyle(el).position === 'absolute');
      return [...document.querySelectorAll(`${typing}, ${pressing}`)]
        .filter((el) => visible(el) && !exempt(el))
        .filter((el) => parseFloat(getComputedStyle(el).borderTopLeftRadius) > 0)
        .map((el) => `${el.tagName} "${(el.textContent ?? '').trim().slice(0, 24)}" ${el.className.toString().slice(0, 60)}`);
    },
    [TYPING, PRESSING],
  );

const notBlackLined = (page: Page) =>
  page.evaluate((typing) => {
    return [...document.querySelectorAll(typing)]
      .filter((el) => {
        const b = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return b.width > 1 && b.height > 1 && s.opacity !== '0' && !(el as HTMLInputElement).disabled;
      })
      // The bar's fields have no line of their own: the form draws them.
      .filter((el) => !el.closest('form[data-search-bar]'))
      .filter((el) => getComputedStyle(el).borderTopColor !== 'rgb(0, 0, 0)')
      .map((el) => `${el.tagName} ${el.getAttribute('aria-label') ?? el.id} ${getComputedStyle(el).borderTopColor}`);
  }, TYPING);

const PUBLIC = [
  '/',
  '/recherche?commune=Cocody',
  '/connexion',
  '/pro/connexion',
  '/pro/inscription',
  '/beaute-divine',
  '/beaute-divine/reserver',
  '/coiffure/abidjan/cocody',
  '/professionnels',
  '/support',
  '/suppression-compte',
  '/page-qui-nexiste-pas',
];
const CONSUMER = ['/mon-compte', '/mon-compte/appt2', '/mon-compte/favoris'];
const PRO = [
  '/pro',
  '/pro/rendez-vous',
  '/pro/clients',
  '/pro/catalogue',
  '/pro/disponibilites',
  '/pro/equipe',
  '/pro/profil',
  '/pro/acompte',
  '/pro/avis',
  '/pro/abonnement',
  '/pro/notifications',
];

const sweep = async (page: Page, paths: string[]) => {
  for (const width of [375, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    for (const path of paths) {
      await page.goto(path);
      await expect(page.getByRole('contentinfo')).toBeVisible();
      await page.waitForLoadState('networkidle');
      expect(await notSquare(page), `${path} at ${width}: not square`).toEqual([]);
      expect(await notBlackLined(page), `${path} at ${width}: no black line`).toEqual([]);
    }
  }
};

test('public and booking pages: every field and button is square, every field black-lined', async ({ page }) => {
  test.setTimeout(120_000);
  await sweep(page, PUBLIC);
});

test('the client’s account: the same', async ({ page }) => {
  test.setTimeout(120_000);
  await signInConsumer(page);
  await sweep(page, CONSUMER);
});

test('the Espace pro: the same', async ({ page }) => {
  test.setTimeout(180_000);
  await signInPro(page);
  await sweep(page, PRO);
});

test('the sweep is reading real controls, so a clean result means something', async ({ page }) => {
  await page.goto('/connexion');
  const counted = await page.evaluate(
    ([typing, pressing]) => [document.querySelectorAll(typing).length, document.querySelectorAll(pressing).length],
    [TYPING, PRESSING],
  );
  expect(counted[0]).toBeGreaterThan(0);
  expect(counted[1]).toBeGreaterThan(1);
});

test('filter chips keep their pill', async ({ page }) => {
  await page.goto('/recherche?commune=Cocody');
  const chip = page.getByRole('link', { name: 'Tous', exact: true });
  await expect(chip).toBeVisible();
  expect(parseFloat(await chip.evaluate((el) => getComputedStyle(el).borderTopLeftRadius))).toBeGreaterThan(20);
});

test.describe('a focused field stays square', () => {
  test('a text field, clicked and typed in', async ({ page }) => {
    await page.goto('/connexion');
    const email = page.getByLabel('Votre e-mail');
    await email.click();
    await expect(email).toBeFocused();
    expect(await email.evaluate((el) => getComputedStyle(el).borderTopLeftRadius)).toBe('0px');
  });

  test('a link wears a square ring too', async ({ page }) => {
    await page.goto('/');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    const radius = await page.evaluate(() => getComputedStyle(document.activeElement as Element).borderTopLeftRadius);
    expect(radius).toBe('0px');
  });
});

test.describe('the search is one bar (spec §3)', () => {
  for (const path of ['/', '/recherche?commune=Cocody']) {
    for (const [width, joined] of [
      [375, 'stacked'],
      [640, 'row'],
      [1280, 'row'],
    ] as const) {
      test(`${path} at ${width}: its parts touch, ${joined}`, async ({ page }) => {
        await page.setViewportSize({ width, height: 900 });
        await page.goto(path);
        const form = page.locator('form[data-search-bar]');
        const parts = await form.locator('input, button').evaluateAll((els) =>
          els.map((el) => {
            const b = el.getBoundingClientRect();
            return { x: b.x, y: b.y, r: b.right, b: b.bottom };
          }),
        );
        expect(parts).toHaveLength(3);
        for (let i = 1; i < parts.length; i++) {
          const gap = joined === 'row' ? parts[i].x - parts[i - 1].r : parts[i].y - parts[i - 1].b;
          expect(gap, `gap before part ${i}`).toBeGreaterThanOrEqual(0);
          expect(gap, `gap before part ${i}`).toBeLessThanOrEqual(1);
        }
        const line = await form.evaluate((el) => {
          const s = getComputedStyle(el);
          return [s.borderTopColor, s.borderTopWidth, s.borderTopLeftRadius];
        });
        expect(line).toEqual(['rgb(0, 0, 0)', '1px', '0px']);
      });
    }
  }

  // Without this the black button paints over the ring of the field before it.
  for (const name of ['Service ou salon', 'Commune']) {
    test(`« ${name} » rises above its neighbours when focused`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 900 });
      await page.goto('/');
      const field = page.getByLabel(name);
      await field.focus();
      const raised = await field.evaluate((el) => {
        const s = getComputedStyle(el);
        return s.position !== 'static' && parseInt(s.zIndex, 10) > 0;
      });
      expect(raised).toBe(true);
    });
  }
});
