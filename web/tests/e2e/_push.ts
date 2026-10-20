import type { Page } from '@playwright/test';

/// **Headless Chromium answers `denied` before anyone was asked.** The shell
/// Playwright runs has no permission prompt, so `Notification.permission`
/// reads `denied` on a browser that never saw the question — a real Chrome
/// reads `default`. Seen on the first e2e run of the browser notifications
/// (docs/design/web-pro-browser-push.md): every new test met « Notifications
/// bloquées pour ce navigateur » on a fresh browser.
///
/// This makes the page see the real browser's state: `denied` reads as
/// `default` (not asked yet); `granted` — after
/// `context.grantPermissions(['notifications'])` — still reads as `granted`.
/// Call it before the first navigation (it is an init script).
export async function asUnaskedBrowser(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const own = Object.getOwnPropertyDescriptor(Notification, 'permission');
    const real = (): string => (own?.get ? (own.get.call(Notification) as string) : 'default');
    Object.defineProperty(Notification, 'permission', {
      configurable: true,
      get: () => (real() === 'denied' ? 'default' : real()),
    });
  });
}
