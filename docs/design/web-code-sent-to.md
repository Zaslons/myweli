# The sign-ins' code step: the address on a line of its own

| | |
|---|---|
| **Status** | Built (2026-11-27), not merged |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Approved** | by the owner, 2026-11-27 (« Approved, build it »), on the plan in §4 |
| **Register row** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 row 39 |
| **Rule** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §9 « An e-mail address breaks only at its seams » · the app's rule, [SYSTEM.md](SYSTEM.md) §13.3 (#895) |
| **Governs** | `web/components/auth/CodeSentTo.tsx` · `emailSeams` in `web/lib/format.ts` · the code step of `web/components/auth/LoginOptions.tsx` and `web/components/pro/ProLoginOptions.tsx` · the « code step with a long address » block of `web/tests/e2e/type-overflow.spec.ts` · `web/tests/code-sent-to.test.tsx` |
| **Skills checked** | `myweli-web-guardrails`, `myweli-dev-guardrails` |
| **Builds on** | the app's `CodeSentTo` ([account-email-change.md](account-email-change.md) §12, PR #895) · [web-salon-price-reflow.md](web-salon-price-reflow.md) (the doubled-text modes) |

---

## 1. Goal & scope

Both sign-ins (`/connexion`, which the booking funnel also renders inline, and
`/pro/connexion`) open a code step that says where the code went:
« Entrez le code reçu par e-mail à {adresse}. », one inline sentence. The app
gave that sentence a new shape in #895, approved by the owner on 2026-11-27:
the sentence, then the address on a line of its own, in ink, with no period
drawn, broken only at its seams. This makes the website say it the same way.
The web mirrors the app's flow, not its pixels: the text stays left-aligned
here, where the app's sign-ins centre it.

**In scope:** the two code steps, and a gate that reaches them with a long
address. **Out of scope:** §6.

## 2. Measured before building

Main at `da6e947b`, the e2e stub, Chromium at 320×568, the committed Hanken
Grotesk (the same file on CI's Linux). The sentence is `bodyLarge`, 16 px, in a
288 px column. Both sign-ins measured alike.

**The web's defect is not the app's.** A browser never cuts inside a word, so
the address was never cut. It spilled instead:

| Text | What happened |
|---|---|
| Normal | The address never fits after « à », so the browser moves it to the next line whole: it already sat on a line of its own, with a drawn period after it and in the sentence's secondary colour. |
| **Android-style 200 %** (`text-size-adjust`, 32 px) | The layout viewport grew past the phone: **408×725** for `aminata.kone@exemple.ci`, **483×858** for `awa.kone.nouvelle@exemple.ci`, 327×581 for `koffi.yao@gmail.com`, 641×1138 for `aminata.kone.traore.nouvelle@exemple.ci`; `awa@exemple.ci` fitted. |
| Browser font at 200 % (a 32 px root) | Nothing moved: the type tokens are px (WEB-SYSTEM §9, the unit contract), so the sentence stayed 16 px. |

No gate reached the step: `type-overflow.spec.ts`'s sign-in rows measure each
page as it opens, before an address is typed.

## 3. How the address may break — the candidates, measured

The same build, each candidate put in place of the paragraph's children, at
Android-style 200 %:

| Candidate | `aminata.kone@exemple.ci` | `koffi.yao@gmail.com` | `aminata.kone.traore.nouvelle@exemple.ci` |
|---|---|---|---|
| Own line, no hint | spills, 399 px | fits (its right edge at 318) | spills, 633 px |
| Own line + `overflow-wrap: break-word` (or `anywhere`) | « aminata.kone@exe » / « mple.ci » | « koffi.yao@gmail.co » / « m » | « aminata.kone.traor » / « e.nouvelle@exempl » / « e.ci » |
| **Own line + `<wbr>` before the « @ » and each « . » of the name** | « aminata.kone » / « @exemple.ci » | « koffi.yao » / « @gmail.com » | « aminata.kone » / « .traore.nouvelle » / « @exemple.ci » |
| … and before the domain's dots too | same | « koffi.yao@gmail » / « .com » — the orphan | same |
| Inline + the same `<wbr>`s | « par e-mail à awa » / « .kone.nouvelle » / « @exemple.ci. » (`awa.kone.nouvelle@…`) — the address starts on a line the sentence began, at normal text too | | |

**A piece wider than a line by itself** (`ouattaraaminatakone@exemple.ci`):
with the `<wbr>`s alone the page grows to 332 px; with `break-word` as the
fallback it is cut inside — « ouattaraaminatako » / « ne@exemple.ci » — which
is the app's limit too: past that point no layout has more to give. A
hyphenated domain (`awa@salon-de-beaute-divine-abidjan.ci`) breaks after its
hyphens, as it did before; that is the browser's own seam.

**Decision:** the `<wbr>` seams, with `break-words` only as the fallback.
`<wbr>` rather than the app's U+200B because a `<wbr>` copies as nothing: a
selected and pasted address stays clean.

## 4. The shape (approved 2026-11-27)

```text
Entrez le code reçu par e-mail à        ← textSecondary, as before
aminata.kone                            ← textPrimary (ink), a line of its own
@exemple.ci                                no period drawn
```

- Same paragraph, same `bodyLarge`, no gap: one sentence, set in two runs.
- **What a screen reader hears does not change**: one text, « Entrez le code
  reçu par e-mail à aminata.kone@exemple.ci. », period included, from a
  visually hidden copy (`sr-only`); the drawing is `aria-hidden`. That is the
  app's single semantics node. Not the drawing itself, because its runs and
  `<wbr>`s are element boundaries, where a screen reader (VoiceOver on iOS in
  particular) may stop and read the address in pieces.
- The address is the trimmed one, as sent (`email.trim()`, as before).
- Copying: a triple-click on the address selects the address alone, clean; a
  triple-click on the sentence, the sentence alone. Only a select-all picks up
  the hidden copy as well (measured, 2026-11-27).

## 5. Tests

- **`web/tests/code-sent-to.test.tsx`** — both components driven to their code
  step with four addresses (one typed with spaces). A screen reader's text is
  the sentence, period included, exactly once; an element draws the address
  alone, `block`, in ink, inside the hidden drawing, with nothing after it; the
  `<wbr>`s cut it into exactly its seams; `break-words` is its fallback. **Red
  first** on main: 16 of 24, every drawing test on both surfaces; the 8
  screen-reader tests passed there, as they must — they hold what does not
  change.
- **`web/tests/format.test.ts`** — `emailSeams`: the seams, never the domain's
  dots, the last « @ », no piece empty, the pieces join back to the address.
- **`type-overflow.spec.ts`, « the sign-ins' code step with a long address »**
  — both sign-ins × `aminata.kone@exemple.ci`, `awa.kone.nouvelle@exemple.ci`
  × normal text, Android-style 200 %, the 32 px root, at 320×568: the
  paragraph's accessibility snapshot is the sentence; the mode applied (the
  drawn size, read when measuring); the layout viewport keeps the screen's
  size; nothing spills; the sentence ends its own line; then the address, line
  by line — whole at 16 px, at its seams at 32 px — with no period. **Red
  first** on main, all 12: the Android mode on the viewport (408×725,
  483×858), the other two on the drawn period. Green on the branch, with
  `type-overflow`, `axe`, `focus`, `tap-targets` and `favorite-after-sign-in`
  (199 tests), and an axe scan of both code steps, clean.

## 6. Not covered

- **Other addresses on the web** — the team list (`EquipeClient`), the Pro
  sidebar (`ProSidebar`) and the salon profile (`ProfilClient`) draw an
  address with `break-all`, which cuts anywhere; the legal pages' `Email` breaks
  « support@myweli.com » after its « @ » rather than before it (those pages are
  frozen while Apple reviews). Not measured here; a task of its own.
- A name piece or a domain wider than a line still breaks inside (§3).
- [SYSTEM.md](SYSTEM.md) §21 row 99 (#895, not on `main` yet) says the website
  is not covered; that clause can be struck once both are merged.
