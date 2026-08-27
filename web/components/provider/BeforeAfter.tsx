import type { Provider } from '../../lib/api/providers';
import { BeforeAfterViewer } from './BeforeAfterViewer';

type Pair = NonNullable<Provider['beforeAfters']>[number];

/// Salon before/after pairs (FR-DISC-006) — the drag-reveal comparator, at
/// last (docs/design/web-provider-before-after.md). This stays the server
/// shell (section + heading); the reveal state lives in the client leaf, the
/// Gallery.tsx boundary idiom. Hidden when there are none.
export function BeforeAfter({ pairs }: { pairs: Pair[] }) {
  if (!pairs || pairs.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">
        Avant / Après
      </h2>
      <div className="mt-m">
        <BeforeAfterViewer pairs={pairs} />
      </div>
    </section>
  );
}
