import type { Locator, Page } from '@playwright/test';

/// An e-mail address as the page DRAWS it (docs/design/web-email-seams.md).
///
/// `BreakableEmail` gives a screen reader its own copy of the address (one
/// text node) and draws it `aria-hidden`, cut by `<wbr>`s at its seams — so a
/// plain `getByText(address)` finds two elements and fails strict mode. This
/// is the one a person sees. (A link that draws an address is named by its
/// `aria-label`: find it with `getByRole('link', { name })`.)
export function drawnEmail(scope: Page | Locator, address: string): Locator {
  const exact = new RegExp(`^${address.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`);
  return scope.locator('[aria-hidden="true"]').filter({ hasText: exact });
}
