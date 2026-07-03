'use client';

import { useRouter } from 'next/navigation';
import { ProLoginOptions } from './ProLoginOptions';

export function ProConnexionClient() {
  const router = useRouter();
  return <ProLoginOptions onSuccess={() => router.replace('/pro')} />;
}
