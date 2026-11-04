'use client';

import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

import { ErrorState } from '../components/ErrorState';
import { SITE_CONTAINER } from '../lib/siteGrid';

/// The route-segment error boundary — every unhandled render or data error in a
/// page lands here (docs/design/observability-error-reporting.md §5).
///
/// **There was none.** A thrown error showed Next's default error page, in
/// English, with no way out and nothing reported — the web equivalent of the
/// backend's missing error edge.
///
/// It reuses [ErrorState] rather than restating the shape: §12/B6 already settled
/// that an error state is "a human French message + a RETRY control", and that
/// "an error state without a way out is a crash with better manners." Next's
/// `reset` IS that retry — it re-renders the segment — so the two contracts meet
/// exactly.
///
/// `title` is passed because this replaces a whole page, and §4 requires one h1
/// per page in every state: without it the heading skeleton disappears precisely
/// when a user most needs to know where they are.
///
/// **On the grid, with no pattern, unlike the 404.** This file's chunk is in every
/// page's scripts, so a pattern here would cost every visitor for a page few ever see
/// (docs/design/web-swiss-direction.md §13.2).
export default function Error({
  error,
  reset,
}: {
  error: globalThis.Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // `digest` is the server-side error's id — the only link between this page
    // and the server log line that produced it, so it goes in as a tag.
    Sentry.captureException(error, {
      tags: { boundary: 'route', digest: error.digest ?? 'none' },
    });
  }, [error]);

  return (
    <main className={`${SITE_CONTAINER} py-xl lg:py-xxl`}>
      <ErrorState
        title="Une erreur est survenue"
        message="Nous n’avons pas pu afficher cette page. Réessayez dans un instant."
        onRetry={reset}
      />
    </main>
  );
}
