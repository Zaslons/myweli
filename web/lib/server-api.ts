import { resolveApiBase } from "./api-base";

/// API base for server-side (BFF route handler) calls. Prefer the server-only
/// `API_BASE_URL` (internal URL, not exposed to the bundle); fall back to the
/// public base for dev/e2e. Design: docs/design/web-m5-booking.md.
///
/// **The localhost fallback is now development-only** — see `api-base.ts` for
/// why a production fallback was a silent failure rather than a loud one.
export const apiBase = resolveApiBase();
