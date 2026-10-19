import type { Metadata } from 'next';
import { ProNotificationsClient } from '../../../../components/pro/ProNotificationsClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Notifications',
  robots: { index: false, follow: false },
};

/// The salon's notification center (docs/design/web-pro-notifications.md).
export default function ProNotificationsPage() {
  return <ProNotificationsClient />;
}
