/// The five pages of our site that the apps open, and the only ones on App Store
/// Connect's form: Support, Privacy, the CGU, the mentions légales, the deletion
/// page. **They carry no link to sign-up, to the Espace pro or to the offers.**
///
/// Apple refused build 698 of MyWeli Pro under 3.1.1 and asked to « remove features,
/// account registration links, and any other links to your site that could indirectly
/// provide access to external purchase mechanisms ». The app cannot lose these pages,
/// because privacy and support are required, so the pages lost the direct links. Every
/// other page keeps them: that is where salons look for the door, and the owner accepted
/// that a salon reading one of these five goes through the logo instead
/// (docs/design/app-review-round-2.md §5).
///
/// **The other half of this list is `AppConfig`'s five getters**, in
/// `mobile/lib/core/config/app_config.dart`. `tests/store-linked-pages.test.tsx` reads
/// that file, so a new link from the app to the site fails CI until it is added here,
/// and so hidden from sign-up, or removed.
export const STORE_LINKED_PATHS = [
  '/support',
  '/politique-confidentialite',
  '/cgu',
  '/mentions-legales',
  '/suppression-compte',
] as const;

const PATHS: ReadonlySet<string> = new Set(STORE_LINKED_PATHS);

/// Exact, never a prefix: `/cgu/x` and `/supports` are other pages. `usePathname` hands
/// over a bare path, and the query, fragment and trailing slash go anyway, so that no
/// spelling of these five can bring the links back.
export function isStoreLinkedPage(pathname: string): boolean {
  return PATHS.has(pathname.split(/[?#]/, 1)[0].replace(/\/+$/, ''));
}
