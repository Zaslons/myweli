import Image from 'next/image';
import Link from 'next/link';
import { HeaderBell } from './HeaderBell';

/// Site header — brand lockup + account entry. Static (the account page gates
/// itself). The logo is the MyWeli lockup SVG (black on the light header).
///
/// « Espace pro » is the salons' door (docs/design/web-pro-access.md P1) — top
/// right, where every booking platform puts it (Jakob's law). From `sm` up:
/// at 320–375 px the lockup, it, the bell and « Mon compte » do not fit one
/// line; phones reach it through the footer group and the home band.
export function Header() {
  return (
    <header className="border-b border-divider bg-secondary">
      <nav className="mx-auto flex max-w-5xl items-center justify-between px-m py-s">
        <Link href="/" aria-label="MyWeli — accueil" className="-my-s flex min-h-12 items-center">
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
          <Link
            href="/professionnels"
            className="-my-s hidden min-h-12 items-center text-labelLarge font-medium text-textPrimary hover:text-textSecondary sm:inline-flex"
          >
            Espace pro
          </Link>
          <HeaderBell />
          <Link
            href="/mon-compte"
            className="-my-s inline-flex min-h-12 items-center text-labelLarge font-medium text-textPrimary hover:text-textSecondary"
          >
            Mon compte
          </Link>
        </div>
      </nav>
    </header>
  );
}
