import Image from 'next/image';
import Link from 'next/link';
import { SITE_CONTAINER, SITE_EDGE } from '../lib/siteGrid';
import { HeaderBell } from './HeaderBell';

/// Site header — brand lockup + account entry. Static (the account page gates
/// itself). The logo is the MyWeli lockup SVG (black on the light header).
///
/// « Espace pro » is the salons' door (docs/design/web-pro-access.md P1) — top
/// right, where every booking platform puts it (Jakob's law). From `sm` up:
/// at 320–375 px the lockup, it, the bell and « Mon compte » do not fit one
/// line; phones reach it through the footer group and the home band.
///
/// `salonDoor` is off on the five pages the apps open, where it is not rendered at
/// all: a link hidden by CSS is still in the HTML (docs/design/app-review-round-2.md
/// §5). The logo still goes home.
export function Header({
  fullWidth = false,
  salonDoor = true,
}: {
  fullWidth?: boolean;
  salonDoor?: boolean;
}) {
  return (
    <header className="border-b border-primary">
      <nav className={`${fullWidth ? SITE_EDGE : SITE_CONTAINER} flex items-center justify-between py-s`}>
        <Link href="/" aria-label="MyWeli — accueil" className="-my-s flex min-h-12 items-center">
          <Image
            src="/brand/myweli_lockup_horizontal_black.svg"
            alt="MyWeli"
            width={126}
            height={50}
            priority
            unoptimized
            className="h-8 w-auto"
          />
        </Link>
        <div className="flex items-center gap-m">
          {salonDoor ? (
            <Link
              href="/professionnels"
              className="-my-s hidden min-h-12 items-center text-labelLarge font-medium text-textPrimary hover:text-textSecondary sm:inline-flex"
            >
              Espace pro
            </Link>
          ) : null}
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
