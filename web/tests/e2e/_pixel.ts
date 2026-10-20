import type { Page } from '@playwright/test';

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
