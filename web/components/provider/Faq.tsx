/// FAQ accordion via native <details> — zero JS (good for CWV + a11y). The same
/// items feed the FAQPage JSON-LD (AEO).
export function Faq({
  items,
}: {
  items: { question: string; answer: string }[];
}) {
  if (items.length === 0) return null;
  return (
    <section className="max-w-content px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">
        Questions fréquentes
      </h2>
      <div className="mt-m divide-y divide-divider">
        {items.map((it) => (
          <details key={it.question} className="py-s">
            {/* B11 closes §15 row 26: this `<summary>` measured ≈35px against
                SYSTEM.md §13.2's 48px floor — a survivor of row 7h's "0
                remaining", which is now wrong for the fifth time. `flex` because
                a bare `min-h` on a `<summary>` does not centre its marker. */}
            <summary className="flex min-h-12 cursor-pointer items-center font-medium text-textPrimary">
              {it.question}
            </summary>
            <p className="mt-xs text-bodyLarge text-textSecondary">{it.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
