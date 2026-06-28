import Link from 'next/link';

/// Site header — logo + account entry. Static (the account page gates itself).
export function Header() {
  return (
    <header className="border-b border-divider bg-secondary">
      <nav className="mx-auto flex max-w-5xl items-center justify-between px-m py-s">
        <Link href="/" className="text-lg font-semibold text-textPrimary">
          Myweli
        </Link>
        <Link
          href="/mon-compte"
          className="text-sm font-medium text-textPrimary hover:text-textSecondary"
        >
          Mon compte
        </Link>
      </nav>
    </header>
  );
}
