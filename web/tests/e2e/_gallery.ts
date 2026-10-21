import type { Page } from '@playwright/test';

/// **The stub's salon gallery is shared by every e2e, and CI runs two
/// workers.** A test that deletes a photo and then presses « Annuler » leaves
/// the gallery a photo short for a few seconds — and `pro.spec.ts`'s
/// « médias », on the other worker, counted it mid-way: Expected 3, Received 2,
/// on #666's two CI runs. Its timing on main had simply put the count first
/// (0.1 s apart); one more booking e2e moved the schedule.
///
/// Waiting for the restore to be saved does not help: the window between the
/// delete and the undo is still there. So a test that only needs the SCREENS —
/// the delete question, the toast, « Annuler » — answers its own gallery saves
/// in the browser, and the shared gallery never changes. `pro.spec.ts`'s
/// « médias » is the one test that really saves.
export async function keepSharedGallery(page: Page): Promise<void> {
  await page.route('**/api/pro/medias/gallery', async (route) => {
    if (route.request().method() !== 'PUT') return route.continue();
    const sent = JSON.parse(route.request().postData() ?? '{}') as { imageUrls?: string[] };
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ imageUrls: sent.imageUrls ?? [] }),
    });
  });
}
