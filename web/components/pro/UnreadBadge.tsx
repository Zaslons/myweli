import { badgeLabel } from '../../lib/pro/notifications';

/// The unread count on the salon's two notification doors — the sidebar
/// entry and the phone bell (docs/design/web-pro-notifications.md §3.1).
/// `aria-hidden`: the door's accessible name already says the number
/// (`unreadLabel`). `min-h`, never `h`: a box holding text may not have a
/// fixed height (SYSTEM §13.3 — it would clip at 200 % text).
export function UnreadBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span
      aria-hidden="true"
      className="inline-flex min-h-5 min-w-5 shrink-0 items-center justify-center rounded-pill bg-error px-xs text-labelSmall font-medium text-secondary"
    >
      {badgeLabel(count)}
    </span>
  );
}
