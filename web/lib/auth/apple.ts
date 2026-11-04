import { loadScript } from '../loadScript';

/// Sign in with Apple on the web — ONE implementation for the client's and
/// the salon's sign-in (docs/design/web-pro-apple.md §3). Moved out of
/// `LoginOptions.tsx`, where the client flow lived alone.

declare global {
  interface Window {
    AppleID?: {
      auth: {
        init: (config: {
          clientId: string;
          scope: string;
          redirectURI: string;
          usePopup: boolean;
        }) => void;
        signIn: (options?: {
          nonce?: string;
        }) => Promise<{
          /// `code`: the one-time authorization code (B6.7).
          authorization: { id_token: string; code?: string };
          user?: { name?: { firstName?: string; lastName?: string } };
        }>;
      };
    };
  }
}

const APPLE_JS =
  'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';

export function randomNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export type AppleIdentity = {
  identityToken: string;
  nonce: string;
  /// Apple sends the name on the FIRST authorisation only.
  fullName?: string;
  /// Apple's one-time code (B6.7): the server exchanges it for the refresh
  /// token it revokes when the account is deleted
  /// (docs/design/backend-integrity-batch6.md §13).
  authorizationCode?: string;
};

/// Opens Apple's popup; resolves to the identity, or null when the person
/// closed it or the script failed — a cancel is silent, never an error line.
///
/// `redirectURI` is the CLIENT sign-in's for both spaces: in popup mode the
/// page never navigates, but Apple still requires a return URL registered for
/// the Services ID, and that one already is — no Apple console change for the
/// Pro side.
export async function appleIdentity(clientId: string): Promise<AppleIdentity | null> {
  try {
    await loadScript(APPLE_JS);
    if (!window.AppleID) return null;
    const nonce = randomNonce();
    window.AppleID.auth.init({
      clientId,
      scope: 'name email',
      redirectURI: `${window.location.origin}/connexion`,
      usePopup: true,
    });
    const res = await window.AppleID.auth.signIn({ nonce });
    const name = res.user?.name;
    const fullName = [name?.firstName, name?.lastName].filter(Boolean).join(' ');
    const code = res.authorization.code;
    return {
      identityToken: res.authorization.id_token,
      nonce,
      fullName: fullName || undefined,
      ...(code ? { authorizationCode: code } : {}),
    };
  } catch {
    return null;
  }
}
