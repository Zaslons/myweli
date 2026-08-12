/// Loads the Sentry SDK for the server and edge runtimes.
///
/// **Next 14 does not load `sentry.server.config.ts` on its own**, and neither
/// does `withSentryConfig` for the server side in this SDK version — the file
/// sits there looking wired while `Sentry.init` never runs. That was the state
/// of this PR for one commit: the config files existed, the build was green, and
/// nothing was reported. Verified by grepping the built output for `sentry` and
/// finding nothing.
///
/// Requires `experimental.instrumentationHook` on Next 14 (stable from 15).
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./sentry.server.config');
  }
  if (process.env.NEXT_RUNTIME === 'edge') {
    await import('./sentry.edge.config');
  }
}
