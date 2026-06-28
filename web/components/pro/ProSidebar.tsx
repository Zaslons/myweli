import Link from 'next/link';
import { ProLogoutButton } from './ProLogoutButton';

// Sidebar nav. Sections land across M7.1–M7.3; until then they show "Bientôt".
const NAV: { label: string; href?: string }[] = [
  { label: 'Aujourd’hui', href: '/pro' },
  { label: 'Agenda' },
  { label: 'Rendez-vous' },
  { label: 'Catalogue' },
  { label: 'Disponibilités' },
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
