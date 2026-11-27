/// What the revenue BFF forwards to the backend: the parameters §7.1/§7.2
/// name, and nothing else — anything the page did not mean to send stays
/// here. The backend validates every value (400 `invalid_input`). Pure.

const ANALYTICS = [
  'period',
  'date',
  'from',
  'to',
  'compare',
  'artistId',
  'serviceId',
  'channel',
] as const;

/// The ledger has no comparison, and pages (§7.2).
const LEDGER = [
  'period',
  'date',
  'from',
  'to',
  'artistId',
  'serviceId',
  'channel',
  'status',
  'page',
  'pageSize',
  'asOf',
] as const;

export function forwardRevenueParams(
  incoming: URLSearchParams,
  kind: 'analytics' | 'ledger',
): string {
  const out = new URLSearchParams();
  for (const name of kind === 'analytics' ? ANALYTICS : LEDGER) {
    const v = incoming.get(name);
    if (v != null) out.set(name, v);
  }
  const s = out.toString();
  return s ? `?${s}` : '';
}
