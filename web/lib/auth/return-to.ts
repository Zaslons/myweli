/// Where `/connexion` sends the person once signed in: a page of this site,
/// or « Mon compte ».
///
/// The check it replaces (`startsWith('/') && !startsWith('//')`) let
/// `/\evil.example` through, and a browser reads that as `//evil.example`:
/// another site, reached right after a sign-in on ours. The independent review
/// of A3w found it; A3w's reason line would have made such a link more
/// convincing (docs/design/consumer-signin-push.md §14.7). The address is now
/// resolved as the browser will resolve it, and kept only if it stays here.
export const DEFAULT_RETURN_TO = '/mon-compte';

export function safeReturnTo(raw: string | null | undefined, origin: string): string {
  if (!raw || !raw.startsWith('/')) return DEFAULT_RETURN_TO;
  let url: URL;
  try {
    url = new URL(raw, origin);
  } catch {
    return DEFAULT_RETURN_TO;
  }
  if (url.origin !== origin) return DEFAULT_RETURN_TO;
  return `${url.pathname}${url.search}${url.hash}`;
}
