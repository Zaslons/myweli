/// Pure helpers for the consumer notification center (parity 5.1). Unit-tested.

export type AppNotification = {
  id: string;
  type: string;
  title: string;
  body: string;
  createdAt: string;
  read: boolean;
  route?: string | null;
};

export type NotificationPrefs = {
  reminders: boolean;
  marketing: boolean;
  push: boolean;
};

/// The backend notifier only ever writes app deep links; map the known ones to
/// their web equivalent. Unknown/null → no navigation.
export function webRouteFor(route: string | null | undefined): string | null {
  if (!route) return null;
  if (route === '/bookings' || route.startsWith('/bookings/')) {
    return '/mon-compte';
  }
  return null;
}

export function unreadCount(items: AppNotification[]): number {
  return items.filter((n) => !n.read).length;
}
