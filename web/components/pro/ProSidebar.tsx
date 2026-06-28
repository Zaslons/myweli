import Link from 'next/link';
import { ProLogoutButton } from './ProLogoutButton';

// Sidebar nav (mirrors the pro app's sections). Later ones show "Bientôt" until
// their PR lands (M7.2–M7.3).
const NAV: { label: string; href?: string }[] = [
  { label: 'Aujourd’hui', href: '/pro' },
  { label: 'Rendez-vous', href: '/pro/rendez-vous' },
  { label: 'Catalogue', href: '/pro/catalogue' },
  { label: 'Disponibilités', href: '/pro/disponibilites' },
  { label: 'Profil' },
  { label: 'Abonnement' },
];

export function ProSidebar() {
  return (
    <aside className="w-60 shrink-0 border-r border-divider bg-secondary p-m">
      <p className="px-s text-lg font-semibold text-textPrimary">Myweli Pro</p>
      <nav className="mt-l space-y-xs">
        {NAV.map((item) =>
          item.href ? (
            <Link
              key={item.label}
              href={item.href}
              className="block rounded-lg px-s py-s text-sm text-textPrimary hover:bg-surfaceVariant"
            >
              {item.label}
            </Link>
          ) : (
            <span
              key={item.label}
              className="flex items-center justify-between rounded-lg px-s py-s text-sm text-textTertiary"
            >
              {item.label}
              <span className="text-xs">Bientôt</span>
            </span>
          ),
        )}
      </nav>
      <div className="mt-l px-s">
        <ProLogoutButton />
      </div>
    </aside>
  );
}
