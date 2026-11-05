import { expect, test } from '@playwright/test';

/// **Is a salon's card photo really served on the live site?**
///
///   npm run check:card-photo                     # production
///   PRIVACY_URL=http://127.0.0.1:3000 CARD_PHOTO_PATH='/recherche?q=vide' npm run check:card-photo
///
/// **Why this exists** (docs/design/web-swiss-cards.md §9). Production has no public
/// salon, so at the merge of B11.3 nobody could read a card, a photo through Vercel's
/// optimizer or the 31-day cache in effect. A sentence in a doc would be forgotten by
/// the day the first salon goes public. This wakes by itself that day.
///
/// **Reading the page's photo cannot see a plan's ceiling.** That file sits in the 31-day
/// cache after its first read, and a cached file keeps answering (inferred: Vercel's
/// answer past the ceiling is unread). What fails there is the next new photo, as a tile
/// with a letter on it, which nobody would report. So each run also asks for one
/// transformation nobody has read: the same file at a quality that changes daily. Its
/// cost is one transformation a day.
///
/// It is a MONITOR, GET only, with no cookies. **It reads the page, not the API:** these
/// jobs already reach myweli.com from a runner, while no scheduled check reaches
/// `api.myweli.com` through the Worker.
///
/// Three outcomes, and only these:
/// - not a 200, or neither of the page's two states: red, because a check that measured
///   nothing is not green;
/// - « Aucun salon trouvé », or a list with no card photo: a printed skip, green,
///   claiming nothing;
/// - a list with a card photo: the first one's `/_next/image` answers 200, it has
///   decoded to something, its box is 4:3, and a transformation nobody has read answers
///   200 too. Anything else is red.
const target = process.env.PRIVACY_URL ?? 'https://myweli.com';
/// Rehearsals only, so a local stub can show each outcome. The workflow never sets it.
const path = process.env.CARD_PHOTO_PATH ?? '/recherche';

test.use({ baseURL: target, viewport: { width: 390, height: 844 } });

/// 60 values, so a quality comes back after 60 days, past the cache's 31 and never on one
/// that is still cached. 1 to 60, so never the 75 a page asks for.
function unreadByAnyone(file: string, now: Date): string {
  const url = new URL(file);
  url.searchParams.set('q', String((Math.floor(now.getTime() / 86_400_000) % 60) + 1));
  return url.href;
}

test(`${path}: the first card photo, once there is one`, async ({ page, request }) => {
  // Longer than the poll below. At the default of 30 s, a photo that never loads also
  // read « Test timeout of 30000ms exceeded », which says nothing about the photo.
  test.setTimeout(60_000);

  const response = await page.goto(path, { waitUntil: 'domcontentloaded' });
  expect(response?.status(), `${path} did not answer 200: nothing was measured`).toBe(200);

  const empty = page.getByText('Aucun salon trouvé');
  const count = page.getByRole('heading', { level: 2, name: /^\d+ salons?$/ });
  await expect(
    empty.or(count).first(),
    `${path} shows neither « Aucun salon trouvé » nor a count: an error page, or a refused API`,
  ).toBeVisible();

  // Only a card's photo carries `data-initial`, so a logo or a letter is not read as one.
  const photo = page.locator('main img[data-initial]').first();
  if ((await empty.isVisible()) || (await photo.count()) === 0) {
    const nothing = 'no public salon with a photo: nothing read';
    console.log(nothing);
    test.skip(true, nothing);
    return;
  }

  await photo.scrollIntoViewIfNeeded();
  await expect
    .poll(() => photo.evaluate((img: HTMLImageElement) => img.complete), {
      message: 'the first card photo never finished loading',
      timeout: 30_000,
    })
    .toBe(true);

  const file = await photo.evaluate((img: HTMLImageElement) => img.currentSrc);
  expect(file, 'the card photo does not go through the optimizer').toContain('/_next/image');
  const served = await request.get(file);
  expect(served.status(), `${file} did not answer 200`).toBe(200);

  expect(
    await photo.evaluate((img: HTMLImageElement) => img.naturalWidth),
    `${file} answered, and did not decode`,
  ).toBeGreaterThan(0);

  const media = (await photo.locator('..').boundingBox())!;
  expect(Math.abs(media.width / media.height - 4 / 3), 'the card is not 4:3').toBeLessThanOrEqual(0.02);

  const unread = unreadByAnyone(file, new Date());
  const transformed = await request.get(unread);
  expect(
    transformed.status(),
    `${unread}, a transformation nobody has read, did not answer 200: new photos show a letter while cached ones still load. A 402 means the plan ran out`,
  ).toBe(200);
  console.log(`read ${file}: 200, decoded, 4:3; ${unread}: 200`);
});
