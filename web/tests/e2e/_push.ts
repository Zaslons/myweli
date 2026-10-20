import type { BrowserContext, Page } from '@playwright/test';

/// **Headless Chromium's `Notification.permission` is stuck at `denied`.**
/// Measured 2026-10-20 with a bare page: `denied` before any question, still
/// `denied` after `context.grantPermissions(['notifications'])`, still
/// `denied` after `Notification.requestPermission()` itself answered
/// `granted`, and still `denied` after a reload. A real browser reads
/// `default` until asked, then its answer. Seen on the first e2e run of the
/// browser notifications (docs/design/web-pro-browser-push.md): every new test
/// met « Notifications bloquées pour ce navigateur » on a fresh browser.
///
/// These make the page read what a real browser would: the answer
/// `requestPermission()` gave, kept across reloads (as a browser keeps it).
/// The question itself still goes to Chromium — it answers `granted` once the
/// test called `context.grantPermissions`.
const SLOT = '__e2e_notification_permission';

async function realBrowserPermission(page: Page): Promise<void> {
  await page.addInitScript((slot) => {
    const read = (): string => {
      try {
        return window.localStorage.getItem(slot) ?? 'default';
      } catch {
        return 'default';
      }
    };
    Object.defineProperty(Notification, 'permission', { configurable: true, get: read });
    const ask = Notification.requestPermission.bind(Notification);
    Notification.requestPermission = (async () => {
      const answer = await ask();
      try {
        window.localStorage.setItem(slot, answer);
      } catch {
        /* the page reads default */
      }
      return answer;
    }) as typeof Notification.requestPermission;
  }, SLOT);
}

/// A computer whose browser was never asked.
export async function asUnaskedBrowser(page: Page): Promise<void> {
  await realBrowserPermission(page);
}

/// A computer whose browser already said yes (an earlier « Activer »).
export async function asGrantedBrowser(page: Page, context: BrowserContext): Promise<void> {
  await context.grantPermissions(['notifications']);
  await page.addInitScript((slot) => {
    try {
      window.localStorage.setItem(slot, 'granted');
    } catch {
      /* the page reads default */
    }
  }, SLOT);
  await realBrowserPermission(page);
}
