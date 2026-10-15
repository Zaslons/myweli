'use client';

import { useRouter } from 'next/navigation';
import { logoutPro } from '../../lib/api/pro';
import { Button } from '../Button';

/// « Se déconnecter ». `redirectTo` lets a host land somewhere other than the
/// bare login — the rejoin gate signs out onto the « accès retiré » banner
/// (docs/design/pro-rejoin-gate.md S8). A failed logout call (no network)
/// still leaves: the page never strands someone on a button that does nothing.
export function ProLogoutButton({
  redirectTo = '/pro/connexion',
}: {
  redirectTo?: string;
}) {
  const router = useRouter();
  return (
    <Button
      variant="secondary"
      onClick={async () => {
        await logoutPro().catch(() => undefined);
        router.replace(redirectTo);
      }}
    >
      Se déconnecter
    </Button>
  );
}
