import type { Metadata } from 'next';
import { AujourdhuiClient } from '../../../components/pro/AujourdhuiClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Aujourd’hui',
  robots: { index: false, follow: false },
};

export default function ProHomePage() {
  return <AujourdhuiClient />;
}
