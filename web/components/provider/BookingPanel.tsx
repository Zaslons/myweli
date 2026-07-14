import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';
import { minActivePrice } from '../../lib/provider-summary';
import { BookingCta } from '../BookingCta';

/// Sticky desktop booking panel: à-partir-de price + Réserver + contact.
export function BookingPanel({
  provider,
  slug,
  disabled = false,
}: {
  provider: Provider;
  slug: string;
  disabled?: boolean;
}) {
  const min = minActivePrice(provider.services);
  const wa = provider.whatsapp?.replace(/[^0-9]/g, '');
  return (
    <div className="rounded-xl border border-border bg-secondary p-l">
      {min != null ? (
        <>
          <p className="text-xs text-textTertiary">À partir de</p>
          <p className="text-2xl font-semibold text-textPrimary">
            {formatFcfa(min, provider.currency ?? undefined)}
          </p>
        </>
      ) : null}
      <div className="mt-m">
        <BookingCta slug={slug} className="w-full" disabled={disabled} />
      </div>
      <div className="mt-m flex gap-s">
        <a
          href={`tel:${provider.phoneNumber}`}
          className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-center text-sm text-textPrimary"
        >
          Appeler
        </a>
        {wa ? (
          <a
            href={`https://wa.me/${wa}`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-center text-sm text-textPrimary"
          >
            WhatsApp
          </a>
        ) : null}
      </div>
    </div>
  );
}
