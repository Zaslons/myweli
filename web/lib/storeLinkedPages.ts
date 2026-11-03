/// The five pages of our site that the apps open: support, privacy, the CGU, the
/// mentions légales, the deletion page. Two of them are also App Store Connect's Support
/// and Privacy URLs. **They carry no link to sign-up, to the Espace pro or to the offers.**
///
/// Apple refused build 698 of MyWeli Pro under 3.1.1 and asked to « remove features,
/// account registration links, and any other links to your site that could indirectly
/// provide access to external purchase mechanisms ». The app keeps these pages, since
/// privacy and support are required, so the pages lost the direct links. Every other page
/// keeps them: that is where salons look for the door, and the owner accepted that a salon
/// reading one of these five goes through the logo instead
/// (docs/design/app-review-round-2.md §5).
///
/// **The other half of this list is `AppConfig`'s five getters**, in
/// `mobile/lib/core/config/app_config.dart`. `tests/store-linked-pages.test.tsx` reads
/// that file, so a new link from the app to the site fails CI until its page is added
/// here, or the link is dropped.
export const STORE_LINKED_PATHS = [
  '/support',
  '/politique-confidentialite',
  '/cgu',
  '/mentions-legales',
  '/suppression-compte',
] as const;

const PATHS: ReadonlySet<string> = new Set(STORE_LINKED_PATHS);

/// Exact, never a prefix: `/cgu/x` and `/supports` are other pages. The query and fragment
/// go. Percent-encoding goes too, because on hydration a path reaches here as typed: the
/// server answers `/%63gu` with the static `/cgu`, rendered for `/cgu`, so a spelling this
/// misses brings the four links back on load, with React errors.
///
/// **So is a run of slashes and backslashes at either end, encoded or not.** Read on
/// myweli.com: `/cgu%2F`, `/%2Fcgu`, `/%5C/cgu` and `/cgu%2F%5C` answer the page, and
/// `/cgu%2Fx`, `/.%2Fcgu`, `/cgu%20` and `/cgu%252F` answer a 404, which keeps the links.
/// That is one decode and one segment, and `decodeURI` will not do: it leaves `%2F` alone.
/// This follows production: `next start` answers `/cgu%2F` with a 404. A path too malformed
/// to decode is not one of the five.
///
/// The pattern is anchored so that it stays linear. `.replace(/[/\\]+$/, '')` is the
/// obvious spelling and quadratic: 100 ms for a run of 14,000, twice per render, now that a
/// visitor can put such a run here with `%2F`.
export function isStoreLinkedPage(pathname: string): boolean {
  const segment = /^[/\\]+([^/\\]+)[/\\]*$/.exec(decoded(pathname.split(/[?#]/, 1)[0]))?.[1];
  return segment !== undefined && PATHS.has(`/${segment}`);
}

function decoded(path: string): string {
  try {
    return decodeURIComponent(path);
  } catch {
    return path;
  }
}
