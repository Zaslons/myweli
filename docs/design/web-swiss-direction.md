# Web — the public site's look: Swiss structure, the MyWeli logo, a woven pattern — design spec

| | |
|---|---|
| **Status** | **Approved 2026-11-02** (decisions in §15). Direction B, with the owner's two additions: the real logo and the things that are MyWeli's own (§3), and a pattern with an African identity that **feels calm** (§4). No code yet: the untrue sentences come first (BACKLOG Batch 12), then S0. One step left with the owner: §4.8 before S1 goes live. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-02 |
| **PRD ref / phase** | FR-WEB-MP-001, FR-WEB-PP-001/002 (presentation only) · V1 |
| **Module** | Web public: `app/page.tsx`, `app/professionnels`, `app/recherche`, `app/[slug]`, `components/home`, `components/landing`, `components/provider`, `Header`, `SiteFooter`, `styles/tokens.ts` |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-verification-guardrails ✓ · no backend change |
| **Depends on** | Nothing. Web merges deploy through Vercel and do not touch the backend, so they do not trigger the Apple keys (B0.12). |

![The chosen direction: real logo, Hanken Grotesk, rows of plaits in black on white, at 1440 and 375 wide](assets/web-swiss-direction.png)

*The chosen direction, rendered at true size from a script (1440 and 375 wide). A sketch, not the final artwork.*

---

## 1. Goal & scope

**Goal.** The public site should look like one brand, made for Abidjan, on a phone and on a large screen. Today it reads as a tidy template.

**What the live site showed on 2026-11-02** (`myweli.com`, 1440 and 375 wide; Planity and Fresha for comparison):

| Finding | Evidence |
|---|---|
| No typeface of its own | Computed `ui-sans-serif, system-ui`. Planity: Aeonik + Inter. Fresha: Roobert. SYSTEM §22 lists « a brand font (Inter) » as deferred |
| A flat hierarchy | `<h1>` 32px at 1440 wide (Fresha 64, Planity 40). `displaySmall/Medium/Large` (36/45/57) exist in `tokens.ts` and **nothing on the web uses them** |
| No image | `/` has one `<img>`, the logo. The hero is pale circles (`HeroBackground`), which SYSTEM §1 calls decoration |
| The logo is small and appears once | `Header` `h-7`. The footer has none |
| No shared left edge | `Header` is `max-w-5xl`, centred. `/recherche` starts at the page edge: at 1440 the logo sits at x = 224 and the `<h1>` at x = 24 |
| Everything is a bordered box | Ten `rounded-xl border` blocks in the source of the home page, `/professionnels`, the landings, the salon card and panel, and the empty state |
| Salon cards have no photo | `ProviderCard` has none. The app's card leads with a 180-high cover: a parity gap |
| **No salon is public yet** | `GET /providers` → `total: 0`. A design that needs salon photos launches empty |

**In scope.** Tokens and rules (§5, §6), the logo and identity (§3), the pattern (§4), and these pages: `/`, `/professionnels`, `/recherche`, the taxonomy landings, the salon page, 404 and error pages, the OG image.

**Inherits only the font, header and footer, with no layout change:** `/connexion`, `/mon-compte/*`, `/[slug]/reserver`, `/support`, the legal pages, `/pro/connexion`, `/pro/inscription`, `/pro/*`. These are task surfaces; restyling them adds risk and no brand value. The booking funnel keeps its flow as is.

**Out of scope.**
- The apps. The font and pattern can reach them later: `AppTheme.themeData(fontFamily:)` is the seam.
- New copy, new features, or any change to a flow, route, API or JSON-LD.
- A commissioned photo shoot. Real photos arrive with real salons (§6.4).

**Flow stays the app's and today's** ([[web-mirror-app-flow]]): search, categories, salons, directory. Same sections, same order, same links.

---

## 2. The direction in four lines

1. **Swiss structure.** One grid, one left edge, one typeface, flush-left text, large type against small, thin rules in place of boxes.
2. **MyWeli's own marks.** The real logo, large enough to be remembered, plus the identity rules we already hold (§3).
3. **African identity through cloth, and calm.** One quiet panel, black on white: long rows, one motif, the logo once, after Baule strip-woven cloth (§4).
4. **Colour comes from people's work.** The interface stays monochrome, so the colour on the page is the salons' photos. Action and status colours stay as SYSTEM §3 defines them.

Why these fit together: strip-woven cloth is already a grid of narrow bands, and the logo is already a strip with a V cut in each end. The cloths that fit best are the quiet ones, and those are real (§4.1).

---

## 3. What represents MyWeli

| Element | Where | Rule |
|---|---|---|
| **Lockup** (`myweli_lockup_horizontal_black.svg`) | `Header`, every public page | Grows from `h-7` to `h-8`. Always links home. Keeps its 48px target. Never redrawn, never typed as text |
| **Wordmark** (`myweli_wordmark_black.svg`) | `SiteFooter`, large, on the grid | About 7 of 12 columns from `lg` and the full width on a phone. Decorative here (`alt=""`): the lockup already names the page. Smaller on `/pro/*`, see §7.9 |
| **Mark** (`myweli_mark_*.svg`) | In a clearing in the panel and at the end of the phone band | Black on the page's paper, the exact path, large enough to be recognised. Once per form |
| **App icon, favicon** | Unchanged | Already black with the mark |
| **OG image** (`app/opengraph-image.png`) | Link previews | Redrawn: panel on one side, lockup and « Réservation beauté & bien-être en Côte d’Ivoire » on the other. Same 1200×630, same alt text |
| **Pure black fills, ink text** | Everywhere | SYSTEM §1 is unchanged: brand `#000000`, text `#1A1A1A` |
| **Rounded controls** | Fields, buttons, chips | Unchanged (`radiusLarge`, `radiusPill`), so the site and the app feel related. Layout boxes lose their corners, not controls |
| **The words of the place** | Commune names, FCFA, Wave / Mobile Money | Already on the site; the index treatment (§7.1) makes them part of the look |

---

## 4. The pattern: « le pagne MyWeli »

### 4.1 Does an African pattern fit a calm monochrome brand? Checked against real cloths

**Yes. The first drawing did not, and the cloths are why.**

The owner asked for this to be checked against real examples, and for it to follow the brand and feel calm. Looked at on 2026-11-02:

| Cloth | What it looks like | What it teaches |
|---|---|---|
| [Baule cloth, High Museum](https://high.org/collection/cloth/) | A dark field with long parallel bands of a fine herringbone. The bands look close to rows of braids | One motif, long rows, a lot of quiet. **The main reference** |
| [Baule or Dyula prestige wrapper, The Met](https://www.metmuseum.org/art/collection/search/321366) | Thin light stripes on dark indigo, with small check blocks far apart. The Met calls the patterning « precise yet subtle » | Considered as a second drawing (§4.4) |
| [Baule ikat, Leila Walter](https://leilawalter.studio/blogs/textile-stories/baule-kita-of-cote-d-ivoire-the-strip-woven-handloom-textile-of-central-cote-d-ivoire) | Soft-edged indigo stripes with repeated diamonds | Rhythm. Its softness comes from the dye and cannot be drawn honestly in flat SVG, so not used |
| [Baule cloth, Miami University Art Museum](https://miamiuniversityartmuseum.omeka.net/items/show/2278) | Catalogued as **black and white** cotton in 7-inch bands (the record has no picture) | Black and white is part of this tradition, not only a brand constraint |
| [Bògòlanfini, The Met](https://www.metmuseum.org/art/collection/search/642873), [Cleveland](https://www.clevelandart.org/print/art/2025.270), [British Museum](https://www.britishmuseum.org/collection/object/E_Af1987-07-4) (Mali) | Geometric, but its motifs are **named**, and irregularities are thought to carry coded messages | **Do not borrow its motifs** |
| [Korhogo cloth](https://en.wikipedia.org/wiki/Korhogo_cloth), [Brown University](https://engagingtheamericas.digitalscholarship.brown.edu/off-the-roll-highlights-of-a-global-textiles-project/korhogo-textile-senufo) (Senufo, northern Côte d'Ivoire) | Figures with meanings, some connected to the Poro society | **Do not borrow its figures** |
| [Green Africa, Pentagram](https://pentagram.com/work/green-africa/story) | An airline identity whose logo pieces build patterns inspired by African textiles (read from its description: the video sits behind a cookie choice I did not make) | Precedent for building a pattern out of a logo. Its bright colour is the opposite of our brief |
| [Tensira](https://madegooddesigns.com/tensira-brand-guidelines/) (Guinean-founded) | Described as built on indigo and ecru, with material in place of ornament | Precedent for calm in this territory. The source calls its tones an unofficial reading |

**Why the first drawing failed the brief.** It put seven motifs side by side in loud blocks: a sampler, closer to a souvenir print than to these cloths. It also had none of what makes the brand calm: empty space and one idea at a time. It is withdrawn.

These museum records vary and some Baule cloths are richly coloured and embroidered, so calm is **a choice within the tradition**, not a claim about all of it.

### 4.2 What we borrow, and what we do not

**We borrow the structure:** long parallel rows, one quiet motif, small accents far apart.

**We do not copy:**
- a specific cloth or a named pattern;
- **figurative or named motifs:** Korhogo figures and bògòlanfini's named signs stay out;
- kente, which belongs first to Ghana. Geometry that resembles it by accident gets changed.

**Copy never claims it is traditional or authentic.** It is MyWeli's own drawing. The site says nothing about it.

### 4.3 The calm rules

These decide every later change to the drawing:

1. **One motif per drawing.** No samplers.
2. **Long rows on one field.** Nothing competes with the `<h1>`.
3. **The logo once**, in its own clearing, the largest thing in the panel.
4. **Fine, not chunky.** The motif is texture at reading distance.
5. **Black on the page's white, from the brand's role tokens.** No third colour, no gradient, no pattern behind text. **White on black is reserved for the dark version of the site**, later: drawn with role tokens, it becomes a value swap (SYSTEM §22).
6. **No animation.**

### 4.4 The drawing: rows of plaits (chosen)

Rows of round-ended strokes that meet from both sides, half a step apart: a plait seen flat.

**Why this one.** The motif comes from the product: Tresses is a category, and the rows also read as a woven band. The closest cloth is the High Museum's.

**Compared at true size, and not chosen:**
- **Stripes with small checks, far apart** (after the Met's wrapper). The most Swiss, but it can read as music staves or a circuit, so it says « African » least clearly.
- **The same plaits, white on a black field.** Strong, and kept for the dark version (§4.3).
- **Arrows (>>>).** An earlier draft of this motif. They read as a « fast forward » control, not as cloth.

### 4.5 Forms

| Form | Where | Drawing |
|---|---|---|
| **Panel** | Hero from `lg`, columns 8–12, with a structural rule on its left, running to the page's right edge and from the header's rule to the next rule | Scaled by its width and **cut at the bottom like cloth off a roll**, so nothing is ever cut down its side |
| **Band** | Hero below `lg`, and the 404 page | Full width, three rows and the mark, a row rule under it |
| **OG image** | Link previews | The panel, exported to the existing PNG |

### 4.6 Where it goes, and where it does not (answered)

| Page | Pattern |
|---|---|
| `/` | Panel or band in the hero |
| `/professionnels` | Panel or band in the hero |
| 404 and error pages | Band |
| Salon pages, category pages, `/recherche` | **None.** Photos are the content, and the page's job is choosing a salon |
| `/connexion`, `/mon-compte/*`, booking, legal, `/pro/*` | **None** |

**Hard rules, held by tests (§12):** at most one panel or band on a page · never behind text · no animation · `aria-hidden`, so it says nothing to a screen reader · no text inside it · inline SVG only, no image file.

### 4.7 Technical shape

- `components/brand/Weave.tsx`, a server component with no client JS, exporting `WovenPanel` and `WovenBand`.
- Colours through the theme's role tokens (`stroke-primary`, the page's `surface`), not literals, which is what makes the dark version a value swap.
- At most **4 KB of markup per page** before compression, pinned by a test. Measured in the sketch: panel 3.1 KB, band 0.8 KB.
- Replaces `HeroBackground`, which is deleted, along with its comment about stacking: nothing sits behind text any more.

### 4.8 Before it goes live: people who would know

I cannot judge from here how this reads in Abidjan. **The owner shows the panel to 3–5 people before S1 is merged:** salon owners, ideally one Ivorian designer. Four questions:

1. What do you see?
2. Does it feel like here, or like a souvenir?
3. Is anything in it wrong or disrespectful?
4. Would you trust a booking site that looks like this?

An answer to question 3 changes the drawing. The structure of the page does not depend on it: without the pattern, the hero still stands on its type.

---

## 5. Type

### 5.1 The typeface: Hanken Grotesk (answered)

One family at every size. Sizes are the measured `latin` variable `woff2` (Fontsource, `Content-Length`, 2026-11-02). Every candidate's subset has to carry French: the Google `latin` range checked for Inter Tight includes `U+00C0–00FF`, `U+0152–0153` (œ) and `U+2000–206F` (’ and the narrow no-break space).

| Family | Size | Reading |
|---|---|---|
| **Hanken Grotesk** (chosen) | 34.7 KB | Warm and open. Its round forms sit well beside the wordmark's. Second-smallest here |
| Inter Tight | 44.9 KB | The closest to Helvetica, and the most neutral. Planity's body text is Inter, so it is the least ours |
| Schibsted Grotesk | 46.8 KB | The most character. Wide, so long French lines wrap sooner: « Port-Bouët » broke in the sketch |
| Instrument Sans | 30.1 KB | The lightest, slightly condensed and contemporary. Colder beside the logo |

Plain Inter (48.3 KB) is what SYSTEM §22 named, so §22 is updated in the S0 PR.

### 5.2 Loading

- `next/font/local` with the `woff2` committed under `web/styles/fonts/`, with its OFL licence file beside it. No build-time network call, exact bytes pinned, and no request to Google at runtime.
- `display: 'swap'`, as WEB.md §7 requires, with `adjustFontFallback` so the swap does not shift the page.
- Weights 400, 500 and 600 from one variable file.
- `fontFamily` gets closed in the theme, as the other families were (WEB-SYSTEM §2). `font-mono` has no use on the web today, so nothing is lost.

### 5.3 Sizes

Nearly everything is already a token. Only one is new.

| Role | `<sm` | `sm` | `lg` | `xl` |
|---|---|---|---|---|
| Hero `<h1>`, `/` and `/professionnels` | `displaySmall` 36/44 | `displayMedium` 45/52 | `displayLarge` 57/64 | **`displayPoster` 80/84** |
| Page `<h1>`, salon and landing | `headlineLarge` 32/40 | `headlineLarge` | `displaySmall` | `displaySmall` |
| Section `<h2>`, public pages | `headlineSmall` 24/32 | `headlineSmall` | `headlineMedium` 28/36 | `headlineMedium` |
| Reading | `bodyLarge` 16/24, as today | | | |

- **`displayPoster` is web-only** and is declared in `WEB_ONLY` (`scripts/dart-tokens.mjs`), since the mirror test fails any undeclared web token. A second token needs a reason.
- Hero sizes add `tracking-tight`. The app's tracking was tuned for Roboto, so body tracking is looked at again on the real font in S0.
- **« bien-être » never breaks at its hyphen.** It breaks badly in French (« bien-/être »). A `whitespace-nowrap` span does it, and the text stays the same for search engines.
- Prices use `tabular-nums`, so columns line up.

---

## 6. Grid, rules, photos

### 6.1 The grid

- **One container on every public page:** `mx-auto max-w-screen-2xl px-m lg:px-l`, in one shared constant so it cannot drift.
- `grid-cols-12` from `lg`, one column below it. Gutters `gap-x-m`, `lg:gap-x-l`.
- Reading paragraphs stay capped at `max-w-content` (SYSTEM §10).
- **Hanging headings** from `lg`: the `<h2>` in columns 1–3, the content in 4–12. Stacked below `lg`.
- **Flush left, everywhere on these pages.** Empty states included: `EmptyState` gains an `align` option, and its default stays centred for the pro pages.

### 6.2 One left edge

The logo, the `<h1>` and the first section start at the same x on every public route, at every width (the defect in §1). `/recherche` runs full width, so `SiteChrome` passes it a full-width header. Held by an e2e test (§12).

### 6.3 Rules instead of boxes

| Rule | Token | Use |
|---|---|---|
| Structural | 1px `border-primary` | Under the header, between sections, above the footer |
| Row | 1px `border-divider` | Between list rows, as SYSTEM §3.3 already defines |

Black structural rules are a **new use of `primary`**, recorded in WEB-SYSTEM. `Card` stays for what is a real container: the booking panel, the pro pages, the account. The page background stays `surface`, so no rule about `secondary` changes.

### 6.4 Photos

- **Same-ratio crops:** 4:3 on cards (the app's card is close to that), 3:2 on the salon cover, through two named `aspectRatio` tokens. Same-ratio crops are what make uneven phone photos look like one set.
- **Square corners**, so the grid stays visible.
- **No filters and no scrims.** Hair colour is information.
- **No AI-generated faces or results** anywhere on the site. A fake result on a booking site misleads people.
- **A salon with no photo:** its logo on `surfaceVariant` if it has one, otherwise its initial in display type. Never a stock image and never the pattern.

---

## 7. Page by page

Sections, order, links, headings' words and JSON-LD stay as they are. Only the presentation changes.

### 7.1 `/`

| Section | Phone | From `lg` |
|---|---|---|
| Hero | Band, `<h1>`, lead, `HomeSearch` stacked | Columns 1–7: `<h1>` at the top, lead and search on the panel's bottom line. Columns 8–12: panel |
| Catégories | Same six links, same order, as a ruled index in 2 columns, `min-h-12` cells | Hanging heading, 3 columns |
| Salons populaires | Tile cards. **Hidden at 0 salons, as today** | 4 across |
| Partout à {ville} | One `<details>` per commune with a 48px `<summary>`; the links stay in the served HTML | Hanging heading, 4 columns, always open |
| Value props | Stacked, each under a rule, no card | 3 columns |
| L'app MyWeli | Only when `appStoreUrl()` has a value, as today | Same |
| Vous êtes un salon ? | Rule, heading, text, secondary button | Hanging heading |
| FAQ | Rows | Hanging heading. `dl` unchanged |

The search stays visible without scrolling at 360×640.

### 7.2 `/professionnels`

Same hero layout. Benefits as a ruled 3-column list. **Steps with large numerals** in place of the small black discs. FAQ with a hanging heading. Closing row under a rule. Its rule of one filled action per screen stays.

### 7.3 `ProviderCard`

Two layouts, one component, with every existing prop unchanged:
- `tile` (home, landings, favourites): photo on top.
- `row` (`/recherche`): photo on the left, 1/3 of the width.

No box: a rule and a hover state. `next/image`, lazy, with real `sizes`. The rating, the « Nouveau » pill and the favourite heart with all its states stay as they are.

### 7.4 `/recherche`

Same list and map, same filters, same mobile toggle. The map is untouched. Cards use `row`, and the full-width header starts at the list's left edge.

### 7.5 Landings

`max-w-content` becomes the site grid. Reading text stays capped. Cards 3 across from `lg`. Sibling chips stay chips. The empty state goes left-aligned with its current words. The FAQ follows §7.1.

### 7.6 Salon page

- Phone: unchanged order, and the sticky booking bar stays.
- From `lg`: cover in columns 1–8 at 3:2. Columns 9–12: name, rating, `BookingPanel`, sticky.
- Sections below get a structural rule and a larger `<h2>`.
- The salon's own logo stays on its cover (salon-logo.md §5).
- No pattern (§4.6).

### 7.7 404 and error pages

Left-aligned with the band. The wording stays as tests hold it.

### 7.8 Header and footer

- **Header:** lockup, « Espace pro », bell, « Mon compte », same links, a black rule under it.
- **Footer:** large wordmark, then the same three link groups and the same `rel="me"` links, on the grid.

### 7.9 `/pro/*`

Gets the font only. `SiteFooter` is a server component shown on `/pro` too (its comment says why), and a poster-size wordmark under an agenda is wrong. So the large wordmark is on public routes, and `/pro/*` gets the lockup at `h-8`. The footer must stay a server component: the choice is made by what the page's own layout passes or by a small client wrapper, whichever ships less JS, decided in S1.

---

## 8. States and edge cases

| Case | Behaviour |
|---|---|
| 0 salons (today) | Home hides the section. Landings show the empty state. The hero stands on its type and pattern: **no page depends on a photo** |
| Locality tree unreadable | As today: « Abidjan » fallback, directory hidden, search still works |
| Font slow or blocked | System fallback with adjusted metrics, then a swap with no visible jump. Text is never hidden |
| Salon with no photo | §6.4 |
| Photo fails to load | The `surfaceVariant` tile stays and the ratio holds, so there is no shift |
| Long city or salon name | `displaySmall` fits « Yamoussoukro » at 320 wide by estimate; `type-overflow.spec.ts` decides. `break-words` on `<h1>`. Declared `truncate` on card names stays |
| 320 wide, 400% zoom | One column. The band fills the width. Covered by the reflow gate |
| Large browser font | Same limit as today: type is `px`, boxes are `rem` (WEB-SYSTEM §9). Not made worse |
| Forced-colours mode | The pattern is decorative. Text and controls are the system's |
| Install banner present | A black band above the header, then a black rule. Looked at in S1 |
| Symbols ★ ♥ ✔ ✕ | Not in the font: they fall back to the system as they do now. Icon sizes checked in S0 |
| Multi-pays | `{ville}` comes from the tree. The pattern is not tied to one city |

---

## 9. API, data, contract

None. `imageUrls` is already `required` on `Provider` in `openapi.yaml`, and `imageUrls[0]` is already the listing cover. To confirm in S3: the real list read returns it (the app's card relies on it and the stub has it).

---

## 10. SEO / AEO / GEO

- Same `<h1>` words, canonical URLs, metadata and JSON-LD on every page. A test compares them before and after (§12).
- The directory's links stay in the served HTML inside `<details>`.
- Sitemap and `llms.txt` unchanged.
- Salon card photos need real `alt` text, not `alt=""`, since they are content. Words: the salon's name, as the hero's alt already does.

---

## 11. Performance and security

**Budgets stay and are not raised:** LCP < 2500 ms, CLS < 0.1, TBT < 200 ms on `/` (`lighthouserc.json`).

| | |
|---|---|
| **Last recorded, 2026-08-20** (WEB.md §7) | `/` local median **2309 ms**, production **2030 ms**. So about 190 ms of room locally, and those numbers are old |
| **What this adds to `/`** | One font file, 34.7 KB; at most 4 KB of inline SVG; no image, no script |
| **The real risk** | A larger `<h1>` can become the LCP element, and the font swap can move it. **Measured in S0, on the font alone, before any layout changes** |
| **If it breaches** | Cut the font first: narrow the weight axis, tighten the subset. Then preload rules. The budget does not move |
| **New photos** | Card photos are lazy and below the fold on `/`. Salon page budgets are set from a measurement in S4, added to `lighthouserc.json` so they cannot be forgotten |

**Security.** CSP's `font-src 'self'` already allows `next/font`'s files, and no new origin appears. No third-party font request, which also keeps the privacy policy true. No secrets. Read back the deployed header after S0.

---

## 12. Tests

Each new guard ships having been watched red, on committed work.

| Guard | What it holds | How to turn it red |
|---|---|---|
| `served-html` / e2e | `body` computes the brand font, and the `woff2` answers 200 from our origin | Remove the font class |
| `tokens.mirror` | `displayPoster` is declared web-only | Remove it from `WEB_ONLY` |
| `tokens.theme-pin` | The closed `fontFamily`, and the emitted tokens | Use a non-token family |
| **New: left edge** | Logo x = `<h1>` x = first section x, on each public route at 375, 768, 1280, 1536, 1920 | Change one container's padding. Must fire on `/recherche` at 1920 |
| **New: pattern rules** | `aria-hidden`, no `<text>`, no hex literal, ≤ 4 KB, at most one per page; present on `/` and `/professionnels`; **absent** from salon, landing, `/recherche`, `/connexion`, `/pro` | Add a band to a salon page |
| **New: logo** | The lockup in the header and the wordmark in the footer are the real brand files, on each public route | Replace one with text |
| **New: SEO unchanged** | `<h1>` text, canonical and JSON-LD on `/`, `/professionnels`, a landing and a salon match a checked-in list | Change a word |
| `type-overflow` | Reflow at 375 / 320, with `/professionnels` and a long-city case added if missing | A nowrap hero that spills |
| `tap-targets` | Add category cells, directory `<summary>` and links, footer links | Remove `min-h-12` |
| `axe` | Existing routes, including the new `<details>` | Existing |
| Lighthouse | Existing on `/`; salon page added in S4 | Existing |
| Unit | `ProviderCard` no-photo cases: logo, initial, unnamed salon (SYSTEM §17.2) | Drop a branch |

**What these cannot see.** WEB-SYSTEM §9 says it plainly: there is no screenshot harness on the web, and ugly-but-not-clipped passes every gate. So each PR carries before and after pictures at 360, 768, 1440 and 1920, and they get looked at. **Real-phone check by the owner** on a low-end Android at S1, since font rendering there cannot be judged from this Mac.

---

## 13. Rollout

Six PRs, in order, each merged only on the owner's word. A merge is a production web deploy, so each is verified on `myweli.com` afterwards.

| # | Slice | Done when |
|---|---|---|
| **S0** | Starts after BACKLOG Batch 12's four untrue sentences. Font, `displayPoster`, grid constant, rule roles, WEB-SYSTEM + SYSTEM §22. **No layout change** | Lighthouse measured on the font alone. Every e2e green, including `/pro` |
| **S1** | `Weave`, `Header`, `SiteFooter`, `/`. Delete `HeroBackground` from `/` | §4.8 answered. Owner's real-phone check |
| **S2** | `/professionnels`, 404 and error pages. `HeroBackground` deleted | |
| **S3** | `ProviderCard`, `/recherche`, landings, favourites list | Cards with and without photos looked at |
| **S4** | Salon page. Budgets added | Salon LCP measured |
| **S5** | OG image. Audit of every page against this spec **on the deployed site**, by separate eyes told to refute it | Findings fixed or filed |

**During App Review.** `/support` and `/politique-confidentialite` are listed with Apple and they keep their wording. They change only in font, header and footer, and they get checked after each deploy. Timing against Apple's decision is the owner's call at each merge.

**Mixed look between merges.** Accepted: there is no public traffic to speak of (memory: not yet public), and each slice stands on its own.

---

## 14. Definition of done

- [ ] Typecheck, lint, `vitest`, `next build`, Playwright, axe, Lighthouse green; no budget raised.
- [ ] Every new guard watched red; recorded in the commit.
- [ ] Tokens only, with no new undeclared `ds-ignore`.
- [ ] Four states kept on each page.
- [ ] Parity: salon cards gain the app's cover photo.
- [ ] App-install push unchanged.
- [ ] H1, canonical, JSON-LD unchanged.
- [ ] Pictures in each PR, looked at. Deployed site read back.
- [ ] WEB-SYSTEM (new section on the public-page language), SYSTEM §22, this spec, the README index, BACKLOG and the roadmap entry kept true.
- [ ] Feature branch + PR, CI green, no Claude attribution.

---

## 15. Decisions

All answered by the owner on 2026-11-02 (BACKLOG decisions 63–67).

| # | Question | Answer |
|---|---|---|
| Q1 | Pattern colour | **Black on white**, on condition that it fits African patterns, the brand, and feels calm. Checked in §4.1: it does, once redrawn. White on black is kept for the dark version |
| Q2 | Typeface | **Hanken Grotesk** |
| Q3 | Where the pattern goes | **Home, `/professionnels`, 404** (§4.6) |
| Q4 | Which drawing | **Rows of plaits** (§4.4) |
| Q5 | What comes first | **The untrue sentences** ([web-flow-audit-2026-11.md](web-flow-audit-2026-11.md)), **then the new look** |

**Left with the owner:** §4.8, showing the panel to people in Abidjan before S1 goes live. I cannot judge that from here.
