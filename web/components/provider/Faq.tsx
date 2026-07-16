/// FAQ accordion via native <details> — zero JS (good for CWV + a11y). The same
/// items feed the FAQPage JSON-LD (AEO).
export function Faq({
  items,
}: {
  items: { question: string; answer: string }[];
}) {
  if (items.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">
        Questions fréquentes
      </h2>
      <div className="mt-m divide-y divide-divider">
        {items.map((it) => (
          <details key={it.question} className="py-s">
            <summary className="cursor-pointer font-medium text-textPrimary">
              {it.question}
            </summary>
            <p className="mt-xs text-bodyMedium text-textSecondary">{it.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
