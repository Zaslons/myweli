/// API base for server-side (BFF route handler) calls. Prefer the server-only
/// `API_BASE_URL` (internal URL, not exposed to the bundle); fall back to the
/// public base for dev/e2e. Design: docs/design/web-m5-booking.md.
export const apiBase =
  process.env.API_BASE_URL ??
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  'http://localhost:8080';
