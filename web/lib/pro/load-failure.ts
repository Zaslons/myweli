import { NO_CONNECTION_MESSAGE } from '../api/network';

/// Why a Pro page's read failed, as its error state needs it — design:
/// docs/design/web-pro-no-connection-copy.md §2.
///
/// `'offline'`: no usable answer reached the browser — status 0 from the
/// lib/api/pro.ts wrappers (no network, a body cut on the way, an unreadable
/// 2xx: web-pro-network-failure.md §2). `'failed'`: the server answered with a
/// failure. The same two words as `logoutPro`. A page keeps
/// `LoadFailure | false` where it kept a boolean: `false` is still « no error ».
export type LoadFailure = 'offline' | 'failed';

/// The failure of the reads that just ran: one of them got no answer → the
/// person's connection. A 200 among them is not 0, so it never counts.
export function loadFailure(...statuses: number[]): LoadFailure {
  return statuses.includes(0) ? 'offline' : 'failed';
}

/// The error state's sentence: the app's « Pas de connexion. Réessayez. »
/// (every api_*_service.dart) when nothing answered — over the page's own
/// sentence, which does not say why. Otherwise the page's own sentence, or
/// `undefined`: ErrorState's default, untouched. Takes the page's state as it
/// is (`false` too, where an error state also covers a missing document).
export function loadFailureMessage(
  failure: LoadFailure | false,
  message?: string,
): string | undefined {
  return failure === 'offline' ? NO_CONNECTION_MESSAGE : message;
}
