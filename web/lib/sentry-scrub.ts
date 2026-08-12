import type { ErrorEvent, EventHint } from '@sentry/nextjs';

/// Strips everything that must not leave the browser or the server
/// (docs/design/observability-error-reporting.md §4.2, §5).
///
/// **The security-critical part of this slice, and the least visible.** If it is
/// wrong, session cookies and PII go to a third party and *nothing in the system
/// notices* — no test fails, no page breaks, no log line appears.
///
/// Cookies matter most here. The web session lives in **httpOnly** cookies
/// precisely so JavaScript cannot read it; forwarding them to an error tracker
/// would hand over the exact credential that design protects.
///
/// Written as a pure function rather than inline in `beforeSend` so it can be
/// tested directly — which is the only way to know it works, since a leak
/// produces no symptom.
export function scrubEvent(event: ErrorEvent, _hint?: EventHint): ErrorEvent {
  if (event.request) {
    // Rebuilt from an allowlist rather than deleting known-bad keys: an
    // allowlist stays correct when the SDK adds a field, a blocklist silently
    // does not.
    event.request = {
      method: event.request.method,
      // The URL is kept — it is the diagnosis — but its query string is not.
      url: stripQuery(event.request.url),
    };
  }

  // Nothing sets these today, and that is exactly why they are cleared: the
  // guarantee should hold for the code someone writes next year.
  delete event.user;
  delete event.breadcrumbs;
  delete event.extra;

  // `contexts` is deliberately KEPT — browser, OS and runtime metadata, no user
  // data, and the most useful thing left once the request is stripped.
  return event;
}

function stripQuery(url?: string): string | undefined {
  if (!url) return url;
  const cut = url.indexOf('?');
  return cut === -1 ? url : url.slice(0, cut);
}
