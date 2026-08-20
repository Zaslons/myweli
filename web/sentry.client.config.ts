import * as Sentry from '@sentry/nextjs';

import { scrubEvent } from './lib/sentry-scrub';

/// Sentry for the client runtime (docs/design/observability-error-reporting.md §5).
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
  // **Errors, and NOTHING ELSE leaves the browser.**
  //
  // The privacy policy says « nous n'envoyons aucun rapport à Sentry lorsque
  // rien n'a échoué » and « aucun outil de mesure d'audience ». Measured on
  // production 2026-08-20, both were FALSE: a clean page load with no error
  // sent three envelopes — a session with `errors: 0` carrying the session id,
  // the release and the full user-agent, plus the visitor's IP at the network
  // layer, to Germany. `browserSessionIntegration` is Sentry Release Health,
  // which counts sessions and users; that is audience measurement.
  //
  // This is the SECOND time a published denial about Sentry has been false
  // here. Rather than soften the sentence, the software is made to match it:
  //
  //   BrowserSession  — sends a session envelope per page load. Removed.
  //   BrowserTracing  — builds pageload transactions. `tracesSampleRate: 0`
  //                     drops them, but the DROP itself is reported in a
  //                     `client_report` envelope, so "nothing is sent" was
  //                     still untrue. Removed, so nothing is built to drop.
  //
  // Anything added here later must keep that sentence true, or change it.
  integrations: (defaults) =>
    defaults.filter(
      (i) => i.name !== 'BrowserSession' && i.name !== 'BrowserTracing',
    ),
});
