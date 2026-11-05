# Web — the salon card, `/recherche`, the landings and the favourites in the new look (B11.3) — design spec

| | |
|---|---|
| **Status** | **Approved, 2026-11-05: the four decisions in §11 are answered. Built on `feat/web-swiss-cards`, proved locally, not pushed (§10).** Both merges wait for Apple's decision on build 719 and the owner's word |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-05, against `main` at `ea0c8f0c` |
| **PRD ref / phase** | FR-WEB-MP-001 (presentation), plus one parity gap: the card's cover photo · V1 |
| **Parent** | [web-swiss-direction.md](web-swiss-direction.md), slice S3. Its §6 and §7.3–§7.5 are approved. Where this spec differs from them, §14 says so |
| **ROADMAP entry** | One new file in `docs/roadmap/entries/`, with the web PR. BACKLOG B11.3 |
| **Module** | Web: `ProviderCard`, `EmptyState`, `RechercheClient`, `TaxonomyLandingView`, `app/page.tsx`, the favourites section of `AccountClient`, `AvisClient` (one attribute), `tailwind.config.ts`, `next.config.mjs`, one job in `production-checks.yml`. Backend: one test, in its own PR |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-verification-guardrails ✓ · myweli-backend-guardrails is owed before the backend test (§3) |

**How to read this.** « Direction §x » is the parent; a bare « §x » is this spec. **The spec is written for the answer to each decision: all four took the recommended path, and §11 keeps the other options for the record.** « Sheet n » is a picture from the plan's private set, sent to the owner on 2026-11-05: none is committed, because the demo photos' licences are unknown (decision 37). « Seen » means read in the code at `ea0c8f0c`. « Measured » means on the prototype: a real `next build` and `next start` of `ea0c8f0c` plus `prototype.patch`, uncommitted, against the stub, in headless Chromium, unthrottled, with photos served to the browser by the picture tool. Anything else says *inferred* or UNVERIFIED. WebKit would not start here, so nothing was seen in Safari. « The data pass » is the read of the API, the images and the live layouts on 2026-11-04: GET only, signed out.

---

## 1. Goal & scope

**Goal.** The salon card gains the cover photo the app has always had, and loses its box. The pages that list it move to the new look. Production has no public salon yet, so this mostly prepares for the first one.

**The rule, in one sentence: a card is a salon's own photo, square and uncovered, with flush-left text and one thin rule.**

**In scope**

| What | Change |
|---|---|
| `ProviderCard` | Two layouts of one component, a 4:3 photo, no box. Every existing prop stays |
| `tailwind.config.ts` | Two tokens: `aspect-card`, `content-initial` |
| `EmptyState` | `align`, centred by default, so the pro pages do not change |
| `/` | Tiles. Only the grid's gaps change |
| `/recherche` | Rows, with a rule between them. A square selection ring. The empty state goes flush left. « Trier » can shrink, so doubled text no longer scrolls the page sideways. « Carte » moves to the page's gutter, off the rows' text (decision 5) |
| Landings, all three levels | The site grid and `SiteSection`, 3 tiles from `lg`, a ruled index of cities, an open FAQ, flush-left empty state, crumbs at the 48px floor |
| Favourites | The new card: a row below `sm`, a tile from `sm`, in the columns it has today. « Retirer des favoris » reaches the 48px floor. A stopped salon is not a link and offers no « Annuler » |
| `next.config.mjs` | `images.minimumCacheTTL`, because photos now appear on every list (§7) |
| `AvisClient` | `unoptimized`, so a client's erased review photo cannot outlive erasure in that cache (§6) |
| In support | `SiteFaqList`, `salonInitial`, stub fixtures, one Next-process preload for the tests, one scheduled check |

**Stays as it is**

| What | Why |
|---|---|
| The map, filters, sort, the mobile toggle's words and behaviour, hover and selection logic on `/recherche` | Direction §7.4. The toggle's place is the one exception: the owner moved it after seeing the before and after (decision 5) |
| The heart's props and states, `SalonRating` itself | Direction §7.3 |
| `/mon-compte`'s container, columns, favourites empty state and error state | Direction §1: task surfaces take only the font, header and footer |
| `<h1>` words, canonical URLs, metadata, JSON-LD, sitemap, `llms.txt` | Direction §10 |
| `components/provider/Faq.tsx` | The salon page shares it, so changing it would start S4 early |
| No pattern on any of these pages | Direction §4.6, already held by `site-look.spec.ts` |

**Out of scope, and where each one goes** (wording in §15)

| What | Goes to |
|---|---|
| Salon page, `Hero`, `Gallery`, `Faq`, `aspect-cover`, budgets for the salon page | B11.4 |
| Budgets for landings and `/recherche` (§7) | B11.4 |
| OG image, audit of the deployed site, `ItemList` with an empty name, the map's popup covered by a marker, the privacy page's sentence on hosting | B11.5 |
| The search fork on landings (C6), returning client's home (C5), past visits and profile (C7, C10) | B12.7, decision 4 |
| « À venir » logic (C4), salon description (C3), deposit and consent details (C8, C9) | B12.6, B12.5, B12.7 |
| The heart's message when signed out, a way out of an empty `/recherche`, a grid/list toggle on the web, a slow photo's retry, a place line for a salon with no commune | B12.7, new lines |
| The app's card: `via.placeholder.com` for a missing photo (`salon-cover-photo.md:245`), no mark on a stopped favourite, its stale comment (`provider_card.dart:20-26`), its home strip going stale after a toggle | B12.10, new lines |
| Whether direction §4.7's 4 KB counts the RSC payload | B11.2, already the owner's |

**Fit with the architecture.** The web PR touches `web/` and one workflow, on the existing API. The backend test is a separate PR because any file under `backend/` starts `deploy-backend.yml` on merge (§9). `ProviderCard` stays a shared module with no `'use client'`, so `/` and the landings add no client code of their own. `next/image` was already in the layout's graph (`Header.tsx:1`, `FooterMark.tsx:3`). Next's route table shows `/` going 134 to 140 kB and a landing 132 to 138 kB: the image chunk is only listed again under those pages. Summing distinct script files gives about +300 B gzipped (measured).

---

## 2. UX & flows

### 2.1 The flow does not change, with one exception

**Entry points.** `/` « Salons populaires ». A landing, from a category link, the search fork, a search engine or the sitemap. `/recherche`, from the search bar or a chip. `/mon-compte`, section « Favoris ».

**Path.** Look at the list, press the card, reach `/{slug}`, book. Back returns to the list. That is the app's flow (`/provider/{id}`).

**Branches.** On `/recherche`: the heart, marker and card highlighting each other, and the list/map toggle. On favourites: « Retirer des favoris ». All unchanged.

**The exception, decision 3.** A favourite whose salon stopped is no longer a link, because that link ends on a 404. The app differs: its card stays tappable and opens « Ce salon n’est plus disponible sur MyWeli. » (inferred from the path, not seen on a device).

### 2.2 The card

Props, all additive. The five existing props do not change.

```ts
layout?: 'tile' | 'row' | 'rowOnPhone';   // default 'tile'. rowOnPhone: row below sm, tile from sm
imageSizes?: string;                      // default: row ? CARD_SIZES.row : CARD_SIZES.site
imagePriority?: boolean;                  // default false. The first card of a landing level or /recherche (§7)
linked?: boolean;                         // default true. false: the root is a <div>, no hover
```

**Tile** (photo on top) and **row** (photo left, a third of the width) share everything below the root.

```
<a class="group block">                     row: group flex items-start gap-sm sm:gap-m
                                            rowOnPhone: group flex items-start gap-sm sm:block
  <div media class="relative aspect-card border-b border-divider bg-surfaceVariant">
                                            row adds: w-1/3 shrink-0
                                            rowOnPhone adds: w-1/3 shrink-0 sm:w-auto
    exactly one of: photo · logo · initial
  </div>
  <div text class="mt-sm">                  row: min-w-0 flex-1, no mt
                                            rowOnPhone: min-w-0 flex-1 sm:mt-sm
    <h3 class="break-words font-medium text-textPrimary">
      <span class="group-hover:underline group-focus-visible:underline">name</span>
      a no-break space, then ✔︎ (as today)
    </h3>
    <div class="mt-xs text-bodyMedium text-textTertiary"><SalonRating withCount /></div>
    <div class="flex">
      <div class="min-w-0 flex-1">
        <p class="mt-xs break-words text-bodyMedium text-textSecondary">commune</p>
        <p class="mt-xs text-bodyMedium text-textTertiary">à partir de <span class="inline-block">15 000 FCFA</span></p>
      </div>
      with a heart: <span aria-hidden class="h-12 w-12 shrink-0"></span>
    </div>
  </div>
</a>
```

`linked={false}` renders the same two children in a `<div>` with the same layout classes, and the name's `group-*` classes go.

**What each choice is for**

| Choice | Why |
|---|---|
| **The root is still the `<a>`** when there is no heart, and `div.relative` around it when there is one | `consumer-optimistic-revert.test.tsx:116-118` walks `closest('a').parentElement`, and `return card` stays where it is |
| **The rating gets its own line** | The app's order (`provider_card.dart:293-321`). A shared row does not fit `row` at 320 |
| **The name is one inline run that wraps** | A name is the one thing on the card with no other copy nearby. A no-break space keeps the mark with the last word. `truncate` and its `clip-ok` go: the guard's own text says a clip that is the only copy is a 1.4.10 loss, « give it room instead » (`tokens.theme-pin.test.ts:411`). Decision 2 |
| **One rule, at the foot of the media block** | It gives a no-photo tile an edge. `surfaceVariant` #F5F5F5 on `surface` #FAFAFA is 1.045:1 (`tokens.ts:18-19`), and forced colours drop the fill. Under a photo it hardly shows (seen) |
| **No other rule in the card** | The list draws the lines between rows, so a card never doubles one |
| **Hover and focus underline the name** | `hover:bg-surfaceVariant` would hide the no-photo tile, and direction §6.4 rules out dimming a photo |
| **The spacer, `h-12 w-12`, in the row that holds the commune and price** | The heart is `h-12 w-12`, in rem, at the wrapper's bottom right. A spacer as tall as the heart fills the heart's band whatever the text, so the name and the rating above it can never reach the heart, and the commune and price beside it stay clear of it. Measured at 320 and 390, normal and doubled, on a long name and on a rated salon with no commune and no price: no text met a heart. A spacer cannot stop one word too wide for its column, so the commune has `break-words` too (§14). A px padding against a rem box is a named defect (WEB-SYSTEM §9, unit contract). This replaces the `min-h-24` an earlier draft had |
| **No `whitespace-nowrap` on the rating line** | With the count it can be wider than the column at doubled text. It wraps and stays inside (measured, three-digit count) |
| **`inline-block` around the amount** | `formatFcfa` puts a plain space before « FCFA » (`format.ts:40`). Without this, 320 reads « 15 000 / FCFA ». With it, « à partir de / 15 000 FCFA », and if even that cannot fit it still wraps rather than spills. `textContent` is unchanged, so `provider-card.test.tsx:15` holds |
| **The heart stays bottom-right, off the photo, with no disc** | Direction §7.3 keeps it as it is. The app puts it on the photo with a disc. Here that would cover a salon's photo for a difference of look, not of capability |

**The three media forms, one at a time**

| | Condition | Markup |
|---|---|---|
| **Photo** | `provider.imageUrls?.[0]` starts with `https://` | `<span aria-hidden class="absolute bottom-0 left-0 {INITIAL}">B</span>`, then `<Image fill sizes={imageSizes} alt={name} data-initial="B" loading="lazy" (with imagePriority: priority, and no loading) className="object-cover after:absolute after:inset-0 after:bg-surfaceVariant after:flex after:items-end after:font-semibold after:tracking-tight after:text-textSecondary after:content-initial {INITIAL with after:}" />` |
| **Logo** | No photo, and `provider.logoUrl` starts with `https://` | `<div class="absolute bottom-0 left-0 h-2/3 w-2/3"><Image fill sizes={imageSizes} alt={`Logo ${name}`} loading="lazy" className="object-contain object-left-bottom after:absolute after:inset-0 after:bg-surfaceVariant" /></div>` |
| **Initial** | Neither | `<span aria-hidden class="absolute bottom-0 left-0 {INITIAL}">B</span>` |

`{INITIAL}` is `font-semibold tracking-tight text-textSecondary` with `text-displayLarge` on a tile, and `text-displaySmall sm:text-displayLarge` on `row` and `rowOnPhone`.

- **`?.`, not `.`:** `lib/api/account.ts:120-125` validates only `id` and `name`.
- **`https://`:** a dev seed's `asset:` makes `next dev` throw (`image-loader.js:48-53`), and `next start` should answer 400 (inferred), as `''` should throw in dev (inferred). Either one reads as no photo here, and the next form takes over. **It does not cover a local backend on fake storage:** its URLs start `https://fake-storage.local` (`storage_service.dart:157`), a host outside `remotePatterns`, so `next dev` throws on `/`, the landings and `/recherche` too, as it already does on the salon page. Production answers 400 and the letter shows. Dev only, recorded, not handled.
- **`loading`:** lazy, except the first card's photo on a landing level or `/recherche`, which has `priority` through `imagePriority` (§7, decision 6). Next refuses `priority` and `loading` together. The prop reaches a photo only: a logo stays lazy.
- **Logo `sizes`:** the tile's value, unchanged, although the logo is drawn at 2/3. That is at most 1.5× the width a logo needs, on a small file whose small words benefit. One less constant.
- **Logo and initial sit in the bottom-left corner with no padding,** on the same x as the name under them, following the owner's flush-left rule. The corner holds for square logos (seen). Wide, tall and white-box logos are shown beside centred in sheet 14. Decision 2. A logo stands on the foot rule. The letter's line box does too, and its ink stands above the rule by half its leading and the font's descent: 12.5–13 CSS px at `displayLarge`, 10.5–11 in a 320 row, 19–26 at doubled text (measured from the pictures). `leading-none` would close only 3.5 of those (line height 64 to 57, read in a browser), so it stays as it is.
- **Nothing is layered under a logo:** a letter would show below a contained logo (seen). Under a photo it is covered whole, so the letter sits there (§2.4).
- **`name`** is `salonNameOr(provider.name, UNNAMED_SALON)` everywhere in the card, the heart's label included. `salonInitial(name)` is new in `lib/salon-name.ts`: the first letter or digit after NFC, upper-cased in `fr-FR`, and the first letter of `UNNAMED_SALON` if there is none. So « 💇 Awa » gives A, « « Chez Awa » » gives C, and « !!! » gives S.

**`CARD_SIZES`, exported from `ProviderCard.tsx`**

```ts
site:    '(min-width: 1536px) 354px, (min-width: 1024px) 23vw, (min-width: 640px) 48vw, 92vw',
row:     '(min-width: 1024px) 18vw, 32vw',
account: '(min-width: 1024px) 203px, (min-width: 640px) 312px, 32vw',
```

**A trap, in the code.** Next keeps only the candidates at or above `640 × the smallest vw` it finds in `sizes` (`get-img-props.js:46-54`). `92vw` alone would drop everything below 640w. `account` at `32vw` keeps 256w, which is what a 119-wide row picks at DPR 2 (measured). If favourites stay a tile on phones (decision 3), `account` must spell its phone width `calc(100vw - 32px)`, which the regex does not match, or a 203px tile downloads 640w. A test holds this (§8).

**Tokens.** `aspect-card` (`4 / 3`) in `theme.extend.aspectRatio` and `content-initial` (`attr(data-initial)`) in `theme.extend.content`, both in `tailwind.config.ts`. **Not in `styles/tokens.ts`:** `Icon.tsx` imports that file, and `Icon` is in the five store-linked pages' graph (§13). `aspect-cover` waits for its first user in S4, as the grid constant waited for S1 (direction §13's S0 row). Build, typecheck and lint pass on these classes (measured).

### 2.3 Page by page

Container width is `SITE_CONTAINER`'s: 16px each side below `lg`, 24px from `lg`, capped at 1536. Computed, and checked against the prototype's measures at 320, 390, 820, 1280 and 1920.

| Page | | 320 | 390 | 820 | 1280 | 1920 |
|---|---|---|---|---|---|---|
| **`/`** `tile` | Across | 1 | 1 | 2 | 4 | 4 |
| | Photo | 288×216 | 358×269 | 386×290 | 290×218 | 354×266 |
| | `sizes` | `CARD_SIZES.site` | | | | |
| **Landing** `tile` | Across | 1 | 1 | 2 | 3, beside the `<h2>` | 3, beside the `<h2>` |
| | Photo | 288×216 | 358×269 | 386×290 | 290×218 | 354×266 |
| | `sizes` | `CARD_SIZES.site` | | | | |
| **`/recherche`** `row` | Text column | 180 | 227 | 509 | 421 | 656 |
| | Photo | 96×72 | 119×90 | 263×197 | 219×164 | 336×252 |
| | `sizes` | `CARD_SIZES.row` | | | | |
| **Favourites** `rowOnPhone` | Across | 1 row | 1 row | 2 tiles | 3 tiles | 3 tiles |
| | Photo | 96×72 | 119×90 | 312×234 | 203×152 | 203×152 |
| | `sizes` | `CARD_SIZES.account` | | | | |

**Three hanging tiles equal four stacked ones at every width from `lg`:** both come to `(width − 72) / 4`. So one `sizes` value serves the home page and the landings, and a tile looks the same on both.

**`/`** (`app/page.tsx`)
- `:135` becomes `grid grid-cols-1 gap-x-m gap-y-l sm:grid-cols-2 lg:grid-cols-4 lg:gap-x-l`.
- Hidden at 0 salons (`:133`). The FAQ moves to `SiteFaqList`, with the same markup.
- All photos lazy. See §7 for 820 × 1180.

**`/recherche`** (`RechercheClient.tsx`)

| Line | Change |
|---|---|
| `:300` | `layout="row"`, and `imagePriority` on the first row only (§7). Every other photo lazy |
| `:273` | `mt-m space-y-m` becomes `mt-xs divide-y divide-divider` when there are results, and `mt-m` when there are none, because the empty state is not inside the divide |
| Each row, `:285-295` | `py-m` on every row. **Not `first:pt-0`:** that put the first row's ring on its photo and name (seen) |
| `:296` | `rounded-xl` goes. `ring-2 ring-primary ring-offset-2 ring-offset-surface`. `.ring-2` stays, and `discovery.spec.ts:136` reads it. The offset keeps the ring off the photo's left edge, as the focus ring does. The first photo moves 4px down (y=371 against 367, measured) |
| `:275` | `align="start"`, same words |
| `:243-257` | `max-w-full` on the label and `min-w-0` on the select. No change at normal text. **Why:** with doubled text at 320 the unchanged « Trier » made the page 322 wide (measured); now 320, and at 195 wide now 195 (measured) |
| `:346` | `left-1/2` and `-translate-x-1/2` go, and `left-m` comes, so x=16, the page's gutter, at every width below `lg`. Decision 5. Its right edge is 100, and a row's text column starts at 124 at 320, 137 at 360, 147 at 390, 277 at 768 and 295 at 820 (measured). Both old classes stay in the stylesheet, because `Toast.tsx:32` still uses them, and `left-m` was already there, because `Hero.tsx:29` uses it, so the stylesheet does not change (§13) |

The `<h1>` stays `headlineSmall` and the count `<h2>` stays `titleLarge`. Direction §5.3's `<h2>` row says « public pages » and §1 lists `/recherche`, so this is a departure (§14): it is a list beside a map. The header's full width already works (`SiteChrome.tsx:22`).

**Landings** (`TaxonomyLandingView.tsx`, same order as today)

```
<main>                                             no container
  JSON-LD, unchanged
  <div SITE_CONTAINER pt-s pb-l>
    Crumbs                                         each link: inline-flex min-h-12 items-center
    <h1 mt-s break-words text-headlineLarge lg:text-displaySmall font-semibold>
    <p mt-m max-w-content text-bodyLarge>
  root:  SiteSection « Choisissez votre ville »    ruled index (below)
  city:  SiteSection « Choisissez votre {kind} »   chips
  salons: SiteSection « N salons »                 <ul grid grid-cols-1 gap-x-m gap-y-l sm:grid-cols-2 lg:grid-cols-3 lg:gap-x-l>
  none:  <section border-t border-primary>         <div SITE_CONTAINER py-xl lg:py-xxl><EmptyState align="start"/>
  area:  SiteSection « {label} dans d’autres {kind}s »  chips
  SiteSection « Autres prestations … »             chips
  SiteSection « Questions fréquentes »             SiteFaqList
```

- **Hanging, not stacked.** Direction §6.1 and WEB-SYSTEM §16 make hanging the default, and `stacked` is for content needing all twelve columns.
- **The ruled index of cities** replaces the boxes at `:308`, in the home page's Catégories treatment: `grid grid-cols-1 gap-x-m sm:grid-cols-2 lg:grid-cols-3 lg:gap-x-l`, each link `flex flex-col justify-center border-b border-divider py-s text-textPrimary hover:text-textSecondary`, with its two lines as today. The colour is on the link so its hover reaches the name, and two lines and `py-s` are 65 tall at every width, so it has no `min-h-12` (§14). One column below `sm`, because « Coiffure à Yamoussoukro » does not fit in half a phone.
- **`SiteFaqList`** (`components/SiteFaqList.tsx`) is the `dl` at `app/page.tsx:222-229`, already copied at `professionnels/page.tsx:74-81`. Three uses justify the extraction, and both pages keep their markup exactly. Landing answers are now open. They were in the HTML already, inside `<details>`.
- `imagePriority` on the first tile only, on all three levels (§7). Every other photo lazy.

**Favourites** (`AccountClient.tsx`)
- `:490` gains `layout="rowOnPhone"`, `imageSizes={CARD_SIZES.account}` and `linked={!stopped}`. `:479`'s columns stay.
- `:496-506` gains `inline-flex min-h-12 items-center`. It computes to 20px against the 48px floor, and no test covers it.
- `removeFav`: when `salonStoppedMessageFor(removed.status)` answers, `show(FAVORITE_REMOVED, 'success')` with no « Annuler », because `FavoritesService.add` refuses a hidden salon (`favorites_service.dart:63-73`). Otherwise `announceFavorite` as today.
- The empty and error states stay centred, as everything else in the account does. The sentence for a stopped salon stays where it is today, under the card.
- **What the phone gains (measured 2026-11-05 on three real builds: `main`, the branch, and the branch with `layout="tile"`; 4 favourites at 390, one of them stopped).** Section height 640 today, 704 as rows, 1826 as tiles. « Aide & Support » at y=1433 today, 1497 as rows, 2619 as tiles. « Supprimer mon compte » at y=1699 today, 1763 as rows, 2885 as tiles. **So rows move support and account deletion down 64px, and tiles would move them 1186px.** At 320: 656, 720 and 1632, so +64 and +976. With four live favourites the moves are the same at both widths. This line used to read 744, 1537 and 1803 for today, so rows looked 40px shorter than today: those three figures were wrong, and the rows and tiles figures held (§14). A row picks a 256w file where a tile picks 750w.
- **203px at `lg` is smaller than 312px at `sm`,** because a third column arrives inside `max-w-2xl`. It is one class to change, and direction §1 says no layout change there, so it stays. It is in the pictures.

### 2.4 Every state

| Case | Behaviour |
|---|---|
| **Photo** | 4:3, `object-cover`, centre crop, as the app. Square corners, no filter, nothing on top. The letter under it is covered whole: `elementFromPoint` at the tile's bottom-left is the `<img>` (measured) |
| **Photo in a portrait** | A 3:4 phone photo keeps 22% to 78% of its height, a 2:3 one 25% to 75% (arithmetic). A head in the upper third would lose its top. `object-top` would keep it and cost a room its chairs (sheet 14: a drawing, and the real interior F1). **No real portrait has been looked at.** Decision 2 |
| **Photo slow** | The tile holds the ratio, the salon's letter sits on it bottom-left, and the photo paints over it with no shift. No spinner and no retry. **Seen in Safari** (iOS 26.5 simulator, the file held 15 s): the letter, then the photo at the same size with no shift. On a normal connection the letter shows briefly on every photo: a still picture cannot show that, and the first real list gets looked at for it. The app has a 12 s retry (`timed_cached_image.dart:212-247`): recorded as a difference, filed in B12.7 |
| **Photo fails** | The tile, ratio held, with the letter, the same as a salon with no photo. **`alt` and `object-cover` are not enough:** `next/image` makes the alt text transparent, but Chromium still draws its broken-image mark in the corner. An `::after` on the `<img>` covers it and carries the letter from `data-initial`: a browser generates one only when the image failed, so a loaded photo is untouched. Measured by pixels: with it, the corner is one colour, #F5F5F5; without it, 548 colours. **A photo with transparency would show the letter through it:** accepted, salon photos are opaque in practice (inferred). **WebKit, seen 2026-11-05 in Safari on an iOS 26.5 simulator, is the worst case this line expected:** the tile holds its ratio with the letter bottom-left, a small blue « ? » is drawn in the tile's centre, and a thin grey outline around it. So WebKit makes no `::after` here, or draws its mark above it. Only `onError` could remove it (inferred), and the next line rules that out on `/` and landings, so it goes to the owner |
| **No swap on failure** | A failed photo does not fall back to the logo. `onError` needs client code on `/` and landings, and Next re-requests each image after hydration when `onError` is set (`image-component.js:169-174`). Direction §8 asks only that the tile stays |
| **Logo fails or is slow** | The tile with no letter, because a letter would sit below a contained logo. The `::after` cover, without `content-initial` |
| **No photo, logo** | The logo, bottom-left, on `surfaceVariant`. Any aspect ratio: `salon-logo.md` §1 has no cropper |
| **No photo, no logo** | The initial, bottom-left. Reachable on a live salon: the gallery PUT has no minimum (`provider_catalog_service.dart:384-401`) |
| **Never** | A stock image, an AI image or the pattern (direction §6.4). Test: no `svg[data-weave]` in a card |
| **Unnamed salon** | « Salon », initial « S », alt « Salon », and the heart's label reads « Ajouter Salon aux favoris ». SYSTEM §17.2 |
| **Long name** | Wraps, and the card grows. F6's 54 characters take 3 lines in a 288 row (164 high against 116, measured), 2 on a 290 tile. Today's `truncate` does not truncate at all: F6 pushes `/recherche` to 489 wide and the landing to 506 at 390, and spills out of its card at 1280 (seen in `10-before-*`). The new card has no overflow from 195 wide up (measured). A defect fixed, and the PR says so |
| **No rating** | `reviewCount` 0 or absent: « Nouveau », as today |
| **Rating** | « ★ 4,8 (32 avis) », words the salon page already uses (`Hero.tsx:52-57`) |
| **« Nouveau », verified** | Unchanged |
| **No price** | The line is gone, and with a heart the spacer's row still holds the heart's band |
| **No commune** | The line is gone. The app shows `city ?? address`: filed |
| **Heart, unknown** | `favoriteBusy`: ♡ at 50%, `disabled` |
| **Heart, pending** | `favoritePending`: 50%, `aria-disabled`, `aria-busy`, keeps focus, a second press writes nothing |
| **Heart, signed out** | ♡. Goes to `/connexion?returnTo=…` |
| **Heart, off / on** | ♡ `textTertiary` / ♥ `text-error`, `aria-pressed`, its label, and the toast with « Annuler » |
| **Heart failed** | The sentence under the row, `role="alert"` |
| **Heart on a tile** | No caller passes one in S3. The slot is built and tested anyway, so C6 only has to wire it |
| **A favourite whose salon stopped** | Stays in the list, with its photo, not a link (`linked={false}`), no hover, and the sentence under it (`AccountClient.tsx:487-495`). Removing it says « Retiré des favoris » with no « Annuler ». At a short name, away from a pointer, the card looks the same as today (byte-identical in the pictures), so sheet 07 shows the pointer and a long name. The link it had ended on a 404 once the ISR window closed (`[slug]/page.tsx:21-46`, inferred from the path) |
| **0 salons (production today)** | `/`: section hidden. Landing: flush-left `EmptyState`, with the links below it. `/recherche`: count hidden, flush-left `EmptyState`. Favourites: centred, with its link |
| **List unreadable** | Unchanged. `/` and landings throw, so ISR keeps the last good page and a build fails, while a preview degrades to empty (`public-read.ts:20-26`). `/recherche` throws to `app/error.tsx` (inferred). Favourites: `ErrorState` with retry (`:460-465`) |
| **Loading** | Unchanged. None on server pages. Map: `Loading`. Hearts disabled while `favRead==='loading'`. Account: `SkeletonRows` |
| **200% text** | Boxes that hold text have no fixed height. Measured with Chromium's mobile text scaling, name 16 to 32px, in the real list. **At 320:** no sideways scroll, no text under a heart, names whole. Rows 300 to 388 high, F6 620. « Port-/Bouët » breaks and the price takes four lines: long, and nothing lost. **At 390:** rows 220 to 268 high, F6 452. **A tile at 288:** 408 to 448 high. Android's text scaling is the real case, UNVERIFIED on a device. iOS « aA » is page zoom: 200% on a 390 phone is a 195-wide page, below every gate on the site. At 195, no sideways scroll (measured), and « 1 500 000 » enters the heart's box by 12px, because a seven-digit price cannot break (measured on the earlier prototype, same widths). Recorded, not handled: only at that width with that price. **A long one-word commune breaks:** « Yamoussoukro » with no price reads « Yamousso / ukro » at 320 and « Yamoussoukr / o » at 390 (looked at). Nothing is lost and nothing meets the heart, though the second reads awkwardly, and an e2e holds it (§14). **« Carte » at doubled text is 120 wide, so its right edge is 136:** at 320 it passes the text column's 124 by 12 and covers the start of a row's text, at 360 it clears 137 by 1.6, and at 390 it clears 147 by 11.6 (measured 2026-11-05 with the same emulation, looked at). Recorded and not handled: the e2e reads normal text, and the centred button covered more |
| **320 wide** | Row 288: photo 96×72, text 180, 116 high, price on two lines, no overlap (measured). The stub's « Beauté Divine » is 98 wide in that 180 column |
| **« Carte » over the list** | At the page's gutter: x=16, 84 wide, 48 tall, right edge at 100, at every width below `lg`. It passes over the photo column and the letters on it, and over no row's text, at 320, 360, 390, 768 and 820, with each row brought under it (measured 2026-11-05; an e2e holds it). On the first screen at 320×568 it covers the start of « Disponible aujourd’hui », where the centred button covered its middle, and its foot reaches the top of the line box of « 8 salons », with the ink clear (looked at). This row used to say it sat over the first card's name « as it does today », which was wrong (decision 5). At doubled text it does reach text at 320 (the 200% row above) |
| **The map view on a phone** | The toggle reads « Liste », x=16, 78 wide, 48 tall, at y=772 at 390. No map control is under it: the zoom is top left, « Autour de moi » top right, the attribution bottom right (measured; an e2e holds it). A salon's marker can pass under it, as under any floating button: on the stub's list one sat 3px above it. At 390×844 the map's box ends at y=789, so the button hangs 31px past its foot: the map's height assumes a taller header (`100dvh-6.5rem` against a 49px header, the same line on `main`), not changed here. The tap comes back to the list |
| **Forced colours** | The fill goes. The tile keeps only its bottom rule, and the letter or the logo carries it: a failed photo is the letter above a line, not white space (seen). The rule is interrupted under the letter (inferred: the text backplate). A logo and a photo themselves are unchanged, and a loaded photo's hidden letter interrupts the foot rule too: it starts 8.5–39 CSS px in (measured on the pictures). The heart changes glyph, not only colour. Chromium's emulated palette only. **Existing limit:** `ring-2` is a box-shadow, so the selected row loses its ring in this mode (inferred). The scroll still lands on it. Not made worse |
| **Keyboard** | Two stops, in order: the link, then the heart. They are siblings, never nested. Each has the global 2px ring at 2px offset, the link's around the whole card, the heart's following its `rounded-pill`. The name underlines with focus as with hover. On `/recherche` either stop highlights the marker (`:288-293`). The gaps are at least 16px, so the link's ring touches no neighbour. A stopped favourite has no link stop |
| **Selected from the map** | Scrolled to, `ring-2 ring-primary ring-offset-2`, square. A faint rule shows just inside the ring's foot, and on a row after the first one just inside its top as well (seen), left as it is |
| **Install banner** | Unchanged |

### 2.5 Against the app

| | App | Web after this |
|---|---|---|
| Cover photo | Yes | **Yes: the gap this closes** |
| Shape | 1.24–1.82, or 1:1 in the list | 4:3 everywhere (direction §6.4) |
| List layout | Thumbnail left, 80×80 | Row, photo left, a third of the width. Same idea, larger |
| No photo | A grey third-party image | Logo or initial. Web ahead |
| Price, logo fallback | No | Yes. Web ahead |
| Heart, unknown and in flight | Tappable, no guard | Disabled, guarded. Web ahead |
| Review count | `★ 4,8 (32)` | « ★ 4,8 (32 avis) » |
| **Stopped favourite** | Tappable, opens a sentence | Not a link. **Less than the app in reach, safer than a 404.** A view of its own is a separate slice |
| **Heart on every card** | Yes | `/recherche` and the salon page only. **Less than the app** (decision 4) |
| **Grid/list toggle** | Yes | Fixed per page. **Less than the app,** filed |
| **Search, sort, map from a landing** | Yes, on its list screen | None. **Less than the app** (decision 4) |

### 2.6 Copy

No new words. « Logo {name} » is `Hero.tsx`'s own alt. « (32 avis) » is `SalonRating`'s own. Everything else already exists: « Nouveau », « à partir de », « Salon », the empty states, « Retiré des favoris ».

### 2.7 Reuse

`SiteSection`, `SITE_CONTAINER`, `SalonRating`, `salonNameOr`, `chipLinkClasses`, `EmptyState`, the home page's ruled index. Task-page `Card` is untouched.

---

## 3. API & contract

**No change to the API, `openapi.yaml` or generated types.**

| Read | Fields used by the card |
|---|---|
| `GET /providers` (`/`, landings, `/recherche`) | `slug`, `name`, `verified`, `rating`, `reviewCount`, `commune`, `services[].price/active`, `currency`, `imageUrls[0]`, `logoUrl` |
| `GET /me/favorites` through `/api/me/favorites` | The same, plus `status` |

**Direction §9's confirmation: in code yes, live no.**
- **Code:** the route returns repository maps with no projection (`routes/providers/index.dart:24-28,52-59`). The repository selects `data` and returns the whole document (`postgres_providers_repository.dart:56,665`), and `byIds` the same (`:78-86`). `imageUrls` is stored in `data` (`:294`), and `logoUrl` too (`:362-363`). The contract agrees (`openapi.yaml:1681-1687,5398,2032,5458`).
- **Live: UNVERIFIED.** `GET api.myweli.com/providers` read `total: 0`, the demo salon is a permanent draft, and staging is `absent`.
- **Nothing pins it.** `backend/test/providers_test.dart` mocks the repository and has no `imageUrls`, and the Postgres test reads by id. **So one backend test, in its own PR:** in `backend/test/db/postgres_repositories_test.dart`, beside `:824`, write a gallery and a `logoUrl`, then read both through `query()` and through `byIds()`, because the favourites read depends on the second. Mutate each SELECT to watch it red. A route test over a mocked repository could not see a SELECT change. **Merging it starts `deploy-backend.yml`** (§9).

---

## 4. Data model

None. Same documents, no migration.

---

## 5. Architecture & patterns

| File | What changes | Reach to the five pages |
|---|---|---|
| `components/provider/ProviderCard.tsx` | §2.2. Additive props: `layout`, `imageSizes`, `imagePriority`, `linked` | Outside |
| `lib/salon-name.ts` | `salonInitial` | Outside |
| `components/EmptyState.tsx` | `align?: 'center' \| 'start'`. `start` drops the box, `p-xl`, `text-center`, the action's `justify-center` and the icon's `mx-auto`, and gives the icon `-ml-s`: the search glyph starts 3/24 inside its 64px box, 8px, so without it the lens stands 8px right of the title (seen). Both `start` callers use `icon="search"`, so no other glyph needs an offset. `plain` alone would keep `p-xl` and break the edge | Outside |
| `components/SiteFaqList.tsx` | New | Outside |
| `app/page.tsx`, `app/professionnels/page.tsx`, `TaxonomyLandingView.tsx`, `RechercheClient.tsx`, `AccountClient.tsx` | §2.3 | Outside |
| `components/pro/AvisClient.tsx` | `unoptimized` on the review photo's `Image` (§6) | Outside |
| `tailwind.config.ts` | `aspectRatio.card`, `content.initial` | The stylesheet (§13) |
| `next.config.mjs` | `images.minimumCacheTTL` | None in the client bundle or HTML (§13) |
| `tests/e2e/_cdn-stub-dns.cjs`, `playwright.config.ts`, `ci.yml`'s `web-lighthouse` | Tests only (§8) | None |
| `web/tool/check-card-photo.spec.ts`, `package.json`, `production-checks.yml` | The scheduled check (§9) | None |

**Not edited, because they are in the five pages' graph:** `lib/siteGrid.ts`, `SiteChrome`, `Header`, `SiteFooter`, `FooterMark`, `Icon`, `ErrorState`, `styles/tokens.ts`, `lib/account/appointments.ts`, `lib/landing.ts`, `lib/format.ts`, `not-found`, `error`. They are imported, not changed.

---

## 6. Security & authz

- **No new origin, no new write, no new auth.** Signed-out pages read what they read today, and favourites stay behind the session cookie through `/api/me/favorites`.
- **`remotePatterns` stays the same three hosts** (`next.config.mjs:289-293`). `/_next/image` is same-origin, so CSP's `img-src` (Report-Only, `:162-168,253`) needs nothing. `https://cdn.myweli.com` is already allowed there for `AvisClient`'s direct file.
- **What a salon can put in the URL:** a new gallery value must be a promoted upload. An invented one is refused (`upload_verification_service.dart:231-238`). The `https://` check is for dev seeds, not a security boundary: the server is the authority.
- **The long cache and erasure. This is the one change that reaches a store-linked page, with no word changed.** `minimumCacheTTL` is global, and consumer erasure really deletes public files (`user_erasure_service.dart:167,179`). `/suppression-compte` lists review photos under what is deleted (`page.tsx:121`) and says reviews stay « sans les photos » (`:139-140`); its « au mieux » caveat covers only a storage failure (`:125-128`). `AvisClient.tsx:195-202` puts those photos through the optimizer, so a copy could outlive the object by up to 31 days instead of 60 s (or 3600 s, §7). Reachable only with the exact `/_next/image` URL, and that URL holds the erased client's id, which is the exposure `account-deletion-erasure.md` §11 records as a past wrong answer (inferred for the cached copy: Vercel's retention after a source delete is UNVERIFIED). Production has no reviews today.
  - **The answer, decision 1 (a):** `AvisClient` adds `unoptimized`, as `ProDepositProof.tsx:110-113` already avoids the optimizer for the same reason and `ReviewList.tsx:62` already uses a direct file. Cost: `/pro/avis` downloads full files for 96px thumbnails, up to 5 MB each (`upload_signing_service.dart:77`). They stay lazy.
  - **Avatars and deposits do not reach it:** the importers of `next/image` are `FooterMark`, `Header`, `ProAuthHeader`, `BeforeAfterViewer`, `Gallery`, `Hero`, `AvisClient`, and now `ProviderCard`. Only `AvisClient` shows a file erasure deletes. A source pin holds that list and the door (§8), because `<Image>` on a review photo would look harmless: the three brand importers show literal `/brand/` files and nothing else, and no file that reads `photoUrls` or `avatarUrl` may import `next/image`, `Gallery`, `Hero`, `BeforeAfterViewer` or `ProviderCard`, with `AvisClient` the only exception, for `next/image` alone. Current code passes it, read and run.
  - **Salon photos stay in the cache:** removing a photo deletes no object today, and logos are not erased with the account (`salon-logo.md` §6, declared residual). So 31 days adds no exposure there now. If salon erasure ever deletes objects, this TTL becomes a residual to state there.
  - `account-deletion-erasure.md` §11 gains one line saying why review photos never go through the optimizer. `docs/BACKEND.md` §7 has no new boundary under this answer.
- **No PII on cards:** `imageUrls` and `logoUrl` are public fields.
- **Recorded, not changed:** the data pass found no file-byte check in the signing or verification code. `next/image` re-encodes what it serves (inferred), which cards now rely on as the hero does.
- **Flagged for the owner, not touched:** `politique-confidentialite/page.tsx:196-199` says files are hosted by Cloudflare R2. Resized copies of public salon photos also sit in Vercel's cache, and cards widen what the hero already does. Vercel is named as the site's host in the same sentence, so it is incomplete rather than false (my reading). **It is one of the five pages, so nothing changes during review.** Filed in B11.5.

---

## 7. Performance

### Where a card photo is the Largest Contentful Paint

Which element won, on the prototype, unthrottled, with photos intercepted. **Nobody has measured an LCP time with a real card photo.**

| Page | 360×640 | 412×823 | 820×1180 | 1440×900 |
|---|---|---|---|---|
| `/` | No, first photo at y=915 | No: `<h1>` | **Yes**, while lazy | No: `<h1>` |
| `/coiffure` (root) | No: `<p>`, first photo at y=653 | **Yes** | **Yes** | **Yes** |
| `/coiffure/abidjan` (city) | No: `<p>`, first photo at y=699 | **Yes** | **Yes** | **Yes** |
| `/coiffure/abidjan/marcory` (area) | **Yes** | **Yes** (107,920) | **Yes** | **Yes** (81,510) |
| `/recherche?q=vitrine` | No: `<h1>`, first photo at y=588 | **Yes**, by a small margin (11,938) | **Yes** | **Yes** (45,880) |

**So direction §7.3's « lazy » and §11's « below the fold » hold only for `/` at the sizes Lighthouse and a desktop use.** A lazy image is invisible to the preload scanner, so on these pages it would be fetched late while being the page's largest paint. But at 360×640, the width SYSTEM.md calls modal in Côte d'Ivoire (`SYSTEM.md:490-491`), two landing levels and `/recherche` would preload a photo that is off-screen.

| Page | Rule |
|---|---|
| `/` | All lazy, as direction §11 says. `priority` would preload a photo for phones, where it is off-screen, against the budgeted LCP. At 820×1180 the photo is the LCP and lazy: no budget sits there, so this is recorded and not changed |
| Landings, `/recherche` | **The first card's photo has `imagePriority`, on all four levels, and every other photo is lazy** (the rule below, decision 6). Exactly one preload, which follows `sizes` (on the prototype, the phone tile picked 828w at 412×823 and 750w at 390; on the branch at DPR 1.75, 750w at 412 and 640w at 360). The bytes are the same with and without it, measured below. At 360×640 root, city and `/recherche` fetch it while it is off-screen, and a list whose first salon has no photo preloads nothing |
| Favourites | All lazy. Noindex, behind sign-in, and no budget |

**It had to earn its place. The rule, so nobody had to judge it later:** for each of root, city, area and `/recherche`, compare the median LCP with and without the prop, **under applied throttling (`lighthouse --throttling-method=devtools`)**. Keep the prop on that level only if it falls by at least 100 ms at 412×823 and does not rise by 100 ms or more at 360×640. Otherwise take it off that level. If no level keeps it, the prop comes out and direction §7.3's word stands.

**The method is the owner's answer of 2026-11-05, and the outcome is the prop on all four levels: root, city, area and `/recherche`. The owner chose it (decision 6).** The rule first named a metric and no method, and was applied to the simulated estimate, because `lighthouserc` names none. That estimate does not model the request starting earlier, which is the one thing the prop does, so it cannot read this question. Applied throttling delays the real requests, so it can. Both tables below stay as the record. The bytes are the same either way. **Lighthouse's own budget gate stays on its method: `lighthouserc.json` does not change, and no budget moves.**

### Budgets

| Page | Budget | After S3 |
|---|---|---|
| `/`, `/suppression-compte` | LCP 2500, CLS 0.1, TBT 200, scripts 179,200 (`lighthouserc.json`) | **Unchanged, not raised.** S2 stands at 2115 and 2109 ms. **Scripts, on the final tree:** 162,492 to 162,497 B on `/` and 164,540 to 164,545 B on `/suppression-compte` against 179,200. Against `main`, by Lighthouse's transfer sizes, +376 to +381 B on `/` and +587 to +592 B on `/suppression-compte`, in two reads; the table below read +310 and +521 B; §13's sum of distinct gzipped files reads +302 B at most. All are under §13's 1 KB and the budget. This row used to say about 320 and 300 B, from the prototype. The gate decides, and passed |
| `/connexion` | LCP 2900 | Unchanged. S2: 2713 ms |
| Landings, `/recherche` | None | **None added in S3.** In CI the stub's image host does not resolve, and in production the landings are empty, so a budget today would measure a page without its largest paint: the failure `ci.yml:736` warns about. B11.4's line gains them, with the same way of serving real bytes |

**Measured before the merge, recorded in this spec.** A throwaway worktree with the stub, and the real optimizer fed real bytes with no host added and no certificate: a `--require` preload that rewrites `https://cdn.stub/` to a local plain-HTTP file server inside `globalThis.fetch`, never committed. Tried on the prototype: `/_next/image?url=https://cdn.stub/f1.jpg&w=640&q=75` answered 200, 59,909 B, with `Cache-Control: public, max-age=2678400, must-revalidate`. Name the files as the fixtures name them.

| Runs | Pages |
|---|---|
| Five each at 412×823 with `lighthouserc`'s throttling | `/`, `/connexion`, `/suppression-compte` |
| Five each at 412×823 and at 360×640, with and without `imagePriority` | `/coiffure`, `/coiffure/abidjan`, `/coiffure/abidjan/marcory`, `/recherche?q=vitrine` |

Delete `.next/cache/images` before each series. Read LCP **and which element it is**, CLS, TBT, and image requests and kilobytes. **Local numbers compare only with local numbers:** `sharp` is absent, so `next start` falls back to squoosh (`image-optimizer.js:709`), and the first hit is a transformation.

**With and without the prop, 2026-11-05, on `af79b362`.** The « without » build is that commit with the prop off both callers, uncommitted. Lighthouse 12.1.0 with `lighthouserc`'s settings, whose method is `simulate` because the file names none (read back in each run's `configSettings`). Google Chrome 156, `--headless=new`, DPR 1.75 at both sizes. Medians of five, the two builds side by side, with `.next/cache/images` deleted before each series, so the first run of each is the cold transformation. Bytes: `f1` and `p1` are `salon_excellence_photo.png`, `f2` and `p2` `barber_shop_pro_photo.png`, `f6` `spa_relax_photo.png`, `f3-logo.png` `maison-nala-logo.png`, and `absent.jpg` a 404. **The element is read from each run's own trace** (`largestContentfulPaint::Candidate`), because Lighthouse 12.1's `largest-contentful-paint-element` audit errors on this Chrome (« Cannot read properties of undefined (reading 'frame_sequence') »).

| Level | 412×823 with | without | Change | 360×640 with | without | Change | Largest paint, 412 · 360 (5 of 5, both builds) | The rule |
|---|---|---|---|---|---|---|---|---|
| Root, `/coiffure` | 2562 | 2487 | **+75** | 2559 | 2484 | +75 | Photo · `<p>` | Off |
| City, `/coiffure/abidjan` | 2412 | 2260 | **+152** | 2411 | 2261 | +150 | Photo · `<p>` | Off |
| Area, `/coiffure/abidjan/marcory` | 2635 | 2485 | **+150** | 2635 | 2485 | +150 | Photo · photo | Off |
| `/recherche?q=vitrine` | 2485 | 2527 | **−42** | 2525 | 2483 | +42 | Photo · `<h1>` | Off |

**On this method no level fell by 100 ms at 412×823, so `571038b2` took the prop out. That was the rule as first applied, and this table is its record.** CLS 0 in all sixteen series. TBT 0 on the landings, and 49–64 on `/recherche`, with one cold run at 1146 (with the prop, 412). Image requests and kilobytes are the same with and without: root and city 2 requests (the header's mark and one photo), 56 KB at 412 and 47 KB at 360; area 6 requests, 144 KB and 118 KB; `/recherche` 6 requests, 34 KB at both, because a row picks 256w. The photo itself does load sooner with the prop: in the simulation it ends at 770 ms against 1886 on the area level at 412 (`metrics.lcpLoadEnd`, one run). The simulated LCP stays near 2500 either way.

**What that number cannot see, and the table the rule reads now.** The same two builds and the same file's numbers, with `--throttling-method=devtools`, which applies `requestLatencyMs`, `downloadThroughputKbps` and `uploadThroughputKbps` to the real requests instead of estimating. `lighthouserc` does not run this method, and it did not have to: the budget gate stays where it is. Medians of five:

| Level | 412×823 with | without | Change | 360×640 with | without | Change |
|---|---|---|---|---|---|---|
| Root | 1673 | 2654 | **−981** | 1523 | 1504 | +19 |
| City | 1669 | 2970 | **−1301** | 1520 | 1504 | +16 |
| Area | 1674 | 2761 | **−1087** | 1631 | 2584 | −953 |
| `/recherche?q=vitrine` | 1495 | 3005 | **−1510** | 1497 | 1453 | +44 |

By the rule, this table keeps the prop on all four levels, where the simulated one takes it off all four. The largest paint is the same element in both. **The mechanism, seen in the requests:** on the city level at 412, the lazy photo's request starts at 1426–1668 ms, after the stylesheet, and with the prop at 582–584 ms, beside it, which is what the paragraph at the top of this section predicted. **Why the simulation misses it (inferred):** its LCP is not set by the photo on these pages. The photo ends at 770 ms in that simulated run and the LCP still reads 2635, and the text-only `/suppression-compte` reads 2108, so about 2100 ms is a floor that a photo does not move. Lighthouse's own warnings are off too: `lcp-lazy-loaded` and `prioritize-lcp-image` error on this Chrome, as the element audit does. **CLS under this throttling:** 0.167 on the city level at 412 (5 of 5 with the prop, 2 of 5 without) and 0.068 on the area level at 360 (5 of 5 both). The cause was not read, because `layout-shifts` errors as well. The owner's answer is that the rule reads this table, and the code half of `571038b2` came back by hand, which restored the prop on every level. For scale, on the city level at 412 with this throttling: `main`, which has no photo there, 1513 ms on a `<p>`; the committed branch, lazy, 2655 ms on the photo; with the prop, 1669 ms on the photo. That page's CLS predates this slice: 0.176 on `main` in 4 of 5 runs, 0.167 on the branch in 5 of 5.

**The branch as it stood at `571038b2`, with no prop, against `main` (`ea0c8f0c`),** kept as the record: same session, same simulated method, each built as CI's `web-lighthouse` builds it, medians of five:

| Page | Budget | `main` (range) | Branch (range) | Largest paint, both | CLS, TBT | Images, branch | Scripts, `main` → branch |
|---|---|---|---|---|---|---|---|
| `/` | LCP 2500, scripts 179,200 B | 2110 (2109–2127) | **2261** (2128–2264) | `<h1>`, 5 of 5 | 0, 0 | 2, 56 KB (`main` 1, 2.4 KB) | 162,178 → 162,488 B |
| `/connexion` | LCP 2900 | 2755 (2412–2865) | **2754** (2112–2864) | `<p>`, 5 of 5 | 0, 0 | 1, 2.4 KB | 239,229 → 240,665 B, no budget |
| `/suppression-compte` | LCP 2500, scripts 179,200 B | 2109 (2108–2412) | **2411** (2108–2569) | `<p>`, 5 of 5 | 0, 0 | 1, 2.4 KB | 164,015 → 164,536 B |

**No budgeted page is over its budget.** `/` moved about 150 ms, one simulated round trip, in every series that had a photo. The other two are the modes WEB.md §7 names: `af79b362` read `/connexion` 2865 (2563–3318) and `/suppression-compte` 2108 (2108–2263) in this same session, on code that does not reach them. One `/suppression-compte` run read 2569, above its budget, and the gate reads a median: close, not a breach.

| Level, branch | 412×823 | 360×640 | Largest paint, 412 · 360 |
|---|---|---|---|
| Root | 2484 | 2484 | Photo · `<p>` |
| City | 2259 | 2259 | Photo · `<p>` |
| Area | **2639** | **2640** | Photo · photo |
| `/recherche?q=vitrine` | **2663** | 2482 | Photo · `<h1>` |

**Over 2500 ms on this estimate, with no prop: area at both sizes and `/recherche` at 412. That went to the owner, with no number set to make it pass, and decision 6 answered it.** CLS 0. TBT 0 on the landings, with one run at 10, and 47–54 on `/recherche`. The « without » build above differs from this one only by a prop nothing passes, and it read area 2485 at both sizes and `/recherche` 2527 at 412. So two reads of what is in effect one build differ by up to about 150 ms, and a 100 ms threshold on five runs sits inside this metric's noise. Each level's first, cold run read 2873–3480 at 412.

**If a budgeted page breaches, the budget does not move** (direction §11). If a landing or `/recherche` is over 2500 ms, that goes to the owner as a finding, with no number written down to make it pass.

**Bytes, measured.** `/` reads `searchProviders({ pageSize: 8 })`, so the number to read is eight photos, not the four this line used to infer. With eight distinct photos in a throwaway stub, never committed, five runs each: at 412×823 (DPR 1.75) **seven of the eight are fetched on load,** all 750w, 277 KB; at 360×640 **all eight,** 640w, 271 KB. None is on-screen, and the largest paint stays the `<h1>` (2260 and 2261 ms). With the stub's one card it is one photo, 54 KB at 412. **These demo files are small** (50–106 KB PNGs), so what a real photo weighs is UNVERIFIED. Many visitors pay per megabyte and there is no image budget to break, so this still needs looking at.

**The hidden map costs more than the photos, and predates this slice.** `/recherche?q=vitrine` at 412 and at 360: 52 requests and 1200 KB. The photos are 34 KB of that. 640 KB in 17 requests goes to `basemaps.cartocdn.com` and `tiles.basemaps.cartocdn.com`, and one script is 268 KB, for a map that is `display: none` below `lg`: `RechercheClient` mounts `ResultsMap` inside `hidden lg:block`, as `main` does (seen in `main`'s source; the bytes were read on the branch). Not changed here, and it goes to the owner.

**CI's Lighthouse does not see a photo.** On `/` the page requests `/_next/image?url=https://cdn.stub/p1.jpg`. With real bytes locally the `<h1>` holds in 5 of 5, and the number does move, 2110 to 2261 ms (above). This line used to infer that it would not. CI's request fails at once instead of loading, so its effect there is still unread: the preload in §8 keeps that request from stalling, and the first CI run gets read for this.

### What a photo costs on Vercel

- **No object gets a `Cache-Control` header at upload** (`storage_service.dart:303,416`, seen in the signing code; **no served header of a real object has been read**, so what `cdn.myweli.com` answers is inferred). `minimumCacheTTL` is unset, so the TTL is Next's default of 60 s (`image-config.js:56`). Vercel's doc says 3600 for this: **UNVERIFIED which.** One saved read, `live/opt5.h`, a `/_next/image` of a local file on the live site, shows `x-vercel-cache: HIT` with `age: 156`, past 60 s: a different kind of source, so not conclusive.
- **The arithmetic, from the data pass, assuming 15 photos per view, none of it observed:** about 330 `/recherche` views a month would reach Hobby's 5K. Over it, new images would fail with a 402, which is §2.4's letter on a tile, and files already cached should keep answering (inferred; Vercel's answer past the ceiling is UNVERIFIED). `check:card-photo` asks for one new transformation a day so that it can see this (§9), about 31 a month, 0.6% of that 5K. On paid rates, 100K views would be about $75–122 a month.
- **The fix is one line:** `images: { minimumCacheTTL: 2678400 }`, 31 days, for a surface that has no photo views yet. It is safe for salon photos because keys are random and a replaced photo gets a new URL (`upload_signing_service.dart:182`). Cost then falls to about photos × widths a month (arithmetic). **It is not free of consequence: §6.** Next's own optimizer honours it locally (measured above); Vercel's is UNVERIFIED.
- **`deviceSizes` stays,** because changing it would change what the client bundle inlines.
- **The plan is UNVERIFIED.** No doc names it and no header reveals it. The owner reads it (§9).

---

## 8. Testing plan

Every new guard is watched red **on committed work**, and the commit records it. A mutation that does not apply is no result. On the prototype today: `vitest` 195 files, 2550 tests green; `tsc` and ESLint clean on the changed files. **Playwright, axe and Lighthouse have not run on it.** **On the branch's final web tree, `f7d1691e`, 2026-11-05:** ESLint and `tsc` clean, `gen:api` no drift, `vitest` 199 files and 2602 tests green, `next build` passes, Playwright 504 passed with none skipped or flaky, Lighthouse's three budgeted pages pass over 9 runs (`/` 2183 ms, `/connexion` 2755 ms, `/suppression-compte` 2411 ms, CLS 0 and TBT 0 on all three).

### New guards

| Guard | Holds | Watched red by |
|---|---|---|
| `provider-card.test.tsx` | Photo > logo > initial, one at a time. Alt is the name, « Logo {name} », and « Salon » unnamed. The letter is hidden from readers, and with a photo it comes before the `<img>` in the DOM and matches `data-initial`. No letter with a logo | Drop the logo branch. Put a letter beside the logo. Move the letter after the `<img>` |
| Same | `asset:…` and `''` read as no photo, and no `<img>` | Remove the `https://` check |
| Same | No `rounded-*`, `border ` or `bg-secondary` on the `<a>`. No `svg[data-weave]` | Put `rounded-xl` back |
| Same | Each layout's default `sizes`. `account`'s `srcset` has a candidate of 256w or less | Change `account` to `…, 92vw`. **This is the trap in §2.2** |
| Same | The photo: lazy by default, with no `fetchpriority="high"`. With `imagePriority`: high, and no `loading`. A logo stays lazy with the prop | The prop does nothing. The logo takes it too |
| Same | The spacer exists only with a heart, and is `h-12 w-12` | Render it always. Drop `h-12` |
| Same | No `truncate` or `whitespace-nowrap` in the card. The name and the mark are one inline run | Put `truncate` back |
| Same | `linked={false}`: no `<a>`, no `group-hover`. Default: an `<a>` to `/{slug}` | Default it to false |
| Same | « (32 avis) » with reviews, « Nouveau » without | Drop `withCount` |
| `salon-name` table | Accent, decomposed accent, leading « «, emoji, digit, blank, `!!!` | Use `charAt(0)` |
| `empty-state` unit | Default is byte-for-byte today's classes. `start` has no box, `p-xl`, `text-center`, `mx-auto` or `justify-center`, and has `-ml-s` | Put `justify-center` back in `start`. Drop `-ml-s` |
| `tokens.theme-pin` | `aspectRatio.card` and `content.initial` are wired | Rename one in the config |
| `next-config` unit | `minimumCacheTTL` ≥ 30 days. `remotePatterns` is exactly the three hosts | Delete the line. Add a host |
| **New source pin: `optimizer-sources.test.ts`,** in the shape of `no-public-provider-read.test.ts` | The files importing `next/image` or `next/legacy/image` are exactly the eight in §6, across every directory of `web/` except `tests`, `tool`, `scripts`, `public` and what never ships. `AvisClient`'s `Image` carries `unoptimized`, bare or `{true}`, spaced or not. **The door:** each brand importer's `<Image>` has a literal `/brand/` src, and no file that reads `photoUrls` or `avatarUrl` imports `next/image` or a component that puts what it is given through it, `AvisClient` alone excepted for `next/image`. Its message says why: a file erasure deletes must never enter that cache | Remove `unoptimized`. `unoptimized={false}`, which the first version read as the word and let through, and `unoptimized = {false}`, which the second did. Add an importer, a `.jsx` or a new top-level directory. An avatar on the header. A new file rendering review photos through `Gallery` |
| `pro-avis` render | A review photo's `src` is the file's own URL, not `/_next/image` | Remove `unoptimized` |
| **New e2e: the card** (`site-look.spec.ts`), `/recherche?q=vitrine` and `/coiffure/abidjan/marcory`, at 375 and 1280 | **The media box's** ratio is 1.33 ± 0.02: the rule takes 1px from the `<img>`, whose own ratio reads 1.34–1.35 (measured). On the `<img>`: `border-radius` 0, `filter: none`, `opacity: 1`, `mix-blend-mode: normal`. On the media box and the link: computed `::before` and `::after` `content` are `none`. `elementFromPoint` at the photo's centre is the `<img>` | `rounded-sm`, `aspect-video`, a `brightness-90`, an overlay `div`, and **a pseudo-element scrim** on the link, which `elementFromPoint` cannot see |
| Same, a failed photo | `naturalWidth` 0, the ratio holds. **Read from pixels:** a helper in `_pixel.ts` screenshots the tile and reads it on a canvas. The top-left 30×30 is one colour, `rgb(245,245,245)`, and the bottom-left holds dark pixels, the letter. Computed style alone proves a rule exists, not that it paints | Remove `after:` from the photo: 548 colours in that corner (measured). Remove `after:content-initial`: no dark pixels |
| Same, a slow photo | With `/_next/image` held open, the tile holds its ratio and the letter is visible. With it loaded, `elementFromPoint` at the bottom-left is the `<img>` | Drop the letter. Put it after the `<img>` |
| **New e2e: heart and text,** at 320, 390 and 200% text, with the fixtures that include the long name and F9 (rated, three-digit count, no commune, no price) | No text's range rectangle meets the heart's box. `scrollWidth` equals the viewport | Remove the spacer. Drop its `h-12`. Remove `min-w-0` from « Trier » at 320 and 200%: 322 wide (measured) |
| Same, 200% | **Non-vacuity first:** the name's line box is at least 40 high, or the check proves nothing. Emulated with `isMobile` and `text-size-adjust: 200%`, measured to double | Drop the emulation and see the first assertion fail |
| **New e2e: the first card's photo is fetched first** | §7's outcome: exactly one `img[fetchpriority=high]` in `main`, the first card's, and exactly one card photo in a `link[rel=preload]`, on all three landing levels and `/recherche`. None on `/` and none in the signed-in favourites. « At most one » would stay green with none, so it reads exactly one | Each level without the prop, and with it on every card. `/` or the favourites with it. `fetchPriority` with no preload |
| **New e2e: the selected row** | `border-radius` 0, computed `box-shadow` carries the 2px offset in `surface` | Remove `ring-offset-2` |
| **New e2e: favourites, signed in** | At 390 the media is a third of the row, at 820 the full tile. A stopped salon has no `<a>` in its card and its removal shows no « Annuler » button; a live one has both. The stub's `p4` is the stopped one (`stub-api.mjs:970`) | `layout="tile"`. `linked` always true. `announceFavorite` for a stopped salon |
| **New e2e: « Carte » over the list,** `/recherche?q=vitrine` at 320, 360, 390, 768 and 820 | Each of the eight rows is scrolled under the button, unless it is wholly above the button at the top of the page. The button's right edge never passes the left edge of a row's text column, and it stays at least 48 tall. A row that could pass under it and did not is a failure, so this cannot go vacuous. At 390 the map view reads « Liste », on no map control, and its tap comes back | Centre it again. `min-h-12` off. The zoom at the bottom left. A tap that stays on the map |
| **`focus.spec.ts`:** a card with a heart | Tab goes link, then heart. Each computes `RING`. The name underlines on focus | `tabindex="-1"` on the heart. Remove `group-focus-visible:underline` |
| **`site-look` SEO:** root, city, area | `<h1>`, title, canonical, JSON-LD types and `<h2>` list match a list **taken from `main` before any edit** | Change a word |
| **Test server:** `_cdn-stub-dns.cjs` | `GET /_next/image?url=https://cdn.stub/p1.jpg&w=640&q=75` answers ≥ 400 within 5 s (2026-11-05: this was 1 s, tighter than what it tells apart, 26 ms against 6 s and 30 s). It reads the speed, not the preload: on a Mac whose real lookup of `cdn.stub` fails at once it stays green with no preload at all | Swap the preload for one whose lookup never answers: no answer in 6 s (measured) |
| **New: `cdn-stub-preload.test.ts`** | The preload answers `fetch` for `cdn.stub` where a lookup that never answers stands in for CI's stall, leaves every other host to the real lookup, and keeps what `util.promisify` reads. `NODE_OPTIONS` sits on the step that runs `npm run lhci` in `web-lighthouse`, and on the Next server in `playwright.config.ts`, with each file's comments stripped | Let `cdn.stub` through, refuse every host, drop the symbols, never install it. Delete or comment out either line, move it to another step or to the stub, misspell the path |
| **New: `production-alarm-status.test.ts`** | Every check in `production-checks.yml`, derived from the file, has an env row reading its own `needs.<job>.result`, and that row's variable is in the report's status line | Drop « card photo » from the line. Drop or comment out its row. Point the row at another job. Add a ninth job with no row |
| **New e2e: a ruled index answers the pointer** | On `/`'s Catégories and `/coiffure`'s cities, the name's computed colour changes under a hover | The colour back on the name. The hover off the home page's link |
| **New e2e: a commune too long, at 200% text,** `/recherche?q=commune-longue` at 320 and 390 | No text meets the heart, the word really broke (two lines or more, so a word that fits proves nothing), and no sideways scroll | Remove `break-words`. Drop the doubling |
| **Backend list read, its own PR** | `imageUrls` and `logoUrl` through `query()` and `byIds()` on Postgres | Project them out of each SELECT |
| **`tool/check-card-photo.spec.ts`** (§9) | Three outcomes, and only these (§9) | A local build with a failing image and an empty image cache: red. `/recherche?q=vide`: a printed skip. A local server stopped: red. **A stand-in where the file already read answers 200 and anything new 402: red, where the first version stayed green.** A photo that never answers: red, and the failure names the photo |

### Existing guards that change

Every row is watched red once, and the commit records it.

| Guard | Change | Watched red by |
|---|---|---|
| `site-look` left edge (`:20-59`) | Add `/coiffure`, `/coiffure/abidjan`, `/coiffure/abidjan/cocody`, `/coiffure/abidjan/plateau` (empty) | Change a container's padding |
| `site-look` pattern (`:118-134`) | Add root and city. Its `/mon-compte` runs signed out, so it reaches the redirect. Add a signed-in read | Put a `data-weave` svg in a card |
| `site-look` no boxes (`:400-415`) | **For `/recherche`, root the check on `main`, not `main section`: the page has no `<section>`, so the old check would be vacuous there (measured: 0).** Assert a card exists first. Exempt `rounded-pill` and `.maplibregl-map, .myweli-marker`, as `controls-shape.spec.ts:30` does. Widen from `li a` to `a`. Add the three landings and `/recherche`. On the prototype: nothing found on any of them, and one box found when the old classes are put back on a card (measured) | Put `rounded-xl border` back on the card |
| `site-look` LCP (`:357-383`) | `/coiffure/abidjan/cocody` now holds a photo. No edit: its `networkidle` settles with the preload below. **Read 2026-11-05: the last entry is « page » at both sizes.** The reason is narrower than it looks: in the suite the photo never loads, so the entry is the `<p>`, and with a generated 1600×1200 file it is the `<img>`, in `main`. So this test only proves the footer does not win, and says nothing about LCP time or a real photo | None: no change, read on the first run |
| `type-overflow` (`:70-100`) | Add `/coiffure/abidjan/cocody`, `/coiffure`, `/coiffure/abidjan/marcory` and `/recherche?q=vitrine`. With no truncation there is no declared loss to protect the matrix from | Fix a width on the card's text |
| `tap-targets` (`:71-84`) | Add the row's heart, landing chips, crumbs, the city index, « Retirer » signed in | Remove `min-h-12` from the crumbs, chips and « Retirer ». The heart at `h-8`. The city index at `h-8` reads 32: it has no `min-h-12`, because that class held nothing there (§14) |
| `axe` (`:161`) | Add `/recherche?q=vitrine` and the signed-in favourites. It runs with no tag filter (`:129`), so **this is where `image-redundant-alt` gets its answer.** If it fires, the alt becomes `""` on a card whose name is beside the photo, and §12's line changes | Give a card's image an empty link |
| `controls-shape` | Holds, heart exempt (`:27`). `/mon-compte/favoris` (`:82`) has no route and falls into `[id]`: left, noted for B11.5, since `/mon-compte` covers the list | None: no change |

**The stall, fixed once, at the root.** Each visit to `/`, a landing, `/recherche` or signed-in `/mon-compte` now makes the Next server fetch the unresolvable `cdn.stub`, and `axe.spec.ts:48-56,73-76` and `type-overflow.spec.ts:559-561` record that as a 30 s stall on CI's libuv pool. The suite has `retries: 0` (`playwright.config.ts:28`), and about 62 `goto` lines or route rows hit these pages. A per-spec helper would have to reach all of them, and the next spec would forget it. So `web/tests/e2e/_cdn-stub-dns.cjs` patches `dns.lookup` to fail `cdn.stub` at once in the Next process, passed as `NODE_OPTIONS=--require ./tests/e2e/_cdn-stub-dns.cjs` in `playwright.config.ts`'s Next server and in the `npm run lhci` step of `web-lighthouse`. Tried on the prototype: a lookup made to hang gave no answer in 6 s; with the preload, a 500 in 26 ms. The same image failure the suite sees today, only fast. **`networkidle` then settles, so the six sites at `served-html:228,260`, `legal:131`, `store-linked-pages:105`, `controls-shape:103` and `site-look:375` need no edit.** `routeNextImages(page)` in `_pixel.ts` stays, only for specs that want a painted photo: it answers a pixel, and 404 for `absent.jpg`. **The first CI run gets read for suite duration as well as Lighthouse.** Next logs each failed image to the server's stderr, and Playwright prints it as `[WebServer] ⨯ TypeError: fetch failed`: noise in the job's log and no failure, as it already was for the salon page (corrected 2026-11-05: this said stdout, which nothing reads).

**Unchanged and expected to hold:** `provider-card` existing cases, `consumer-optimistic-revert` (the root is still `<a>`), `heart-announced`, `heart-read-throws`, `consumer-network-pages`, `account.spec`, `slow-phone`, `service`, `tokens.mirror`, `unnamed-salon`, `lighthouserc`. All of the unit ones pass on the prototype (measured). `discovery:136` reads `.ring-2`, which stays (passed on the branch, 2026-11-05).

### The stub

It returns one salon and ignores `q` (`stub-api.mjs:824-836`), so no list can show a no-photo or long-name card today.

- **New fixtures,** in `tests/e2e/card-fixtures.json`, returned only as below, so Lighthouse and every other spec keep the single card:

| Read | Returns |
|---|---|
| `q=vitrine` | F1 photo, F2 photo, F3 logo only, F4 initial only, F5 a photo at `https://cdn.stub/absent.jpg`, F6 long name, F7 unnamed with no price or commune, F9 rated with a three-digit count, no commune, no price |
| `commune=Marcory`, when `category` is absent or `salon` | F1 to F6. **Not F7:** a landing's `ItemList` would carry an empty name (`TaxonomyLandingView.tsx:277-283`). That is today's behaviour for an unnamed public salon, direction §1 bars a JSON-LD change in S3, and it is filed in B11.5. The unnamed tile is held by the unit test and the `/recherche` row. So `/barbier/abidjan/marcory` stays empty |
| `q=vide` | Nothing, for an empty `/recherche` |
| `q=commune-longue` | One row: F9 with « Yamoussoukro » as its commune, the one word too long for the column beside the heart at 200% text, with no price to lift it out of the heart's band. Its own read, so the eight every other spec counts stay eight |

- `/coiffure/abidjan/plateau` stays empty.

### Watched red: the record

Run 2026-11-05 on detached copies, on committed work. Each mutation applied by exact text with its match count asserted, the diff asserted non-empty, only that guard run, the copy restored and asserted clean. No guard was weakened to pass. Chromium only, on this Mac.

- **First pass, at `23eecdbd` (backend `747d6e39`): 128 rows, 114 red, 12 green, 2 printed skips.** The 12 green are 3 baselines, 6 controls or reads meant to be green, and 3 that stayed green under a mutation meant to turn them red.
- **Second pass, after the reviews: 42 rows, 31 red, 10 green, 1 printed skip.** Browser and `check:card-photo` rows at `c7f5ef9c`, unit rows at `f7d1691e`. The 10 green are 3 baselines, 4 controls, the old check and a blind copy of the new one on the stand-in (the finding itself), and one failing image that read green from the cache, which the next row empties.

**What stayed green under a mutation, and what happened to it**

| Guard | Mutation | Why it stayed green | Now |
|---|---|---|---|
| `tap-targets`, the city index | Remove `min-h-12` | The link is 65 tall without it, so the class held nothing | The class is gone (§14). The guard reads 32 under `h-8` |
| Test server, `_cdn-stub-dns.cjs` | No preload at all | This Mac's real lookup fails at once, so it reads the same | `cdn-stub-preload.test.ts` goes red on it, and on losing either `NODE_OPTIONS` line |
| `optimizer-sources` | `unoptimized={false}` | The pin read the word | It reads the value |
| The alarm test | « card photo » out of the status line | Nothing claimed that line | `production-alarm-status.test.ts` goes red on it |

**First pass**

| Guard | Mutation | Result |
|---|---|---|
| provider-card.test.tsx: photo > logo > initial | Drop the logo branch | RED |
| provider-card.test.tsx: no letter with a logo | Put a letter beside the logo | RED |
| provider-card.test.tsx: the letter comes before the `<img>` | Move the letter after the `<img>` | RED |
| provider-card.test.tsx: asset: and '' read as no photo | Remove the https:// check | RED |
| provider-card.test.tsx: no rounded-*, border or bg-secondary on the `<a>` | Put rounded-xl back | RED |
| provider-card.test.tsx: no rounded-*, border or bg-secondary on the `<a>` | Put border back | RED |
| provider-card.test.tsx: no rounded-*, border or bg-secondary on the `<a>` | Put bg-secondary back | RED |
| provider-card.test.tsx: account keeps a candidate of 256w or less | Change `account` to …, 92vw | RED |
| provider-card.test.tsx: loading=lazy, no fetchpriority=high | Put `priority` on it (for `loading`) | RED |
| provider-card.test.tsx: the spacer exists only with a heart | Render it always | RED |
| provider-card.test.tsx: the spacer is h-12 w-12 | Drop h-12 | RED |
| provider-card.test.tsx: no truncate or whitespace-nowrap; one inline run | Put truncate back | RED |
| provider-card.test.tsx: no truncate or whitespace-nowrap; one inline run | whitespace-nowrap on the rating | RED |
| provider-card.test.tsx: no truncate or whitespace-nowrap; one inline run | `<h3>` a flex row | RED |
| provider-card.test.tsx: the default is a link to /{slug} | Default `linked` to false | RED |
| provider-card.test.tsx: linked={false} has no group-hover | Keep the hover classes when not linked | RED |
| provider-card.test.tsx: « (32 avis) » with reviews | Drop withCount | RED |
| provider-card.test.tsx: asset: and '' read as no photo | The other half: test the photo with `!= null`, so '' reaches `<Image>` | RED |
| salon-name table (unnamed-salon.test.ts) | Use charAt(0) | RED |
| empty-state unit (b6-states.test.tsx) | Put justify-center back in `start` | RED |
| empty-state unit (b6-states.test.tsx) | Drop -ml-s | RED |
| empty-state unit (b6-states.test.tsx): default byte for byte | Change the default box | RED |
| empty-state unit (b6-states.test.tsx): `start` has no p-xl | Keep p-xl in `start` | RED |
| empty-state unit (b6-states.test.tsx): `start` has no mx-auto | Keep mx-auto in `start` | RED |
| tokens.theme-pin: aspectRatio.card | Rename it in the config | RED |
| tokens.theme-pin: content.initial | Rename it in the config | RED |
| next-config unit: minimumCacheTTL ≥ 30 days | Delete the line | RED |
| next-config unit: minimumCacheTTL ≥ 30 days | One day instead | RED |
| next-config unit: exactly the three hosts | Add a host | RED |
| optimizer-sources.test.ts: AvisClient carries unoptimized | Remove `unoptimized` | RED |
| optimizer-sources.test.ts: it does not read a comment | Turn the attribute into a comment: `// unoptimized` | RED |
| optimizer-sources.test.ts: exactly eight importers | Add an importer | RED |
| optimizer-sources.test.ts: exactly eight importers | Add a dynamic importer | RED |
| optimizer-sources.test.ts: a comment is not an importer | Control: the import only in a comment | GREEN |
| pro-avis render (pro-avis-summary.test.tsx) | Remove `unoptimized` | RED |
| provider-card.test.tsx: a favourite with no gallery does not throw | `.` for `?.` on imageUrls | RED |
| provider-card.test.tsx: an unnamed salon reads « Salon », « S » | Use provider.name raw | RED |
| provider-card.test.tsx: each layout has its own default sizes | No row default | RED |
| provider-card.test.tsx: no svg[data-weave] | Put a data-weave svg in the media box | RED |
| provider-card.test.tsx: data-initial matches the letter | Drop data-initial | RED |
| provider-card.test.tsx: alt is the name | alt="" | RED |
| provider-card.test.tsx: alt is « Logo {name} » | alt={name} on the logo | RED |
| heart-announced.test.tsx: a stopped salon has no « Annuler » | `announceFavorite` for a stopped salon | RED |
| optimizer-sources.test.ts: scans a real tree | Point it at no directory | RED |
| optimizer-sources.test.ts: AvisClient carries unoptimized | `unoptimized={false}`: a word, not the behaviour | GREEN |
| pro-avis render (pro-avis-summary.test.tsx) | `unoptimized={false}` | RED |
| production_alarm_test.dart: clear.needs | Leave clear.needs alone | RED |
| production_alarm_test.dart: report.needs | Leave report.needs alone | RED |
| production_alarm_test.dart: no check counts as passed without passing | continue-on-error on the job | RED |
| production_alarm_test.dart: no check counts as passed without passing | An `if` on the job | RED |
| production_alarm_test.dart: the same, on a step | continue-on-error on the step | RED |
| production_alarm_test.dart: the report's status line | Drop « card photo » from the status line (the spec claims no guard for it) | GREEN |
| e2e the card: border-radius 0 on the `<img>` | rounded-sm | RED |
| e2e the card: the media box is 1.33 ± 0.02 | aspect-video | RED |
| e2e the card: filter none | a brightness-90 | RED |
| e2e the card: elementFromPoint at the centre is the `<img>` | An overlay div | RED |
| e2e the card: no ::before or ::after on the link | A pseudo-element scrim on the link | RED |
| e2e the card: no ::before or ::after on the media box | A pseudo-element scrim on the media box | RED |
| e2e a failed photo: the corner is one colour | Remove `after:` from the photo | RED |
| e2e a failed photo: the letter, in dark pixels | Remove after:content-initial | RED |
| e2e a slow photo: the letter is visible | Drop the letter | RED |
| e2e a slow photo: the loaded `<img>` is on top | Put it after the `<img>` | RED |
| e2e heart and text: no text meets the heart | Remove the spacer | RED |
| e2e heart and text: no text meets the heart | Drop its h-12 | RED |
| e2e heart and text: scrollWidth equals the viewport | Remove min-w-0 from « Trier » | RED |
| e2e heart and text, 200%: non-vacuity first | Drop the emulation (the 200% style tag) | RED |
| e2e heart and text, 200%: non-vacuity first | Drop the emulation (isMobile) | RED |
| e2e no priority: no fetchpriority=high, no card photo preloaded | Put `priority` on the card's photo | RED |
| e2e the selected row: the offset in surface | Remove ring-offset-2 | RED |
| e2e the selected row: border-radius 0 | Put rounded-xl back on the row | RED |
| e2e favourites: a third of the row at 390, the full tile at 820 | layout="tile" | RED |
| e2e favourites: a stopped salon has no `<a>` | `linked` always true | RED |
| e2e favourites: no « Annuler » for a stopped salon | `announceFavorite` for a stopped salon | RED |
| focus.spec.ts: Tab goes link, then heart | tabindex="-1" on the heart | RED |
| focus.spec.ts: the name underlines on focus | Remove group-focus-visible:underline | RED |
| site-look SEO: root, city, area | Change a word in an `<h2>` | RED |
| site-look SEO: JSON-LD types | ItemList gone | RED |
| Test server: _cdn-stub-dns.cjs, ≥ 400 within 1 s | Swap the preload for one whose lookup never answers | RED |
| Test server: _cdn-stub-dns.cjs | No preload at all (on this Mac, a real lookup) | GREEN |
| site-look left edge: landings | Change a container's padding | RED |
| site-look left edge: the empty landing | `align="start"` removed from its EmptyState | RED |
| site-look pattern: root, city, signed-in account | Put a data-weave svg in a card | RED |
| site-look no boxes | Put rounded-xl border back on the card | RED |
| type-overflow: the four new routes | Fix a width on the card's text | RED |
| tap-targets: the row's heart | Heart at h-8 w-8 (it has no min-h-12 to remove) | RED |
| tap-targets: crumbs | Remove min-h-12 | RED |
| tap-targets: the city index | Remove min-h-12 | GREEN |
| tap-targets: landing chips | Remove min-h-12 | RED |
| tap-targets: « Retirer » signed in | Remove min-h-12 | RED |
| axe: /recherche?q=vitrine and the signed-in favourites | Give a card's image an empty link | RED |
| e2e neither a photo nor a logo: a logo has no letter under it | Put a letter beside the logo | RED |
| e2e neither a photo nor a logo: the letter | Drop the initial form | RED |
| e2e heart and text: scrollWidth equals the viewport | Remove max-w-full from « Trier »'s label | RED |
| site-look left edge: landings | The same from `lg`: the first one lost to `lg:px-l` | RED |
| site-look left edge: the first section's `<h2>` | Change SiteSection's padding, so the `<h1>` holds and the `<h2>` does not | RED |
| type-overflow: /recherche?q=vitrine | Fix a width on the row's text: the first one lost to `flex-1` | RED |
| tap-targets: the city index | Why C05c stayed green: min-h-12 removed, and the spec asks for 999 so it prints the height | RED |
| tap-targets: the city index | Can it fire on this link at all: h-8 instead of min-h-12 | RED |
| tool/check-card-photo.spec.ts | A local build with a failing image | RED |
| tool/check-card-photo.spec.ts | `/recherche?q=vide`: a printed skip | SKIP |
| tool/check-card-photo.spec.ts | Not one of the page's two states: a page with neither | RED |
| tool/check-card-photo.spec.ts | Not a 200: a path that 404s | RED |
| tool/check-card-photo.spec.ts | A local server stopped | RED |
| tool/check-card-photo.spec.ts | A list with no card photo: the stub's list cut to a logo and a letter | SKIP |
| tool/check-card-photo.spec.ts | Real bytes, and the card is aspect-video | RED |
| tool/check-card-photo.spec.ts | The photo is `unoptimized`, so it does not go through the optimizer | RED |
| postgres_repositories_test.dart: query() carries imageUrls | Project imageUrls out of query()'s SELECT | RED |
| postgres_repositories_test.dart: query() carries logoUrl | Project logoUrl out of query()'s SELECT | RED |
| postgres_repositories_test.dart: byIds() carries imageUrls | Project imageUrls out of byIds()'s SELECT | RED |
| postgres_repositories_test.dart: byIds() carries logoUrl | Project logoUrl out of byIds()'s SELECT | RED |
| postgres_repositories_test.dart: control: the same SELECT form | Project out a key nobody reads, in query() | GREEN |
| postgres_repositories_test.dart: control: the same SELECT form | Project out a key nobody reads, in byIds() | GREEN |
| provider-card.test.tsx: no fetchpriority=high | Stay lazy and add fetchPriority="high": U07 stops at `loading`, before this line | RED |
| tokens.theme-pin: emits .aspect-card | The card no longer spells it: `aspect-video` | RED |
| tokens.theme-pin: emits after:content-initial | The card no longer spells it | RED |
| e2e no priority: no card photo in a preload | `priority` on the photo, and the spec's fetchpriority line removed, so the preload line is what is left | RED |
| e2e favourites: the full tile at 820 | layout="row": a row at every width | RED |
| e2e favourites: a live salon keeps its link | `linked={false}` for every favourite | RED |
| focus.spec.ts: the link computes RING | No outline on the link | RED |
| focus.spec.ts: the heart computes RING | No outline on the heart | RED |
| site-look SEO: `<h1>` | Change a word | RED |
| site-look SEO: title | Change a word | RED |
| site-look SEO: canonical | Change the URL | RED |

**Second pass**

| Guard | Mutation | Result |
|---|---|---|
| optimizer-sources: AvisClient carries unoptimized | X10 again: unoptimized={false} | RED |
| optimizer-sources: AvisClient carries unoptimized | unoptimized={keep}: a variable proves nothing | RED |
| optimizer-sources: AvisClient carries unoptimized | Control: unoptimized={true} | GREEN |
| cdn-stub-preload: ci.yml | Delete NODE_OPTIONS from the Lighthouse step | RED |
| cdn-stub-preload: ci.yml | Comment it out, so only a comment names it | RED |
| cdn-stub-preload: ci.yml | Move it off the lhci step, onto the step before | RED |
| cdn-stub-preload: ci.yml | A wrong path in the flag | RED |
| cdn-stub-preload: ci.yml | Control: one more env row on that step | GREEN |
| cdn-stub-preload: playwright.config | Delete it from the Next server | RED |
| cdn-stub-preload: playwright.config | Comment it out | RED |
| cdn-stub-preload: playwright.config | On the stub instead of the Next server | RED |
| cdn-stub-preload: the preload | E22b, in this guard: the preload lets cdn.stub through to the lookup that hangs | RED |
| cdn-stub-preload: the preload | It refuses every host | RED |
| cdn-stub-preload: the preload | It loses the real lookup’s symbols | RED |
| cdn-stub-preload: the preload | It is never installed | RED |
| production-alarm-status | A06 again: « card photo » out of the status line | RED |
| production-alarm-status | The env row gone, the line kept | RED |
| production-alarm-status | The env row commented out | RED |
| production-alarm-status | The row reads another job | RED |
| production-alarm-status | A ninth check arrives with no row, so the derived list has to see it | RED |
| production-alarm-status | The jobs block cannot be found | RED |
| production-alarm-status | Control: a word changed in the prose | GREEN |
| tool/check-card-photo.spec.ts | The check as it was at 23eecdbd, on a stand-in out of transformations: q=75 answers 200, anything new 402. The review’s finding | GREEN |
| tool/check-card-photo.spec.ts | The check now, on the same stand-in | RED |
| tool/check-card-photo.spec.ts | Mutation: the check asks for q=75 again, on the same stand-in | GREEN |
| tool/check-card-photo.spec.ts | Control: the check now, on a stand-in with no ceiling | GREEN |
| tool/check-card-photo.spec.ts | The check as it was at 23eecdbd, on a photo that never answers: the poll’s message cannot print | RED |
| tool/check-card-photo.spec.ts | The check now, on the same photo: the poll’s message prints | RED |
| tool/check-card-photo.spec.ts | A local build with a failing image, with the image cache still holding the file from the row above, so it read green. The next row empties it | GREEN |
| tool/check-card-photo.spec.ts | /recherche?q=vide: a printed skip | SKIP |
| tool/check-card-photo.spec.ts | Not one of the page’s two states | RED |
| tool/check-card-photo.spec.ts | Not a 200 | RED |
| tool/check-card-photo.spec.ts | A local server stopped | RED |
| tool/check-card-photo.spec.ts | A local build with a failing image, its image cache emptied first. CP18 read green because the 31-day cache still held the file from CP16 | RED |
| site-look: a ruled index answers the pointer, /coiffure | The review’s defect: the colour back on the name | RED |
| site-look: a ruled index answers the pointer, / | The home page’s hover removed | RED |
| tap-targets: the city index | The link really small: h-8. min-h-12 is gone, so this is the only way it can fall below the floor | RED |
| site-look: a commune too long, at 200% text | The review’s gap: break-words off the commune | RED |
| site-look: a commune too long, at 200% text | Non-vacuity: the doubling dropped, in this test only | RED |

### What these cannot see

- **Whether it looks right,** and a real photo: a fixture is a pixel. So pictures, looked at (§9).
- **The real optimizer on Vercel,** until a salon is public.
- **Safari,** until the simulator.
- **For every route list here:** a new caller of `ProviderCard` is not in any of them. The unit tests hold the card itself.

---

## 9. Rollout

**Two PRs.** The web slice, and the backend test on its own. **Both merges wait for Apple's decision on build 719 (B0.1) and the owner's word.**

| A merge of | Starts |
|---|---|
| **The web PR** | A Vercel production deploy (B0.1: a merge can deploy production even with no `web/` file). The five pages' HTML changes in hashes (§13). The new job runs from the next 06:00 UTC |
| **The backend-test PR** | `deploy-backend.yml`, on any `backend/**` path (`:97-105`). With `staging.state` at `absent` it builds and pushes an image and runs the pin and emitter checks against production, and it skips only the staging deploy. **No backend deploy.** It does make a new tag beside the one the post-Apple production deploy will promote (BACKLOG lines 29, 45), so that promotion names its tag on purpose |

**Before the merge**
1. Before and after pictures from the local build, at direction §12's 360, 768, 1440 and 1920 and at this spec's 320, 390, 820 and 1280. Looked at. **Photos:** `mobile/assets/images/providers/{salon_excellence,barber_shop_pro,spa_relax}_photo.png`, never `beaute_divine_photo.png`, which is a phone screenshot, and `docs/design/assets/demo-salon/maison-nala-logo.png`, served by `page.route` in the picture tool. Each sheet carries « photos de démonstration, jamais publiées ». None shows a person: if the owner gives a portrait (decision 2), it is shot once, never committed. **After the review's fixes, shot again on the final tree:** the doubled `/recherche` at 320 and 390, and `/coiffure` at 320, 390 and 1280, read the same pixels as before, so no sheet changed. The one row the commune's `break-words` changes has its own read and was looked at (§2.4).
2. §7's measurement, with and without `imagePriority`. Done, both methods, and decision 6 chose.
3. §13's comparison of the five pages.
4. Every mutation in §8.
5. WebKit: the failed photo with its letter, the slow photo, and the row, in the iOS simulator against the local build. **Done 2026-11-05, Safari on an iOS 26.5 simulator, real bytes through the local optimizer.** The row, a photo, the letter, a logo and a landing's tile read as in Chromium. The slow photo holds the letter and paints with no shift. The failed photo shows a small blue « ? » and a thin outline as well as its letter (§2.4), which goes to the owner. Not read there: doubled text, forced colours, keyboard focus. The pictures hold demo photos, so none is committed.

**After the merge, on `myweli.com`** (GET only, signed out)

| Readable now | Not readable now |
|---|---|
| `/recherche` and the three landing levels: left edge, flush-left empty state, ruled index, open FAQ, no box, no pattern, no sideways scroll, at six sizes | **Any card.** `GET /providers` reads `total: 0`, the demo salon is a permanent draft, staging is `absent`, and a preview has nothing behind it |
| `<h1>`, canonical and JSON-LD on those pages against the list | **Any photo through Vercel's optimizer,** and the 31-day TTL in effect |
| `/` unchanged: its section stays hidden | **The favourites list** (no sign-in on a live host) |
| The five pages: words and links | **LCP with a photo** on any page |
| CSP console, all ten privacy checks, `gh run list --workflow=production-checks.yml --limit 3` | |

**So direction §13's « Cards with and without photos looked at » is met locally, and not on production.** It stays open under B11.3 until a salon is public.

**The mechanism for that day, since a sentence in a doc would be forgotten.** `web/tool/check-card-photo.spec.ts`, run by `npm run check:card-photo` (`playwright test … --config=tool/privacy.config.ts`, as `check:privacy` and `check:legal` are), GET only, no cookies, against `PRIVACY_URL`. **It reads the page, not the API:** those jobs already reach `myweli.com` from a runner, while no scheduled check reaches `api.myweli.com` through the Worker (UNVERIFIED that a runner can). Phone viewport, 390×844.

| What it finds on `/recherche` | Outcome |
|---|---|
| Not a 200, or neither « Aucun salon trouvé » nor a count `<h2>` (an error page, a refused API) | **Red.** The file's own rule: « a check that measured nothing is not green » (`production-checks.yml:271`) |
| « Aucun salon trouvé », or a list with no card photo | **A printed skip:** « no public salon with a photo: nothing read ». Green, claiming nothing |
| A list with a card photo | The first one: its `/_next/image` answers 200, `naturalWidth` above 0, media ratio 1.33 ± 0.02. **And one transformation nobody has read answers 200:** the same file, with `q` set from the date to 1–60, so it comes back after 60 days, past the cache's 31, and is never the page's 75. Anything else is **red**. That last read is how a plan out of transformations shows: the first photo's own file is cached after its first read and should keep answering, while new photos fail as a letter on a tile (§14). Its cost is one transformation a day |

**The workflow change, whole.** A job `cardphoto`, the same shape as `privacy`, with `PRIVACY_URL: ${{ github.event.inputs.target || 'https://myweli.com' }}`, so a dispatch with a custom target reads that target as the others do. It has no `if` and no `continue-on-error`, and it declares `permissions: contents: read`, so it holds none of the workflow's `issues` or `id-token` rights (corrected 2026-11-05: it inherited them; `cwv`, `privacy` and `legal` still do, for their own change). Added to `report.needs` and `clear.needs` (`:328`, `:428`). `report` gains the env row `CARDPHOTO: ${{ needs.cardphoto.result }}`, « · card photo: ${CARDPHOTO} » in its status line, and « Five of these run against myweli.com » with card photo named beside CWV, privacy, legal and retention (`:368-370`). The report's sentence on this job names its four reds: `/recherche` answering neither a list nor an empty list, the photo not loading through the optimizer, a card no longer 4:3, and a new transformation refused. `clear`'s comment gains: « The card photo check reads nothing until a public salon has a photo; the run's log says which. » `docs/design/production-alarm-close.md` goes from seven checks to eight. `backend/test/infra/production_alarm_test.dart:46-53,76-92` derives the checks from this file, so it needs no edit, and it fails if either `needs` is missed; CI has no path filter, so it runs on the web PR. That test is the mutation: leave `clear.needs` alone and see it red.

It wakes with the first public salon, and on that same day `check:cwv` starts measuring `/` with real photos, by itself. The first time it runs for real, B11.3's last line gets read and closed by hand: the cards looked at on the live site, with the first real portrait and the letter's flash among them.

**Yours (the owner's), none of it blocking the build**
- Read the Vercel plan under Settings → Billing. If it is Hobby, §7's ceiling applies, and Vercel limits Hobby to non-commercial use. Asked on 2026-11-05, no answer yet.
- One or two real portraits you hold the rights to, if you have them (§11, decision 2). Asked on 2026-11-05, no answer yet.
- Look at the final pictures.
- Merge on your word, after Apple.

**Rollback.** Revert the PR. No data, no API, no flag.

---

## 10. Definition of done

- [ ] Typecheck, lint, `vitest`, `next build`, Playwright, axe, Lighthouse green. No budget raised. Backend test green in its own PR.
- [ ] Every new guard and every changed guard watched red on committed work, recorded in the commit.
- [ ] Tokens only, no arbitrary values, no new undeclared `ds-ignore`.
- [ ] Four states on each page. §2.4 walked against the build, line by line.
- [ ] Parity: cover photo in. §2.5's gaps filed, or answered in §11.
- [ ] App-install push unchanged.
- [ ] `<h1>`, canonical, JSON-LD unchanged on a landing, against the list from `main`.
- [ ] §13's comparison of the five pages attached to the PR.
- [ ] Pictures looked at and sent to the owner, none committed or uploaded (decision 37), and the PR says which were looked at. Deployed site read back. What could not be read is listed as such (§9).
- [ ] `web-swiss-direction.md`: its status and its §6.4, §7.3–§7.5, §8, §9, §10 and §11, corrected per §14 here, with the date. WEB-SYSTEM §16: `aspect-card`, `content-initial`, the card, favourites as the one exception to « font, header and footer only ». `account-deletion-erasure.md` §11. `production-alarm-close.md`. README index, BACKLOG per §15, one roadmap entry.
- [ ] This spec cross-linked from `ProviderCard.tsx`.
- [ ] Feature branches and PRs, CI green, no Claude attribution. Merges left to the owner.

**Where this stands, 2026-11-05, before any push.** Met locally, and read in this spec: typecheck, lint, `vitest`, `next build`, Playwright, axe and Lighthouse on the final tree, the backend test on a fresh Postgres 16, every guard watched red (§8), §13's comparison, the pictures looked at, and WebKit in the simulator. **Still open, so the boxes stay empty:** both PRs and their CI, the pictures reaching the owner, the deployed read-back (§9), and the owner's calls: §7's method, §13's condition 2, and what the pictures left to him (§2.4, §7, §11).

---

## 11. Decisions for the owner

**Answered on 2026-11-05: 1 (a), 2 (a), 3 (a), 4 (a), and after the pictures 5, 6 and 7, with 3 confirmed on the corrected figures.** The owner answered 2, 3 and 4 directly, and on 1 said « do what is best in the long term », so (a) is this spec's call, with the reason below. Under each option is what would have changed.

**1. Cards need a long image cache, and review photos share it. `/suppression-compte` says those photos are deleted.** (§6, §7)
- (a) **Keep 31 days, and show review photos on `/pro/avis` without the optimizer, recommended.** One attribute, a source pin, one line in `account-deletion-erasure.md` §11.
- (b) Keep 31 days everywhere and write the residual down. No attribute and no pin. `account-deletion-erasure.md` §11 and `docs/BACKEND.md` §7 state that a copy can outlive erasure by 31 days. The page's sentence goes to B11.5, after Apple.
- (c) One day for everything: `minimumCacheTTL: 86400`, no attribute. A day's residual, written down in the same two places. Cost about 30 times (a)'s (arithmetic).

*Why (a):* it keeps a sentence on a store-linked page true without touching the page, and `ProDepositProof.tsx:110-113` set this precedent. *Cost:* full files, up to 5 MB, for 96px thumbnails on one pro page.

*Why (a) is also the long-term answer:* the promise holds by construction, and a pin keeps it held. (b) writes a weaker promise into a page both stores link to, and it stays weaker for good. (c) pays about 30 times more for as long as the site runs, and still leaves a residual. (a)'s cost is the only one that can later be removed without touching the promise: the salon page already shows these same files at 64px (`ReviewList.tsx:62`), so a small copy made at upload, under the same `review/{userId}/` prefix that erasure deletes, would serve both pages. Nothing needs that today, with no reviews in production, and §15 files it.

**2. Where the pictures show the card struggling: names at large text, logos of odd shapes, portrait photos.** (Sheets 11, 14)
- (a) **Names wrap at every width, the row stays at every width, the logo stays in the corner, the crop stays centred, recommended.** Reverses direction §8's « Declared `truncate` on card names stays ».
- (b) As approved: names truncate with `clip-ok`, `h3` a flex row, `span.truncate`. Then a short name loses its end at doubled text: « Beauté … » at 320, « Chez Koffi Bar… » at 390. `truncationLosses` must not read the long-name fixture, and `type-overflow` does not gain Marcory or `/recherche?q=vitrine`.
- (c) Stack below `sm`. Root `group block sm:flex sm:items-start sm:gap-m`, media `sm:w-1/3 sm:shrink-0`, body `mt-sm sm:mt-0 sm:min-w-0 sm:flex-1`, `CARD_SIZES.row` `(min-width: 1024px) 18vw, (min-width: 640px) 32vw, 92vw`. A card is 324 high instead of 116, so lists are about three times longer. All three competitors do this.
- (d) Any of these with the logo centred: `absolute inset-0 m-auto h-2/3 w-2/3`, `object-center`.
- **And one thing only you can give:** if you hold the rights to one or two real portraits of a client's hair, tell me their folder in plain text and I shoot them, mock only, never committed. If heads are cut, the choice is `object-top`, one class on the photo. Without them, the centre crop is signed unseen and gets looked at with the first real salon.

*Why (a):* the name is the one thing on the card with no other copy, the reader who enlarged the text is the one who loses it, and wrapping moves only long names at normal text (F6 in a 288 row: 164 high against 116). The corner follows your flush-left rule and lines up with the name, and centred is calmer and holds better for wide, tall and white-box logos: it is close, and yours to judge. The centre crop matches the app, and `object-top` costs a room its chairs. *Cost:* uneven row heights with long names.

**3. Favourites: a stopped salon, and the list's length on a phone.** (Sheets 12, 07)
- (a) **Both, recommended.** A stopped salon is not a link and removing it offers no « Annuler ». Below `sm` favourites are rows, from `sm` the tile.
- (b) The stopped salon only. Tiles at every width, `layout` stays `tile`, `account` ends in `calc(100vw - 32px)`. Four favourites: a 1826-tall section, « Aide & Support » at y=2619.
- (c) Rows only. The link and « Annuler » stay. The stopped salon is filed in B12.7.
- (d) Neither. Both filed in B12.7.

*Why (a):* the web already withholds these links for bookings for this same reason (`lib/account/appointments.ts:87-91`, `account.spec.ts:356-365`), a photo makes a dead link more inviting, and `FavoritesService.add` refuses a hidden salon, so « Annuler » can only fail. The stub answers every write 204, so e2e cannot see that. Rows keep support and account deletion close to where they are today: section 704 tall against 640 today and 1826 as tiles, so 64px lower instead of 1186px lower. **Corrected after the answer, 2026-11-05:** this read 744 today, which made rows look shorter than today (§14), and the owner was told. **Confirmed on the corrected figures, 2026-11-05: decision 3 stands.** At 390, section 640 today, 704 as rows and 1826 as tiles: rows move support and account deletion 64px down, and tiles would move them 1186px. It needs your word because direction §1 limits flow and layout changes there, and because the app differs: its card stays tappable and opens a sentence. The sentence stays on the card's last line: moving it under the name would be a new slot on the card, not done.

**4. What the app has that the card lacks.** BACKLOG B12.7 says C5–C10 get done « when touched », and this slice touches the landings (C6) and the favourites' file (C7, C10). (Sheet 16)
- (a) **Add the review count, « ★ 4,8 (32 avis) », and defer C5–C10 by name, recommended.**
- (b) Defer everything. `SalonRating` without `withCount`, and the count filed in B12.7.
- (c) (a), plus hearts on landing tiles: a client island and the `/api/me/favorites` probe on public, indexed pages. Bundle cost unmeasured. The tile already takes a heart.
- (d) (a), plus sort, filter and map on landings, or send those searches to `/recherche`. Changes a flow or route, and the second undoes the SEO funnel in `web-m8-1-discovery.md` §3.

*Why (a):* 4,8 from 3 reviews and 4,8 from 300 read differently when choosing a salon, the app shows it, and no audit lists the gap. It is one prop here, and otherwise its own PR and read-back later. It fits at 320 and on a tile (measured), and at doubled text the line wraps and stays in its column. Deferring C5–C10 keeps S3's safety, « no link or JSON-LD changed ». *Cost:* until C6 lands, a client who arrives on a landing has fewer tools than the app gives, and the audit recorded that this was never weighed (`web-flow-audit-2026-11.md`, C6). With 0 public salons nobody loses anything today.

**5. « Carte » on phones.** *Asked after the pictures, because the plan had it wrong.* **Answered 2026-11-05: move it left.** §1 said « toggle unchanged », §2.4 « as it does today », and the line naming it to the owner « as today ». All three were wrong in the same way. The button had not moved, but the row under it is new, and a row's text starts nearer the centre than a card's did. At 360×640, `main` hid only the ✔︎ after « Beauté Divine », and the branch hid most of the name. At 390×844, `main` hid the end of the second card's price, and the branch hid the commune and most of the price. The owner saw that before and after, and the button centred and at the left, and chose left. So `left-m`, no translate and no arbitrary value, which overrides §1's « toggle unchanged » for this one class. The toast stays where it is: centred, at 80px, above the button's 24–72px band, and reading it shows no collision. *Cost:* it covers the start of « Disponible aujourd’hui » on the first screen at 320×568, as the centred button covered its middle, and at doubled text at 320 it reaches a row's text by 12px (§2.4).

**6. The first photo on a list.** *§7 had left this to the owner, with both tables.* **Answered 2026-11-05: load it first.** The rule reads applied throttling (`lighthouse --throttling-method=devtools`) from now on, not the simulated estimate, because the estimate does not model the request starting earlier. The prop is on the first card of root, city, area and `/recherche`, and on no card of `/` or the favourites. The same bytes either way. At 412×823 under that throttling the LCP falls by 981, 1301, 1087 and 1510 ms. `lighthouserc.json` does not change and no budget moves. *Cost, recorded in §7:* at 360×640 root, city and `/recherche` fetch it off-screen, reading +19, +16 and +44 ms. CLS under this throttling reads 0.167 on the city level at 412, in 5 of 5 with the prop and 2 of 5 without, where `main` reads 0.176 in 4 of 5.

**7. §13's condition 2.** *§13 stopped the merge until the owner had read it.* **Answered 2026-11-05: accepted for this merge, and from now on the condition reads « decoded payload »:** the payload compared after decoding and normalising. A real change still fails it, and a moved `<script>` boundary does not. The stop on it is lifted because the owner has read it. The measured record stays as the record: 7 B per page, the boundary moved.

**Decided here, and recorded in §14 so they can be overruled from the pictures:** the heart's position, the favourites' 203px, the rule under the media, the letter under a photo, a row photo a third of the width at 1920.

**Named to the owner on 2026-11-05 as left alone unless they say otherwise, and not changed by them:** the logo in the corner rather than centred (sheet 14); a row photo a third of the width, so two and a bit salons fit beside the map at 1280×900 against four and a half today (sheet 2). **A third thing was named with them, and it was wrong:** « the fixed « Carte » button over card text on phones, as today ». Decision 5 is what happened to it.

---

## 12. SEO, AEO, GEO

- **Same `<h1>` words, canonical, metadata, JSON-LD (`BreadcrumbList`, `ItemList`, `FAQPage`), sitemap and `llms.txt`.** No field added to `ItemList`, even though photos exist now: direction §1 bars any JSON-LD change, and this is noted for B11.5.
- **Same heading order on landings,** with larger `<h1>` and `<h2>` from direction §5.3. Every link stays in the served HTML, and none goes into `display: none`.
- **The FAQ's answers become visible.** The words are the same as `FAQPage`'s, which is stronger for answer engines than text behind a disclosure.
- **Alt text on a photo is the salon's name:** real text for image search, as direction §10 asks. Inside the link the name is said twice by a screen reader (inferred). Axe's redundant-alt rule compares the whole link's text, so it should not fire. **Answered 2026-11-05: it does not fire,** in `axe.spec` on `/recherche?q=vitrine` and the signed-in favourites, so the alt stays the name. The doubling is a known cost, and direction §10's reason stands. The letter is `aria-hidden`.
- **`/recherche` and `/mon-compte` stay noindex.** Landings stay indexable, and their empty state keeps « Explorez les liens ci-dessous », which stays true.
- **A lazy `<img>` is still in the HTML with its `srcset`,** as the first card's is with its preload. Nothing about discovery depends on it.

---

## 13. What could reach the five store-linked pages

`/support`, `/politique-confidentialite`, `/cgu`, `/mentions-legales`, `/suppression-compte` must not change in words or links during review.

**Walked from source:** the import closure of the layout, `not-found`, `error`, `global-error` and the five pages holds 56 files, an over-count that includes type-only imports. Nothing this slice edits is in it. An independent walk gave the same.

**Compared, on real builds:** `main` at `ea0c8f0c` against the prototype with its mock route removed, same stub, the five pages each at 390 and 1280. One later change, a no-break space in `ProviderCard`, is outside their graph and was not re-compared.

| What | Result (measured) |
|---|---|
| Visible words, `<a href>` list, `class` attributes | The same on all five. HTML the same byte length |
| Pixels, full page | Identical, 10 of 10 |
| Computed style of every element, property by property, custom properties included | No difference, 10 of 10. **Compare by property name:** Chromium enumerates `--tw-*` in a different order on each load, so a whole-string hash differs even between two loads of the same build |
| Stylesheet | One file, 31,974 to 33,832 B. Rules 553 to 583: none removed, all old rules in their old order, 30 added, none of which changes a computed style here. So its hash changes |
| Scripts | Still 12 per page. **One shared chunk is replaced** (`3153-…` by `1666-…`), and six others change hash. About +320 B gzipped per page |
| What is inside those scripts | 202 of the 205 module ids are the same. The other three sit in the layout, error and global-error chunks and are their entry modules (inferred from where they sit). Four modules moved from the shared chunks into the layout chunk. **The same code, partitioned differently** |
| Why | `next/image` is now imported from more routes, so webpack draws its shared chunks differently (inferred) |
| `next.config.mjs` | `2678400` appears in no file under `.next/static`, only in `images-manifest.json` and `required-server-files.json` (measured) |
| `/suppression-compte`'s truth | Not a build difference. §6, decision 1 |

**By design:** `aspect-card` and `content-initial` are not in `tokens.ts`, and `Faq` and `SiteFaqList` are unused by the five. `/suppression-compte` avoids `Faq` on purpose (`page.tsx:26`).

**The guard before the merge, repeating this on the real branch.** Build `main` and the branch against the same stub. All of these must hold, and anything else stops the merge and gets explained:
1. Words, link list and `class` attributes identical, in order, from the prerendered HTML.
2. **The decoded payload** identical after normalising, and everything outside the payload identical after normalising: `/_next/static/**` paths to their kind, `buildId`, and in the RSC payload the module ids and chunk-id arrays of `I[…]` rows. The payload is compared after decoding it from its `self.__next_f.push` scripts, not as raw HTML. A real change still fails this, and a moved `<script>` boundary does not. **Amended 2026-11-05, decision 7:** this read « HTML identical after normalising », and a chunk's longer name broke that with nothing changed, because Next cuts the inline payload by length. The owner read that, accepted it for this merge, and from now on the condition reads « decoded payload ».
3. Every old CSS rule still present, in order. Added rules allowed.
4. Same number of scripts per page, and the gzipped sum up by no more than 1 KB. The Lighthouse gate holds the budget.
5. Computed styles by property name, and pixels of the full page, at 390 and 1280, identical. The before-and-after pictures go in the PR.

Plus `store-linked-pages.test.tsx` and its e2e. After the merge, words and links read on `myweli.com`, as after #730.

**On the real branch, 2026-11-05 (`571038b2` against `ea0c8f0c`): conditions 1, 3, 4 and 5 hold, and condition 2, as it was then written, does not.** After its three normalisations, all five pages still differ, at one place each: a few characters on one side of a `self.__next_f.push` boundary, because a chunk renamed from `785` to `5878` makes the `I[…]` rows 6 characters longer in the decoded payload and each page 7 B longer in its HTML, and Next cuts the inline payload into `<script>`s by length (the cut is inferred from where it moved; Next's source was not read). Decoding each page's payload and normalising it gives identical text, and everything outside the payload is identical. **That stopped the merge until the owner had read it. They read it on 2026-11-05 and accepted it, so the stop is lifted, and the condition as it now reads holds (decision 7). This paragraph and the next stay as the measured record: 7 B per page, the boundary moved.**

**Re-run on the final web tree, 2026-11-05 (`f7d1691e` against `ea0c8f0c`), because the review's fixes touched `TaxonomyLandingView` and `ProviderCard`: the same result.** Condition 1: words, links and `class` attributes identical, in order, on all five. Condition 2, as then written: did not hold, for the same cause, with the same 7 B of HTML per page and 6 characters of decoded payload: 5 inline payload scripts on each side, the decoded payload identical after normalising, and everything outside it identical. As it now reads, it holds. Condition 3: the same stylesheet as the earlier read (`f5a802c7a217fd7f.css`), 553 to 581 rules, 0 removed, 0 out of order, 28 added. Condition 4: 12 scripts per page on both sides, the gzipped sum up by 299 to 302 B. Condition 5: 10 of 10, 0 computed-style differences over 1,737,926 property reads, identical PNG bytes; the controls read 135 differences on two different pages and 0 on one page loaded twice. `store-linked-pages.test.tsx` and its 34 e2e tests pass in the same tree's full suites.

**The web tree changed after that read, on the owner's answers and the last review:** « Carte », `imagePriority`, and comments and guards. Nothing edited is in the five pages' graph, read from source. **The stylesheet did not change:** a build of this branch still writes `f5a802c7a217fd7f.css` at 33748 B, the file condition 3 read above (measured). `left-1/2` and `-translate-x-1/2` keep their rules because `Toast.tsx:32` still uses them, and `left-m` already had one because `Hero.tsx:29` uses it. The comparison on the final tree is owed by the next stage's gate.

---

## 14. Where the approved spec was wrong or silent

Every § in this table is the parent's, unless it says otherwise.

| Parent says | What holds | Done here |
|---|---|---|
| §7.3 « `next/image`, lazy »; §11 « lazy and below the fold » | « Lazy » holds for every photo but one per level. « Below the fold » is true only for `/`, at phone and desktop sizes: a card photo is the LCP on landings and `/recherche` at 412×823, and on `/` at 820×1180. At 360×640 root, city and `/recherche` have it off-screen | `imagePriority` on one card, per level, was built and measured under §7's rule. On the simulated method no level met it, and `571038b2` took it out. Under applied throttling all four did, and the owner chose that reading (decision 6), so the prop is back on the first card of each level |
| §7.3 « The rating … stay as they are » | Same component, but it leaves the name's row, and gains the count under decision 4 | Own line, the app's order |
| §7.3 « a rule and a hover state » | Does not say where, and the old hover would hide a no-photo tile | Rule at the foot of the media, row rules in the list, name underlined |
| §7.3 does not place the heart | Bottom-right on the web, on the photo in the app | Stays bottom-right, off the photo, with a spacer as tall as the heart |
| §7.3 gives `row` no breakpoint | All three competitors stack on phones. The app's list keeps a thumbnail on the left | A row at every width, as §7.3 says. Decision 2 (c) is the other answer |
| §7.3 « two layouts » | Favourites as tiles push support and account deletion down 1186px on a phone, and rows 64px (corrected 2026-11-05: this read 1082) | A third value, `rowOnPhone`, the same two layouts switching at `sm`. Decision 3 |
| §7.3 « real `sizes` » | One layout, three grids. And a wrong `vw` silently drops candidates | Additive `imageSizes`, `CARD_SIZES` |
| §7.3 « every existing prop unchanged » | Holds. `linked` is new, for a stopped favourite | Additive. Decision 3 |
| §6.4 « two named tokens » | `cover` has no user until S4 | `card` now, `cover` in S4 |
| §6.4 « the app's card is close to 4:3 » | Only its two-column phone grid (1.24–1.36). Carousel 1.56, one column 1.82, list 1:1 | Wording corrected. The 4:3 decision stands |
| §1 « a 180-high cover » | Grid only. The app's list uses an 80×80 thumbnail | Wording corrected |
| §6.4 is silent on a logo's fit | Any ratio, often opaque | Contained, 2/3 of the tile, bottom-left, no padding. Decision 2 (d) is the other answer |
| §6.4 is silent on the crop's position | Centre cuts the top of a head in an upper third; top costs a room its chairs | Centre, as the app. Decision 2 |
| §1 « no layout change on `/mon-compte/*` » against §7.3 and §13 S3 | They contradict | The card applies, and columns, container and states do not. WEB-SYSTEM §16 records the exception |
| §1 rules out flow changes | A stopped favourite's link ends on a 404, and its « Annuler » can only fail | Not a link, no « Annuler ». Decision 3 |
| §6.1 « Flush left … empty states included » | Reads as including favourites | Public pages only. Favourites stays centred with the rest of the account |
| §5.3 `<h2>` row, public pages | `/recherche` is one, and its count `<h2>` stays `titleLarge` | Kept smaller: it is a list beside a map |
| §7.4 omits `/recherche`'s empty state and the selection ring | §6.1 and §6.3 cover them | In scope, with `ring-offset-2` and every row `py-m` |
| §7.4 « same filters » | Holds, and « Trier » scrolled the page sideways at 320 with doubled text | `max-w-full`, `min-w-0`. No change at normal text |
| §7.5 does not say hanging or stacked | §6.1's default is hanging, and it gives the home page's exact tile | Hanging |
| §7.5 « The FAQ follows §7.1 » | Landings use `Faq`, shared with the salon page, whose own container breaks the edge | New `SiteFaqList`; `Faq` waits for S4 |
| §7.5 omits the city links | §1 counts them among the boxes | Ruled index |
| §8 « Declared `truncate` on card names stays » | Today's `truncate` does not truncate, and at doubled text it cuts short names for the reader who enlarged them | Names wrap. Decision 2 |
| §8 « The `surfaceVariant` tile stays » | Chromium also draws a broken-image mark, and a pale tile says nothing while a photo is slow | The tile stays, with the salon's letter under the photo and in the failed image's `::after`. WebKit UNVERIFIED |
| §8 is silent on 48px | « Retirer » 20px, crumbs 20px | Both raised to the floor, no word changes |
| §9 « no backend change » | Confirmed in code only. No live read is possible, and no test pinned it | One backend test, test only, in its own PR, because `backend/**` starts `deploy-backend.yml` |
| §10 « as the hero's alt already does » | The hero says `Salon {name}`, so « Salon Salon Excellence » is possible | Bare name, §10's first clause. `Hero` is S4's |
| §11 budgets | Nothing measures landings or `/recherche`, and CI cannot serve a photo | Measured once by hand, gate moved to B11.4 |
| §11 is silent on transformations | With a short TTL most views would be billed, and a Hobby plan would fail with a 402 (arithmetic) | `minimumCacheTTL`, a new line in `next.config.mjs` |
| §11 is silent on the cache and erasure | Review photos go through the optimizer, and erasure deletes them | `unoptimized` on `AvisClient`. Decision 1 |
| §12 lists a before-and-after SEO guard for a landing | It exists for `/` and `/professionnels` only | Added here at all three levels. The salon page's is S4's |
| This spec's §8, `routeNextImages` « answers a pixel » | A loaded 1×1 file reads `naturalWidth` 0, as a failed photo does, because a `w` descriptor divides it by its density (measured: 1 ÷ 1.07, floored). And a box on a fractional x paints the page's colour in its first column (measured at 1280) | A 64×48 opaque PNG in one colour, so the failed photo's check means something and a loaded photo can be read covering its letter. The 30×30 corner is read from 2px in |
| This spec's §7 rule names the metric and not the method | `lighthouserc` names no method, so Lighthouse runs `simulate`, and the same file's numbers applied with `devtools` give the opposite answer on all four levels | The rule was applied to `simulate`, what the gate reads. The owner's answer: the rule reads applied throttling from now on (decision 6), and the gate stays on its method. Both tables stay in §7 |
| This spec's §7 « all four photos » on `/` | `/` reads eight salons, and a phone fetches seven or eight on load | Measured in §7. No change to the page |
| This spec's §9 and `tool/check-card-photo.spec.ts:17`, « Phone viewport, so no basemap loads » | Below `lg` the map is mounted and hidden, and it still loads the basemap, read at 412 and 360 (not at 390) | Recorded in §7. The clause is deleted from both places: it was false, and only the map's own cost is the owner's |
| This spec's §13 « the only differences on the prototype » | On the real branch the payload's `<script>` boundaries move too | Reported under §13. The owner read it and accepted it on 2026-11-05, and condition 2 now reads « decoded payload » (decision 7) |
| This spec's §2.3, `min-h-12` and `hover:text-textSecondary` on the ruled index | Both lines always render, with `py-s`, 65 tall at every width, so the class held nothing and §8's mutation of it stayed green. And both children set their own colour, so the hover changed nothing: `rgb(26, 26, 26)` before and after on `/coiffure`, read in a browser, where the home page's index moves to `rgb(74, 74, 74)` | `min-h-12` goes, and `tap-targets` still holds the 48px (`h-8` reads 32). The colour moves to the link, as on the home page, and an e2e holds both indexes |
| This spec's §2.2, « the commune and price beside it stay clear of it » | Not one word too wide for its column. « Yamoussoukro » at 200% text with no price runs 187 wide beside a 132 column, meets the heart at 320, 360 and 390, and at 320 passes the card's edge. It is in the taxonomy. No fixture had that combination | `break-words` on the commune, one stub read, one e2e. « 1 500 000 » at 195 wide stays as §2.4 records it |
| This spec's §2.3 and §11 decision 3, « where they are today », 744 today | Three real builds read 640 today, 704 as rows, 1826 as tiles. Rows move support and account deletion down 64px, not up 40, and tiles 1186px, not 1082. The figures for today were wrong, and those for rows and tiles held | Corrected 2026-11-05, here, in direction §7.3 and in BACKLOG's decision 84. **Decision 3 was answered on the old figure, so the owner was told, and confirmed it on these figures the same day.** Rows are still 1122px shorter than tiles |
| This spec's §2.2, the letter in the « bottom-left corner » | The left edge holds. The ink stands 11–13 CSS px above the rule at normal text, by its own line box | Worded in §2.2. `leading-none` would close 3.5px of that, so no change |
| This spec's §2.4, forced colours and the selected row | A loaded photo's hidden letter interrupts the foot rule too, and a selected row after the first has a faint rule inside the ring's top as well | Worded in §2.4, no code |
| This spec's §2.4, « WebKit is UNVERIFIED » | Seen in Safari: the failed photo shows a small blue « ? » and a thin outline beside its letter, the worst case §2.4 expected. The row, photo, letter, logo, tile and slow photo read as in Chromium | Recorded in §2.4 and §9, step 5. Removing the mark needs `onError`, which §2.4 rules out on `/` and landings, so it goes to the owner |
| This spec's §9 and the workflow, « how a 402 is caught » | The check read one fixed URL, cached for 31 days after its first read. On a stand-in answering 200 for that file and 402 for anything new, it stayed green. Locally, a file read earlier still answered 200 once its source was gone. Vercel's own answer past the ceiling is UNVERIFIED | Each run also reads one transformation nobody has read, at one transformation a day. The stand-in now reads red, and real bytes through Next's optimizer read 200. The alarm's sentence named one red of four, and now names all four |
| This spec's §8, the test-server guard as what holds the preload | It reads the speed. With no preload at all it stayed green on this Mac, and nothing read `NODE_OPTIONS` in `ci.yml` | A new unit test stands in for CI's stall with a lookup that never answers, and reads both lines. What CI's own libuv pool does is still read on the first CI run |
| This spec's §8 and §9 are silent on the alarm's status line | Dropping « card photo » from it left every test green | A new derived test, in `web/`, because any file under `backend/` starts `deploy-backend.yml` |
| This spec's §1 « toggle unchanged », §2.4 « as it does today », §11 « as today »; direction §7.4 « same mobile toggle » | The button did not move, but the row under it is new, and a row's text starts nearer the centre than a card's did. So it covered more than today: at 360×640 most of the name where `main` hid only the ✔︎, at 390×844 the commune and most of the price where `main` hid the end of a price | The owner saw the before and after and moved it: `left-m`, decision 5. Its words and behaviour stay. An e2e brings each row under it at 320, 360, 390, 768 and 820 |
| §13 « Cards with and without photos looked at » | Cannot be done on production | Locally now, on production when a salon is public, with a scheduled check for that day (§9 of this spec). A new job the parent did not plan |

---

## 15. What the PR writes in BACKLOG, word for word

- **B11.3**, after the existing line: « **Still open until a salon is public:** cards with and without photos looked at on the live site, the first real portrait's crop, and the letter's brief showing on a normal connection (`web-swiss-cards.md` §9). `check:card-photo` wakes by itself. »
- **B11.4**, after the existing line: « **Also from S3:** Lighthouse budgets for a landing and `/recherche`, with real bytes through the optimizer, as `web-swiss-cards.md` §7 measured once by hand. The stub's image host does not resolve, so a budget without that measures a page without its largest paint. »
- **B11.5**, added to its list: « A landing's `ItemList` carries an empty name for an unnamed public salon (`TaxonomyLandingView.tsx:277-283`). `ItemList` has no photo. A neighbouring marker paints over the open popup on `/recherche`, covering the rating and price (`ResultsMap.tsx:82`), which shows on the first real multi-salon list. `controls-shape.spec.ts:82` reads `/mon-compte/favoris`, which has no route and falls into `[id]`. `politique-confidentialite` names R2 for files and Vercel as the host, while resized public photos also sit in Vercel's cache: look after Apple's decision. `/mon-compte` at 200% text is 466 wide and scrolls sideways at 320 and 390, because « Exporter mes données » is `shrink-0` (`AccountClient.tsx:566`). Without that, 390 fits and 320 is 357 wide, from the profile's « Modifier » and e-mail lines. It predates S3. « Carte » on `/recherche` has the same forced-colours loss as the filled button above: no fill and no border, so a loose word on a white patch, now over the row's photo column (inferred from where it moved, not read again). On a landing a plain space before « ? » and « » » lets the mark start a line: « » sur chaque fiche. » at 360, a lone « ? » at 320 and 390. Those words feed `FAQPage`, so changing them changes what search engines read. Separately, « Combien coûte coiffure à Marcory ? » and « Coiffure à Plateau » read oddly in French. »
- **B12.7**, after the existing line: « **S3 (B11.3) touched the landings and the favourites' file and left C5, C6, C7 and C10, on the owner's decision of 2026-11-05.** The tile already takes a heart, so C6's first step is wiring. New lines, no audit lists them: the heart's message when signed out; a way out of an empty `/recherche`; a grid/list toggle on the web; a slow photo's retry; a failed photo's small blue « ? » and outline in Safari, which only `onError` could remove (`web-swiss-cards.md` §2.4); a place line for a salon with no commune; review photos drawn at 64 and 96px from the full file (up to 5 MB) on the salon page and `/pro/avis`, where a small copy made at upload under the same `review/{userId}/` prefix would keep them out of the image cache and still go with erasure (`web-swiss-cards.md` §11). »
- **B12.10**, after the existing line: « **The app's card, from S3:** `via.placeholder.com` for a missing photo (`salon-cover-photo.md:245`), no mark on a stopped favourite, its stale comment (`provider_card.dart:20-26`), its home strip going stale after a toggle. »
- **One decision row per answer in §11,** numbered from 82, the next free number in BACKLOG's decisions when this was written; check it again before writing. Decision 1 (`82`) records the owner's words, « do what is best in the long term », and that (a) was this spec's call. Decision 3 (`84`) gains the owner's confirmation on the corrected figures: « **Confirmed by you on 2026-11-05, on the corrected figures:** at 390 the section is 640 today, 704 as rows and 1826 as tiles. » Decisions 5, 6 and 7 are the three rows below, read as the next free numbers on 2026-11-05 (85 was the last).
- **Decision 86** (§11's 5), after 85: « 86. « Carte » on phones, centred or at the left? [B11.3] — ✅ **Answered (2026-11-05), after the before and after: move it left.** It sits at the page's gutter, over a row's photo column and never over its text. The plan said « as today », and that was wrong: the button had not moved, but the row under it is new, so it covered more of a row's text than of today's card (`web-swiss-cards.md` §11, decision 5). This overrides the spec's « toggle unchanged » for this one class. The toast stays where it is. »
- **Decision 87** (§11's 6): « 87. A list's first photo, fetched first or lazy like the rest? [B11.3] — ✅ **Answered (2026-11-05): load it first, on root, city, area and `/recherche`.** The rule in `web-swiss-cards.md` §7 reads applied throttling (`lighthouse --throttling-method=devtools`) from now on, not the simulated estimate, because the estimate does not model the request starting earlier. The same bytes either way. Lighthouse's own budget gate stays on its method: `lighthouserc.json` does not change and no budget moves. »
- **Decision 88** (§11's 7): « 88. §13's condition 2, on the five store-linked pages? [B11.3] — ✅ **Answered (2026-11-05): accepted for this merge, and from now on the condition reads « decoded payload »:** the payload compared after decoding and normalising. A real change still fails it, and a moved `<script>` boundary does not. The merge stop on it is lifted because you have read it. The measured record stays: 7 B per page, the boundary moved (`web-swiss-cards.md` §13). »
