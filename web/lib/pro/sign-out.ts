import { type LogoutOutcome, logoutPro } from '../api/pro';
import { unregisterBeforeSignOut } from './browser-push';
import { getBrowserPushDeps } from './browser-push-deps';
import { forgetSalon } from './remembered-salon';

/// A member's sign-out from this browser: its notification token first, so a
/// shared salon computer stops receiving the alerts of a member who left it
/// (docs/design/web-pro-browser-push.md §2.6) — then the session. Bounded:
/// the token step never holds a sign-out more than a few seconds. A sign-out
/// that landed also forgets the salon this browser remembered (decision 14);
/// one that did not leaves the session — and the salon's name — as they were.
export async function signOutPro(): Promise<LogoutOutcome> {
  await unregisterBeforeSignOut(getBrowserPushDeps());
  const outcome = await logoutPro();
  if (outcome === 'ok') forgetSalon();
  return outcome;
}
