import * as Sentry from '@sentry/nextjs';

import { scrubEvent } from './lib/sentry-scrub';

/// Sentry for the edge runtime (docs/design/observability-error-reporting.md §5).
///
/// **`NEXT_PUBLIC_SENTRY_DSN` unset → the SDK is inert.** Dev, CI and any
/// deployment without a DSN need no setup, and a missing DSN is never a build or
/// boot failure — the same posture as the backend's `SENTRY_DSN`, and for the
/// same reason: telemetry that can break the app is worse than no telemetry.
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_SENTRY_ENV ?? 'development',
  release: process.env.NEXT_PUBLIC_RELEASE,
  // Errors only. Performance monitoring is a separate decision with its own
  // cost; shipping it on by accident is how telemetry bills surprise people.
  tracesSampleRate: 0,
  // Belt to `scrubEvent`'s braces — the SDK must not decide to enrich events
  // with user data on our behalf.
  sendDefaultPii: false,
  beforeSend: scrubEvent,
});
