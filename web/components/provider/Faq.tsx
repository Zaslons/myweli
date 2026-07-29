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
                remaining", which is now wrong for the fifth time.
                **Padding, NOT `flex`.** The first attempt used `flex
                items-center` to centre the label, and the adversarial review
                caught what that costs: a `<summary>`'s disclosure triangle is
                its `::marker`, and a marker only renders while the element is
                `display: list-item`. `flex` deletes it — trading a 48px target
                for the affordance that says the row opens, on every public
                salon page. Vertical centring is not worth that; the label sits
                at the top of a box that clears the floor, and the triangle
                stays. */}
            <summary className="min-h-12 cursor-pointer py-s font-medium text-textPrimary">
              {it.question}
            </summary>
            <p className="mt-xs text-bodyLarge text-textSecondary">{it.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
