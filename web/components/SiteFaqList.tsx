/// The open FAQ of a public page (docs/design/web-swiss-cards.md §2.3): the `dl` the
/// home page and /professionnels both spelled, and now the landings too. The answers
/// are in the page, visible, and say what `FAQPage` says.
export function SiteFaqList({
  items,
}: {
  items: readonly { question: string; answer: string }[];
}) {
  return (
    <dl className="divide-y divide-divider">
      {items.map((f) => (
        <div key={f.question} className="py-m first:pt-0 last:pb-0">
          <dt className="font-medium text-textPrimary">{f.question}</dt>
          <dd className="mt-xs max-w-content text-bodyLarge text-textSecondary">{f.answer}</dd>
        </div>
      ))}
    </dl>
  );
}
