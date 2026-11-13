import type { Metadata } from 'next';
import { AujourdhuiClient } from '../../../components/pro/AujourdhuiClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Aujourd’hui',
  robots: { index: false, follow: false },
};

export default function ProHomePage({
  searchParams,
}: {
  /// `?salon=` — a notice about one of the account's salons (B0.18: the
  /// decision's push, feed row and e-mail): the page switches to it once
  /// (docs/design/web-salon-validation.md §4.5).
  searchParams: { salon?: string | string[] };
}) {
  const salon = typeof searchParams.salon === 'string' ? searchParams.salon : undefined;
  return <AujourdhuiClient salon={salon} />;
}
