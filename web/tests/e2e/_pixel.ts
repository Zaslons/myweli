import type { Locator, Page } from '@playwright/test';

/// A 1×1 transparent GIF — the smallest thing that actually DECODES (axe.spec.ts
/// carries the same bytes and explains why fulfilling beats aborting: a
/// fulfilled image stays loaded, an aborted one is a broken image).
export const PIXEL = Buffer.from(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
  'base64',
);

/// The stub's raw `<img>` URLs live on the unresolvable fixture host
/// `cdn.stub` — among them the deposit screenshot the pro panel shows
/// (docs/design/web-pro-journal-panel-deposit.md). Unrouted, that image fails
/// and the panel rightly says « Capture indisponible » instead of showing it.
export async function serveStubImages(page: Page): Promise<void> {
  await page.route('**/cdn.stub/**', (r) =>
    r.fulfill({ status: 200, contentType: 'image/gif', body: PIXEL }),
  );
}

/// A 64×48 opaque PNG in one colour, standing in for a salon's photo.
///
/// **Not [PIXEL]:** a card's `<img>` has a `srcset` of `w` descriptors, so its
/// `naturalWidth` is the file's width over its density. A 1×1 file at density 1.07 reads
/// 0, exactly as a photo that failed does, and any check on it would pass for the wrong
/// reason (measured). Opaque, so a spec can see that it covers the letter under it.
export const PHOTO = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAARElEQVR42u3PQQkAAAgEsOtkAYPYP4cV/AqDFVim67UICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICFwtOmO0iJ9REJ4AAAAASUVORK5CYII=',
  'base64',
);
export const PHOTO_COLOUR = 'rgb(92,64,51)';

/// `next/image`'s side of the stub's photos, for a spec that wants one painted
/// (docs/design/web-swiss-cards.md §8). The Next server cannot fetch `cdn.stub`, so
/// every `/_next/image` of it fails on its own; this answers [PHOTO] instead, and a 404
/// for the fixtures' `absent.jpg`, the one photo meant to fail.
export async function routeNextImages(page: Page): Promise<void> {
  await page.route('**/_next/image**', (r) => {
    const source = new URL(r.request().url()).searchParams.get('url') ?? '';
    return source.endsWith('/absent.jpg')
      ? r.fulfill({ status: 404, body: '' })
      : r.fulfill({ status: 200, contentType: 'image/png', body: PHOTO });
  });
}

export type Region = { x: number; y: number; width: number; height: number };

/// **What a box actually paints in a region of it**, from a screenshot read on a canvas.
///
/// Computed style proves a rule exists, not that it paints: a failed photo's `::after`
/// can be declared and still leave Chromium's broken-image mark in the corner. The
/// canvas is on a blank page of its own, so nothing of the page under test touches it.
/// `dark` counts the pixels well below the tile's fill, which is the salon's letter.
export async function paintedIn(
  box: Locator,
  region: (size: { width: number; height: number }) => Region,
): Promise<{ colours: string[]; dark: number; width: number; height: number }> {
  const shot = (await box.screenshot()).toString('base64');
  const blank = await box.page().context().newPage();
  try {
    const size = await box.evaluate((el) => {
      const b = el.getBoundingClientRect();
      return { width: b.width, height: b.height };
    });
    const r = region(size);
    return await blank.evaluate(
      async ({ shot, r }) => {
        const image = new Image();
        image.src = `data:image/png;base64,${shot}`;
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = image.naturalWidth;
        canvas.height = image.naturalHeight;
        const context = canvas.getContext('2d')!;
        context.drawImage(image, 0, 0);
        const { data } = context.getImageData(
          Math.round(r.x),
          Math.round(r.y),
          Math.round(r.width),
          Math.round(r.height),
        );
        const colours = new Set<string>();
        let dark = 0;
        for (let i = 0; i < data.length; i += 4) {
          colours.add(`rgb(${data[i]},${data[i + 1]},${data[i + 2]})`);
          if (data[i] < 128 && data[i + 1] < 128 && data[i + 2] < 128) dark += 1;
        }
        return {
          colours: [...colours],
          dark,
          width: image.naturalWidth,
          height: image.naturalHeight,
        };
      },
      { shot, r },
    );
  } finally {
    await blank.close();
  }
}
