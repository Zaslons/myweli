'use client';

import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

/// The last boundary — a failure in the **root layout itself**, which
/// `app/error.tsx` cannot catch because it renders *inside* that layout.
///
/// **It must render its own `<html>` and `<body>`**, because it replaces the
/// root layout rather than sitting within it. That is also why it cannot use
/// `ErrorState`, the header, the fonts, or anything else the layout provides:
/// the thing that failed is the thing those come from. Tailwind classes still
/// apply — the stylesheet is linked by the build, not by the layout — but this
/// deliberately assumes as little as possible.
///
/// In practice it should never render. It exists so that when it does, the user
/// sees a French sentence and a way out instead of a blank page, and we hear
/// about it.
export default function GlobalError({
  error,
  reset,
}: {
  error: globalThis.Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error, {
      tags: { boundary: 'global', digest: error.digest ?? 'none' },
    });
  }, [error]);

  return (
    <html lang="fr">
      <body>
        <main className="mx-auto max-w-3xl px-m py-xxl text-center">
          <h1 className="text-headlineMedium font-semibold text-textPrimary">
            Une erreur est survenue
          </h1>
          <p className="mt-m text-bodyLarge text-textSecondary">
            Nous n’avons pas pu charger MyWeli. Réessayez dans un instant.
          </p>
          <button
            type="button"
            onClick={reset}
            className="mt-l inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-labelLarge font-medium text-secondary"
          >
            Réessayer
          </button>
        </main>
      </body>
    </html>
  );
}
