/// The single place the API base URL is resolved (docs/design/infra-staging.md §1.3).
///
/// ## Why this is not just a `??` chain
///
/// It used to be, in two files, both ending `?? 'http://localhost:8080'`. On the
/// face of it that is harmless — a misconfigured deployment would fail loudly
/// with connection errors on every request.
///
/// Except the build-time path does not fail loudly. `lib/api/localities.ts` and
/// `lib/api/providers.ts` catch and degrade to empty results, and the ISR pages
/// call them during `next build`. So a production deploy missing this variable
/// does not error: it **publishes a marketplace with no salons in it**, looking
/// merely new rather than broken.
///
/// So the default is now scoped to where it is actually correct — development
/// and test — and production refuses to resolve without an explicit value.
///
/// Copy `.env.example` to `.env.local` for local work; Next.js loads it
/// automatically, including for a local `next build`.
const LOCALHOST = "http://localhost:8080";

/// Resolves the API base for **server-side** callers (BFF route handlers and
/// server components).
///
/// Prefers the server-only `API_BASE_URL` — an internal URL that never reaches
/// the browser bundle — then the public one.
export function resolveApiBase(): string {
  return resolve(
    process.env.API_BASE_URL ?? process.env.NEXT_PUBLIC_API_BASE_URL,
    "API_BASE_URL (or NEXT_PUBLIC_API_BASE_URL)",
  );
}

/// Resolves the API base for the **typed client**, which is inlined into any
/// bundle that imports it, so only the `NEXT_PUBLIC_` value is legitimate here.
export function resolvePublicApiBase(): string {
  return resolve(
    process.env.NEXT_PUBLIC_API_BASE_URL,
    "NEXT_PUBLIC_API_BASE_URL",
  );
}

function resolve(configured: string | undefined, names: string): string {
  const trimmed = configured?.trim();
  if (trimmed) return trimmed;
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      `${names} must be set in production. Refusing to fall back to ` +
        `${LOCALHOST}: the build-time fetches degrade to empty results rather ` +
        `than failing, so this would publish a site with no salons in it and ` +
        `no error anywhere. Set it per Vercel environment — Production to the ` +
        `production API, Preview to staging (docs/LAUNCH.md §5.4).`,
    );
  }
  return LOCALHOST;
}
