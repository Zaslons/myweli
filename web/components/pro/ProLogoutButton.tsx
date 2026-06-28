'use client';

import { useRouter } from 'next/navigation';
import { logoutPro } from '../../lib/api/pro';
import { Button } from '../Button';

export function ProLogoutButton() {
  const router = useRouter();
  return (
    <Button
      variant="secondary"
      onClick={async () => {
        await logoutPro();
        router.replace('/pro/connexion');
      }}
    >
      Se déconnecter
    </Button>
  );
}
