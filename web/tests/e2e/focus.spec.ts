import { expect, test } from '@playwright/test';

/// B4 — §5's focus contract, measured (WEB-SYSTEM §5, §15 row 8).
///
/// Before B4, `focus-visible:` appeared ZERO times across 180 buttons and ~105
/// controls — the browser default ring, unstyled and barely visible on a
/// black-and-white UI, was doing all the work. These tests pin the designed ring:
/// its exact computed values, its keyboard-only trigger, and the skip link that
/// makes it visible on the very first Tab of any public page.
///
/// One nuance, verified against browser behaviour rather than wished away:
/// `:focus-visible` DOES match on a click-focused **text field** (that is
/// platform-correct — a field you clicked is a field you will type in). So the
/// no-ring-on-click assertion targets a **button**; asserting it on a field would
/// pin a behaviour browsers do not have.

test.use({ viewport: { width: 375, height: 812 } });

const RING = {
  outlineStyle: 'solid',
  outlineWidth: '2px',
  outlineColor: 'rgb(0, 0, 0)', // borderFocus
  outlineOffset: '2px',
};

async function outlineOf(locator: import('@playwright/test').Locator) {
  return locator.evaluate((el) => {
    const s = getComputedStyle(el);
    return {
      outlineStyle: s.outlineStyle,
      outlineWidth: s.outlineWidth,
      outlineColor: s.outlineColor,
      outlineOffset: s.outlineOffset,
    };
  });
}

test('the first Tab on a public page is the skip link, wearing the ring', async ({
  page,
}) => {
  await page.goto('/');
  await page.keyboard.press('Tab');

  const skip = page.getByRole('link', { name: 'Aller au contenu' });
  await expect(skip).toBeFocused();
  await expect(skip).toBeVisible(); // sr-only until focused — focus must reveal it
  expect(await outlineOf(skip)).toEqual(RING);

  // Activating it moves the subsequent tab order into the content.
  await page.keyboard.press('Enter');
  await expect(page).toHaveURL(/#contenu$/);
});

test('keyboard focus wears the ring; a clicked button does not', async ({
  page,
}) => {
  // The home search button — always enabled (the funnels' submit is only
  // guaranteed enabled after §14 rule 5 lands; don't couple this test to that).
  await page.goto('/');
  const search = page.getByRole('button', { name: 'Rechercher' });

  // Keyboard: reach it the way a keyboard user does — Tab-walk to it.
  // (Programmatic .focus() does not reliably set the :focus-visible heuristic.)
  for (let i = 0; i < 30; i++) {
    await page.keyboard.press('Tab');
    if (await search.evaluate((el) => el === document.activeElement)) break;
  }
  await expect(search).toBeFocused();
  expect(await outlineOf(search)).toEqual(RING);

  // Mouse: the same button, clicked — :focus-visible must NOT match. (Text
  // fields legitimately DO show the ring on click; buttons must not.)
  await page.mouse.click(5, 400); // drop focus somewhere inert
  const box = await search.boundingBox();
  await page.mouse.click(box!.x + box!.width / 2, box!.y + box!.height / 2);
  const clicked = await outlineOf(search);
  expect(clicked.outlineStyle === 'none' || clicked.outlineWidth === '0px').toBe(
    true,
  );
});

test('a focused text field shows BOTH indicators — the border swap and the ring', async ({
  page,
}) => {
  await page.goto('/connexion');
  const email = page.getByLabel(/e-mail/i);
  await email.focus();

  const s = await email.evaluate((el) => {
    const c = getComputedStyle(el);
    return { border: c.borderColor, shadow: c.boxShadow };
  });
  // The field's own focus state: border -> borderFocus + ring-1 (a 1px box-shadow
  // spread faking mobile's 2nd border pixel with zero layout shift).
  expect(s.border).toBe('rgb(0, 0, 0)');
  expect(s.shadow).toContain('0px 0px 0px 1px');
});

test('an invalid submit ties the error to its field (§6, §14)', async ({
  page,
}) => {
  await page.goto('/connexion');
  const email = page.getByLabel(/e-mail/i);
  await email.fill('pas-un-email');
  await page.getByRole('button', { name: 'Continuer avec e-mail' }).click();

  // §14 rule 5: the submit is NOT disabled for invalid input — it errors instead.
  // (Filter: Next.js's route announcer is also role=alert on every page.)
  const alert = page.getByRole('alert').filter({ hasText: 'Saisissez' });
  await expect(alert).toContainText('Saisissez une adresse e-mail valide.');

  await expect(email).toHaveAttribute('aria-invalid', 'true');
  // aria-describedby may chain "<error> <hint>" — every id must resolve.
  const ids = (await email.getAttribute('aria-describedby'))!.split(/\s+/);
  expect(ids.length).toBeGreaterThan(0);
  for (const id of ids) {
    // Attribute selector, not `#id` — React 18's useId puts COLONS in ids
    // (`:R4svf4q:-error`), which break raw CSS id selectors.
    await expect(page.locator(`[id="${id}"]`)).toBeAttached();
  }
  // The error <p> is one of the describedby targets — the association is real.
  const alertId = await alert.getAttribute('id');
  expect(ids).toContain(alertId);
});
