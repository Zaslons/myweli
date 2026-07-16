import Image from 'next/image';
import Link from 'next/link';
import { HeaderBell } from './HeaderBell';

/// Site header — brand lockup + account entry. Static (the account page gates
/// itself). The logo is the MyWeli lockup SVG (black on the light header).
export function Header() {
  return (
    <header className="border-b border-divider bg-secondary">
      <nav className="mx-auto flex max-w-5xl items-center justify-between px-m py-s">
        <Link href="/" aria-label="MyWeli — accueil" className="flex items-center">
          <Image
            src="/brand/myweli_lockup_horizontal_black.svg"
            alt="MyWeli"
            width={126}
            height={50}
            priority
            unoptimized
            className="h-7 w-auto"
          />
        </Link>
        <div className="flex items-center gap-m">
          <HeaderBell />
          <Link
            href="/mon-compte"
            className="text-labelLarge font-medium text-textPrimary hover:text-textSecondary"
          >
            Mon compte
          </Link>
        </div>
      </nav>
    </header>
  );
}
