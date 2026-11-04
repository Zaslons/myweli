import { buildFailsClosed } from '../build-posture';

/// What a public page's read does with an answer it cannot use — a refusal,
/// no answer, or a 200 without what it asked for (docs/design/hygiene-batch9.md
/// §2.10, decision Q6).
///
/// Where the build fails closed — production, local, CI — it THROWS:
/// - at ISR regeneration, Next keeps serving the last good page and tries
///   again on the next request after the window;
/// - at build time, the build fails and the previous deployment stays up.
///
/// It used to return the empty value, so a regeneration REPLACED a good page
/// with an empty marketplace — or a live salon with a 404 for the whole
/// window — and a build published a sitemap without its salons, all with
/// nothing in any log.
///
/// A Vercel PREVIEW points at staging, whose database sleeps between
/// rehearsals: it keeps degrading to [empty], the trade build-posture.ts
/// already makes for the landing pages and the redirects.
export function unreadable<T>(what: string, empty: T, cause: unknown): T {
  if (!buildFailsClosed()) return empty;
  throw new Error(
    `Public read failed: ${what}. Not publishing an empty answer in its place.`,
    { cause },
  );
}
