import type { NextRequest } from 'next/server';

/// Server side of the Apple sign-in BFFs (B6.7 —
/// docs/design/backend-integrity-batch6.md §13): Apple's one-time `code`
/// goes on to the backend, which exchanges it for the refresh token it
/// revokes when the account is deleted. Apple requires, for a WEB code, the
/// redirect URI of the authorization — the one `lib/auth/apple.ts` gave it,
/// `<this origin>/connexion`. Derived here from the request's own origin,
/// NEVER from a value the browser sends.
export function appleCodeFields(
  req: NextRequest,
  code: unknown,
): { authorizationCode?: string; redirectUri?: string } {
  if (typeof code !== 'string' || code.length === 0) return {};
  return { authorizationCode: code, redirectUri: `${req.nextUrl.origin}/connexion` };
}
