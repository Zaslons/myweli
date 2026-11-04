/// `/pro` or `/pro/…` exactly. The prefix test this used to be
/// (`startsWith('/pro')`) also caught `/professionnels`, the public page for
/// salons (docs/design/web-pro-access.md §1.3).
export function isProRoute(pathname: string): boolean {
  return pathname === '/pro' || pathname.startsWith('/pro/');
}
