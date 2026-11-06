# Web — the salon page in the new look (S4) — design spec

| | |
|---|---|
| **Status** | **§1: its plan approved by the owner's answers, from pictures, on 2026-11-05 (BACKLOG 95–98); this spec written 2026-11-06; not built, not merged.** §1 is B11.4's cover shape, brought forward by the owner (BACKLOG 94). It is written before any code, on its own branch, `feat/web-salon-cover`, cut from #737's tip `57b252a8`. Its PR is stacked on #737 and merges right after it, both after Apple's decision and on the owner's word. **§2, the rest of S4, is not specified yet.** |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-06 |
| **PRD ref / phase** | FR-WEB-PP-001/002 (presentation only) · V1 |
| **Module** | Web public: `app/[slug]`, `components/provider/Hero.tsx`, `ProviderView.tsx`, `BookingPanel.tsx`, `FavoriteButton.tsx`, `ReviewList.tsx`, `components/BookingCta.tsx`, `tailwind.config.ts` |
| **ROADMAP entry** | [2026-11-06-web-swiss-salon-cover.md](../roadmap/entries/2026-11-06-web-swiss-salon-cover.md) |
| **Parent** | [web-swiss-direction.md](web-swiss-direction.md) §6, §7.6, §12, §13 (S4). Follows [web-swiss-cards.md](web-swiss-cards.md) (S3, PR #737), whose crop token it reuses |
| **Skills checked** | myweli-web-guardrails ✓ · no backend change · no `mobile/` change (the app's side is BACKLOG B12.13) |
| **Depends on** | #737 merged first. Apple's decision on build 719 (BACKLOG B0.1) before either merge |

**How to read this.** §1 is the one slice built now. Every number in it says where it comes from:
- **measured (A)**: the pictures stage, 2026-11-05, Chromium, on a real `next build` of option A against the e2e stub (`b114/pics-facts.json`, scratch, never committed);
- **measured (A2)**: the review stage, the same day, on A plus the two edits in §1.6 (the bar and the toast). Those raw files are no longer on disk; the numbers are the plan's record. The build re-measures them;
- **arithmetic**, from classes and image sizes;
- **inferred**, said as such, and **UNVERIFIED** where nothing checked it.

No browser but Chromium was used.

---

## 1. The cover shape, brought forward (B11.4, first part)

### 1.1 Goal & scope

**Why.** On a computer the cover is a 1024×320 band, 3.2:1 (measured on `main` and #737). An upright 3:4 portrait shows 23.4% of its height there, 15.3%–38.8% at 20% (arithmetic, matched by a pixel read within 0.1 point on 48 boxes). An upright room cut at 20% in that band shows its ceiling: `salon_excellence` 15.8%–36.7%, `barber_shop_pro` 16.1%–35.7%, `spa_relax` 15.0%–40.0%. The owner rejected ceilings on the card (BACKLOG 89), and on 2026-11-05 brought B11.4's better shape forward rather than keep 20% in that band (BACKLOG 94).

**What.** The salon's cover becomes 3:2 at every width, through an `aspect-cover` token, and keeps the cards' cut, `object-subject` (50% 20%). From `lg` the page takes the direction's §7.6 layout, which the shape needs: the cover in columns 1–8, and beside it the name, the rating and `BookingPanel`, with only the panel sticky. The phone keeps its order. In a 3:2 box a 3:4 portrait shows 50% of its height (10%–60%) and `salon_excellence` 44.4% (11.1%–55.6%), about twice today's share on a computer.

**User stories.**
- *Phone.* I open a salon's page. I see its photo in about the shape the app uses (the app's cover is about 360×248, 1.45:1), then the name, the rating and « Réserver » without scrolling.
- *Computer.* I see a large photo of the salon on the left. Beside it I see the name, the rating, the starting price and « Réserver ». While I read the services and reviews, the booking box stays in view.

**In scope, brought forward from B11.4.**
- The `cover` aspect token, 3:2.
- The 3:2 cover at every width.
- Direction §7.6's layout from `lg`: the site's container, columns 1–8 and 9–12, the sticky panel.
- The hero's « Réserver » hidden from `lg`, where the panel's is beside it.
- Exact `sizes` for the cover.

**In scope because this slice redraws those exact elements.**
1. **The favourite button's focus jump, a defect fix.** On load the `[busy]` effect of `FavoriteButton.tsx:45-49` focuses the heart with nothing focused, and the browser scrolls to it. On the live site's code (`main` `ea0c8f0c`) and on #737 the page lands scrolled 317 px at 320×568 and 454 px at 844×390, past the cover (measured; the file is the same in both).
2. **« Réserver » disabled in the owner's preview.** `ProviderView.tsx:138` passes no `preview` to the hero, so its « Réserver » is a live link in the preview (read in code; UNVERIFIED in a browser). The panel's and the bar's are already disabled there.
3. **48 px targets** (SYSTEM §13.2): « Réserver » everywhere (36 px today, measured), and the panel's « Appeler » and « WhatsApp » (38 px today, measured).
4. **The reading cap on a review's text** (`max-w-content`): the sections' column is wider than today from 1280, and a review would run 749–920 px against direction §6.1's 720 cap (arithmetic).
5. **A wrong citation:** « salon-logo.md §5 » in `Hero.tsx` and direction §7.6. That section is about the logo's upload purpose. The logo on the cover is [salon-cover-photo.md](salon-cover-photo.md) §2.1, item 4.
6. **The phone bar stops above the footer** (`sticky bottom-0`), as « Carte » does (web-swiss-cards.md decision 5). Required: with the 48 px « Réserver » the bar is 65 px, and fixed it stands on the footer's last link at the page's end, where a press on « Instagram » lands on the bar (measured on A at 390×844 and 320×568).
7. **The favourite toast lifts above the bar** (`aboveFloatingControl`). Today it covers part of « Réserver ».
8. **The `<h1>` wraps its chip** (`flex-wrap`), because the rail is narrow.
9. **A generated test photo.** Upright, face-free, at least 2048 px wide, at a real camera's weight, drawn by a small committed script that is deterministic and procedural: no face, no stand-in, no demo photo, so its bytes need no licence and no large binary is committed. It is the only photo allowed in anything committed or in the PR. Without it the computer's gain cannot be measured (§1.9) and the PR has no photo it may show.

**Not in this branch yet: the four « Carte » fixes.** The owner answered « Fix them in the cover update » for the four costs of « Carte » never put in words (BACKLOG 91, §1.12). They are planned separately and join this branch only after the owner signs off that plan. Nothing in this spec builds them.

**Out of scope, staying in B11.4** (§2):
- Lighthouse budgets for the salon page, a landing and `/recherche`, with real bytes;
- `/recherche`'s hidden map on phones, and the home page's off-screen photos;
- direction §5.3's type sizes: the `<h1>` as `headlineLarge`/`displaySmall`, the `<h2>` as `headlineSmall`/`headlineMedium`;
- the sections: structural rules and hanging headings through `SiteSection`, `Faq` in the site look, flush left, and the salon page joining the full left-edge test;
- square corners for gallery tiles, review cards, the map and review photos;
- gallery `sizes`;
- the hero's alt « Salon {name} »;
- a salon with no photo shown with its logo or initial (direction §6.4);
- a failed cover's letter, as the card has (direction §8);
- focus hidden under the phone bar, if its fix needs global CSS (§1.4);
- the page's two layout exceptions in WEB-SYSTEM §16, until the sections take `SiteSection`;
- B12.5 (the salon's description) and `slow-phone.spec.ts:66`'s claim; B12.7's review photos;
- the parity gaps: in the app, tapping the cover opens the viewer, and the heart sits on the cover;
- « ✔ Vérifié » inside the `<h1>`'s text;
- the Pro preview's notice bar, which stays `max-w-5xl` above a page that is now wider (`SalonPreviewClient.tsx:81`).

**How it fits.** Presentation only, as the direction says: no route, API, contract, JSON-LD or copy change. `Hero` and `ProviderView` stay server components, and the only client change is `FavoriteButton`'s focus guard and its toast's lift. The token lives in `tailwind.config.ts` beside `card`, never in `styles/tokens.ts` (which `Icon`, and so the five store-linked pages, import).

### 1.2 Layout

**Below `lg`, one column** (direction §6.1), in today's order: the cover full width at 3:2, then the name block with the hero's « Réserver », the intro, the heart, the sections, and the bar.

| Viewport | Cover | `<h1>` | « Réserver » | Bar | Measured or not |
|---|---|---|---|---|---|
| 320×568 | 320×213.3, y 49–262.3 | 310.3–346.3 | hero 386.3–434.3 | 503–568 (65) | measured (A) |
| 360×640 | 360×240, y 49–289 | 337–373 | hero 413–461 | 575–640 | measured (A) |
| 390×844 | 390×260, y 49–309 | 357–393 | hero 433–481 | 779–844 | measured (A) |
| 412 wide | 412×274.7 | — | — | — | arithmetic |
| 768 wide | 768×512 | — | — | — | arithmetic, not shot |
| 820×1180 | 820×546.7, y 49–595.7 | 643.7–679.7 | hero 719.7–767.7 | 1115–1180 | measured (A) |
| 1023×768 | 1023×682, y 49–731 | 779–815, below the first screen | bar's, 712–760 | 703–768 | measured (A) |
| 844×390, a phone held sideways | 844×562.7, y 49–611.7 | 659.7–695.7, below the first screen | bar's, 334–382 | 325–390 | measured (A) |

At 390×844 against today (measured, `main` and #737 alike): the cover 49–273 becomes 49–309; the logo's ring 193–257 becomes 229–293; the `<h1>` 321–357 becomes 357–393; the rating 361–381 becomes 397–417; « Réserver » 397–433 (36 tall) becomes 433–481; the heart 577–625 becomes 625–673; the bar 791–844 (53) becomes 779–844 (65); the first `<h2>` 649 becomes 697. At 320 the cover is 11 px shorter than today's 224, at 390 36 px taller.

**From `lg`** (option A, the owner's answer 95):
- `<main>` is `mx-auto max-w-screen-2xl lg:grid lg:grid-cols-12 lg:gap-x-l lg:px-l`: `SITE_CONTAINER` without its phone padding, because the phone cover runs edge to edge and each section brings its own `px-m`. `lib/siteGrid.ts` is in the five pages' graph, so it gains no constant; an e2e holds the cover's x to the header logo's.
- DOM order: (1) the cover, `lg:col-span-8`; (2) the rail, `lg:col-span-4 lg:col-start-9 lg:row-span-2`, holding the name block (`lg:px-0 lg:pt-0`) and then the aside with `BookingPanel`, `sticky top-l`; (3) the sections, `lg:col-span-8`, unchanged inside; (4) the phone bar, the last child of `main`.
- With a cover, the cover takes row 1 in columns 1–8 and the rail rows 1–2 in 9–12, so the sections land in row 2 under the cover (measured, A2).

| Viewport | Cover (x, y, size) | Rail | Panel | Heart | Measured or not |
|---|---|---|---|---|---|
| 1024×768 | x 24–666.7, y 49–477.4, 642.7×428.4 | x 690.7, 309.3 wide | y 157–383 | 549.4–597.4 | measured (A) |
| 1280×800 | x 24–837.3, y 49–591.2, 813.3×542.2 | x 861.3, 394.7 wide | y 157–383 | 663.2–711.2 | measured (A) |
| 1366×768 | 870.7×580.4, y 49–629.4 | 423.3 wide | y 157–383 | 701.4–749.4 | measured (A) |
| 1440×900 | 920×613.3, y 49–662.3 | 448 wide | y 157–383 | 734.3–782.3 | measured (A) |
| 1920×1080 | x 216–1200, y 49–705, 984×656 | x 1224, 480 wide | y 157–383 | 777–825 | measured (A) |

At 1280×800 (measured, A): the category line at y 49, the `<h1>` 73–109 at x 861.3, the rating 113–133, the panel 157–383 with one « Réserver » at 246–294 and « Appeler » and « WhatsApp » at 310–358, all 48 tall; the logo's image 60×60 at x 42, y 513.2, inside its 64 px ring; the first `<h2>` at 735.2; a gallery tile 255.1×160. Today at 1280×800 (measured): the cover 1024×320 at x 128, the `<h1>` 417–453, two « Réserver » (the hero's 493–529 and the panel's 658–694, 36 tall), the panel 569–773, the heart 625–673.

**The cover's width from `lg`** is ⅔·(W − 48) − 8, that is ⅔·W − 40, up to 1536, and 984 from there (arithmetic; matches every row above).

**The name, the rating and « Réserver » are on the first screen** at 1024×768, 1280×800, 1366×768, 1440×900 and 1920×1080 (measured, A).

**What the photo shows** (arithmetic; one row serves every width with that shape; « 20% » is `object-subject`, the band is the part of the photo's height shown, from its top):

| Photo | 3:2, at 20% | Today on a computer, 1024×320 at 20% | Today at 390×224 at 20% |
|---|---|---|---|
| 3:4 portrait | 50.0%, 10.0–60.0 | 23.4%, 15.3–38.8 | 43.1%, 11.4–54.5 |
| 2:3 (`salon_excellence`) | 44.4%, 11.1–55.6 | 20.8%, 15.8–36.7 | 38.3%, 12.3–50.6 |
| 0.63 (`barber_shop_pro`) | 42.0%, 11.6–53.6 | 19.7%, 16.1–35.7 | 36.2%, 12.8–48.9 |
| 4:5 (`spa_relax`) | 53.3%, 9.3–62.7 | 25.0%, 15.0–40.0 | 45.9%, 10.8–56.8 |
| 4:3 landscape | 88.9%, 2.2–91.1 | 41.7%, 11.7–53.3 | 76.6%, 4.7–81.3 |
| 16:9 landscape | all the height, 84.4% of the width | 55.6%, 8.9–64.4 | all the height, 97.9% of the width |

At 3:2 and 20%, read from the pictures (the reading is the planner's): faces and the fade stay whole; a tall bun's top touches its source photo's edge, so only its lower part shows, and only `object-top` would keep it whole; the two upright rooms show their upper half, lights, mirrors and the tops of the stations, with the chairs cut. The owner chose 20% on those words (answer 96).

**Not chosen** (§1.12): the same arrangement inside today's 1024 page (B), the name under the photo (C), keeping 224 px below 640, and the app's 360:248. **Rejected before the questions:** a full-width 3:2 cover above the page, which puts the `<h1>` at y 780–816, cut by the edge of a 1280×800 screen, and below the first screen at 1366×768 and 1024×768 (arithmetic).

### 1.3 States

| State | Behaviour |
|---|---|
| **Loading** | The page is served HTML. The cover's box is reserved by its ratio, so nothing moves when the photo arrives, and it shows `bg-surfaceVariant` meanwhile, a calm block in place of up to 984×656 of white. It is not a scrim |
| **Photo** | As §1.2. `priority` stays, so the cover is fetched first |
| **No photo** | No cover element, as today. From `lg` the rail keeps column 9, with the `<h1>` at x 861, y 73 at 1280, and the sections start top left, the intro at y 49 (measured, A2, the cover removed in the page). Mostly the owner's preview: publishing needs at least three photos (`pro-salon-lifecycle.md:51`). The logo or letter in its place stays in B11.4 |
| **Failed cover** | The 813×542 grey block at 1280, with the logo on it and Chromium's small broken-image mark in its corner, and no letter (measured, A2). The card shows the salon's letter there (direction §8). That letter stays in B11.4 |
| **Long name** | « Institut de beauté et coiffure afro Excellence Riviera Palmeraie » does not overflow at 320, 1024 or 1280, but it squeezes « ✔ Vérifié » into a 54 px chip on two lines beside a three- or four-line name; at 1024 the name is four lines, 144 tall, in the 309 px rail (measured, A2). With `flex-wrap` the chip takes its own line. The same squeeze exists today at 320 with the same markup (inferred) |
| **The owner's preview** (`/pro/apercu`, `SalonPreviewClient.tsx:101`) | No JSON-LD and no heart, as today. Every « Réserver » is a disabled button, the hero's included (§1.1 item 2). The notice above the page stays `max-w-5xl`, narrower than the page from 1024 |
| **Signed in, favourite** | The heart under the intro as today. Its toast « Ajouté aux favoris » with « Annuler » sits above the bar under `lg` (§1.4) |
| **Favourite refused** | The heart's sentence under it as today (`FavoriteButton.tsx`), and focus comes back to the heart after a failed call (`consumer-optimistic-revert.test.tsx:421-437`, unchanged) |
| **Unknown slug** | 404, unchanged |
| **Text at 200% (browser font setting)** | Type is px and does not grow (WEB-SYSTEM §9, §15 rows 29 and 31). `aspect-cover` has no length, so the cover keeps its shape where today's rem `h-56`/`sm:h-80` grew (inferred). `min-h-12` is rem, so at a 32 px root the bar is 113 tall, and the toast's 80 px lift still leaves it over the top 24 px of « Réserver », over its left 23.5 px; « Annuler » does not reach it and presses go through (measured, A2). A px offset against a rem box is a defect by WEB-SYSTEM §9: recorded, the same kind as « Carte »'s in BACKLOG 91 |
| **Page zoom 200%** | 1280×800 becomes 640×400: the layout below `lg`, the photo fills the first screen and the bar shows « Réserver » (inferred, not measured). Today's heart sits below that screen too, so the focus jump would scroll today's page (inferred) |
| **320 wide, reflow** | The phone layout with a 213-tall cover, 11 px shorter than today: nothing new can overflow. No sideways scroll was found at any size shot (measured, A) |
| **A phone held sideways, 844×390** | Header and photo, with the bar's « Réserver » at the bottom (325–390), and the `<h1>` at 659.7, below the first screen (measured, A). Today lands scrolled 454 px instead, the `<h1>` at −37, past the cover (measured, `main`) |
| **640 to 1023 wide** | Full-width 3:2: 427 tall at 640, 512 at 768, 547 at 820, 682 at 1023. At 1023×768 the `<h1>` is at 779, below the first screen (today 417), and the bar's « Réserver » is on it. From 1006 to 1023 px wide on a 768-tall screen the bar runs over the logo's ring (651–715 at 1023, the bar from 703; measured at 1023, the range by arithmetic) |
| **Upright tablets** | 768×1024 and 820×1180 show the name on the first screen: the `<h1>` at 609 (arithmetic) and 643.7 (measured) |
| **Tablets held sideways** | Common ones are at least 1024 CSS px wide and get the computer layout |
| **Install banner** | Everything moves down 64 px (76 at 320 and 360, where its line wraps; web-swiss-cards.md §2.4). At 320×568 « Réserver » would end at 498, about 5 px above the bar (arithmetic). UNVERIFIED on this page: these builds had no store URL |
| **Forced colours** | Unchanged by this slice. B11.5 records that a filled button loses its fill there (`Button.tsx`); `BookingCta`'s « Réserver » is filled the same way, so likely the same (inferred, not looked at) |

### 1.4 Interaction

**The sticky panel, from `lg`.** Only the panel sticks, at `top-l` (24 px), as today. The name and the rating scroll away: the panel is 226 tall and the name block 108 (y 49–157 at 1280, measured), so a sticky column holding both would be about 334 tall, and with larger text or a four-line name it could pass a 768-tall screen and hide its own foot. Measured on A at « Avis » and on A2 at « Questions fréquentes »: the panel's top is 24 at 1024, 1280 and 1920, and a press at « Réserver »'s centre lands on it. **At the very end of the page** it rides up with the rail's end: its top at −113 at 1280 and −94 at 1024, so it is only partly on screen there, and « Réserver » still answers; at 1920 it stays at 24. The header is static (`Header.tsx:25`) and the install banner is in the flow, so nothing fixed sits at the top from `lg`. From `lg` the panel sits in columns 9–12 and never covers a focused element in 1–8 (WCAG 2.4.11).

**The phone bar, sticky above the footer.** `sticky bottom-0`, still the last child of `main`, in place of `fixed inset-x-0 bottom-0`; `main` loses `pb-xxl lg:pb-0`. `z-sticky`, `lg:hidden` and its content stay. Measured on A2:
- in the middle of the page its foot is the screen's foot, at 390×844 and 320×568;
- at the page's end all eight footer links answer at their centre, at 390×844, 360×640 and 320×568;
- at first load it sits where A's fixed bar did (779–844 at 390, 575–640 at 360, 503–568 at 320).

At the page's very end it is no longer at the screen's foot: at 390×844 it sits at the top of the screen (0–65), above the footer, and at 360×640 and 320×568 it has left the screen, so « Réserver » comes back after scrolling up 188 px and 244 px. A thinner fixed bar was not offered: with `py-xs` it would be 57 px and still start at 787, above the link's centre at 788 (arithmetic), so the footer fix would still be needed.

**The favourite toast.** `FavoriteButton` places its `<Toast>` at `bottom-l`, 24 px, on `z-toast` above the bar. Measured on A2 with the toast's classes swapped back: at 390×844 the pill (764–820) covers 32 px of « Réserver »'s height (788–836) over its left 23.5 px, and « Annuler » ends at x 268.5 where « Réserver » starts at 269, so presses still reach « Réserver »; at 320×568 « Annuler » covers a corner of « Réserver » 17 px wide and 18 px tall, and a press there undoes the favourite. With `aboveFloatingControl` the pill ends 15 px above the bar at 390 and 320 (measured, A2). `Toast.tsx` does not change; its comment names « Carte », and the call site says why it lifts here.

**No jump on load.** The focus effect runs only after a call the user started (a `called` guard, about six lines, outside the five pages' graph). On A, B, C and A2 the page lands at 0 everywhere measured. A probe « on load, focus stays on `<body>` » passed on A2 and failed on #737's `b0995489`, and `consumer-optimistic-revert.test.tsx:421-437` stays green with it (34 of 34 on A2's copy).

**« Réserver » in the preview** is `disabled={preview}` on the hero's `BookingCta` too: a button, with the title « Disponible après la mise en ligne », and no `/reserver` link anywhere on the preview.

**Focus order.**
- Phone: unchanged. The header, the hero's « Réserver », the heart, the gallery, … the FAQ, then the bar's « Réserver ».
- From `lg`: the header, then the panel's « Réserver », « Appeler » and « WhatsApp », then the heart, the gallery, … the FAQ. Today the panel is reached after the whole FAQ; now right after the name, which is also where it is on screen.

**Focus hidden under the phone bar (WCAG 2.4.11), a known defect.** A Tab walk on A2 in Chromium, at 390×844 and 1023×768, hid three controls entirely under the bar: the FAQ's « Quels sont les tarifs… » summary, and the map's « Toggle attribution » and « MapLibre ». « Où se trouve… » was mostly hidden, 46 of 48 px at 1023. Chromium scrolls a focused element just into view at the bottom and does not centre it. Today's fixed 53 px bar should do the same (inferred, not measured): it is not new. The simple fix, `scroll-padding-bottom` on `<html>` below `lg`, is global CSS shared with the five store-linked pages, so it waits for Apple's decision. The build tries a page-scoped `scroll-margin-bottom` on this page's controls; if it does not pass the lint or does not work, the defect goes to WEB-SYSTEM §15's register and stays in B11.4. WebKit and Gecko are UNVERIFIED (§1.14).

**Headings and landmarks.** The `<h1>`, in the rail, comes before every `<h2>` in the DOM. The `<h2>` list is unchanged, with no `<h3>`. The landmarks are today's: the `<header>` inside `<main>` (generic, not a banner) and an unlabelled `<aside>` inside `<main>`, left unlabelled because a name would make it a complementary landmark nested in `main`.

**Copy.** No word changes. « Réserver », « Appeler », « WhatsApp », « À partir de », « Ajouté aux favoris », « Annuler », « ✔ Vérifié », the alts « Salon {name} » and « Logo {name} » stay.

### 1.5 API, data, contract

None. `imageUrls[0]` is already the cover, `logoUrl` the logo. No `openapi.yaml`, backend or migration change.

### 1.6 Architecture & components

The code basis is two scratch patches, never committed: `b114/patches/A.patch` and `b114/patches/A2-over-A.patch`. They were made on `b0995489`, whose `web/` is the same as `57b252a8`'s, and on an archive of `57b252a8` A applies cleanly and A2 applies over it (dry run), read 2026-11-06. On `b0995489`, A passed `tsc --noEmit` and ESLint with `--max-warnings=0` on the changed files, and both checks were watched red (planning stage). The build reapplies them with tests and this spec.

- **Token.** `tailwind.config.ts`, `theme.extend.aspectRatio`: `{ card: '4 / 3', cover: '3 / 2' }`, and the comment's « `cover` waits for its first user in S4 » goes. Not in `styles/tokens.ts`: `Icon` imports that file. A web layout ratio with no app mirror: `tokens.mirror` does not read `extend`, which is how `card` already works (inferred from `card`; the build confirms it).
- **`components/provider/Hero.tsx`** splits into two exports:
  - `ProviderCover({ provider, sizes, className })`: `<div class="relative aspect-cover w-full bg-surfaceVariant …">` with the `<Image fill priority sizes={sizes} class="object-cover object-subject">` (alt `Salon {name}`) and the logo block, unchanged. `null` without a photo.
  - `ProviderHero({ provider, slug, preview, className })`: the `<header>` with the category line, the `<h1>` (gaining `flex-wrap`) with its chip, the rating, and « Réserver » in `mt-m lg:hidden` with `disabled={preview}`. `slug` defaults to `provider.slug ?? ''`; the page passes its route slug.
  - Its comment cites salon-cover-photo.md §2.1, item 4, for the logo.
- **`components/provider/ProviderView.tsx`**: the grid and DOM order of §1.2; the old `lg:grid-cols-3` wrapper and old aside go; `COVER_SIZES` (§1.9) exported for its test; the bar as in §1.4.
- **`components/BookingCta.tsx`**: `min-h-12` on both branches.
- **`components/provider/BookingPanel.tsx`**: « Appeler » and « WhatsApp » become `inline-flex min-h-12 flex-1 items-center justify-center`. The panel's `rounded-xl` box stays: direction §6.3 keeps `Card` for real containers.
- **`components/provider/ReviewList.tsx`**: a review's text gets `max-w-content`. The intro and the FAQ are already capped.
- **`components/provider/FavoriteButton.tsx`**: the `called` guard (§1.4) and `<Toast toast={toast} aboveFloatingControl />`.
- **Unchanged:** `Gallery`, `BeforeAfter`, `MapEmbed`, `Faq`, `Hours`, `ServiceList`, `SalonVisitsCard`, `Toast.tsx`, `lib/siteGrid.ts`, the JSON-LD, `providerMetadata`, `buildFaq`, `app/[slug]/page.tsx`.
- **The test photo's script** (§1.1 item 9) is the build's choice of name and tool, under `web/tool/`. `jpeg-js` 0.4.4 is already in the lockfile through Lighthouse (dev only, read in `package-lock.json`), so encoding needs no download; whether to declare it is the build's call.
- `Hero.tsx` and `ProviderView.tsx` gain `// Design: docs/design/web-swiss-salon.md §1`.

### 1.7 Security, privacy, and the five store-linked pages

**No new surface.** No route, API call, cookie, origin or secret. CSP unchanged. The page reads what it read.

**Privacy.** No face and no AI image anywhere. The demo salon photos (their licence is unknown, BACKLOG 37) and the owner's private stand-ins are never committed, uploaded or put in the PR. The only photo in anything committed or in the PR is the generated test photo. Scripted browsers abort every request that is not to localhost and block popups.

**The five store-linked pages** (`/support`, `/politique-confidentialite`, `/cgu`, `/mentions-legales`, `/suppression-compte`) must not change in content or computed style while Apple reviews.
- **Their code.** The walker (`b114/map-tools/closure2.py`, scratch) gives a 56-file closure at `57b252a8`, and none of the files this slice edits is in it: `ProviderView`, `Hero`, `BookingPanel`, `BookingCta`, `FavoriteButton`, `ReviewList` and `tailwind.config.ts` are all outside, and so is `Toast`, which does not change (run 2026-11-06). Its control, seeded from `app/[slug]/page.tsx`, reaches 65 files including `Hero`, `FavoriteButton` and `lib/siteGrid.ts`, so it can say yes. `lib/siteGrid.ts`, `styles/tokens.ts`, `lib/format.ts` and `lib/seo/jsonld.ts` are inside, and this slice does not edit them.
- **Their stylesheet.** `tailwind.config.ts` shapes the one shared stylesheet. Read with the Tailwind CLI on the patched trees (planning stage): A adds six rules, `.aspect-cover`, `.lg:col-span-8`, `.lg:col-start-9`, `.lg:row-span-2`, `.lg:px-0`, `.lg:pt-0`, and removes `.lg:col-span-2`, whose only user is today's `ProviderView`. A2 also removes `.pb-xxl`, whose only user in `app`, `components` and `lib` is `ProviderView` (a grep; the CLI was not re-run, so the build reads it).
- **The gate before the merge** is B11.3's five conditions (web-swiss-cards.md §13), with its tools, on the real branch against #737's tip, each from a fresh `git archive`, `npm ci` and `next build` against one stub. **Condition 3 changes for this PR:** « every old CSS rule still present, in order, added rules allowed » becomes « every old CSS rule still present, in order, except `.lg:col-span-2` and `.pb-xxl`, which none of the five uses; added rules allowed ». Condition 5, computed styles by property name and full-page pixels at 390 and 1280, must hold identical on all five, and is what proves the removal harmless.

### 1.8 SEO / AEO / GEO

**Unchanged:** the `<h1>` text, `<title>`, meta description, canonical, Open Graph and `og:image`, the JSON-LD (`LocalBusiness`, `FAQPage`, `BreadcrumbList`), the sitemap, `robots` and `llms.txt`. The served HTML keeps every word; its order changes in one place, the booking panel now coming before the sections instead of after them. The preview still renders no JSON-LD.

**Checks:**
- a new e2e on `/beaute-divine`: the `<h1>` text, the canonical and the JSON-LD blocks equal a list taken from `b0995489`. This is the salon page's row of direction §12's « SEO unchanged » guard, which S3 left to S4;
- the unit test of §1.10 that the `<h1>` precedes every `<h2>`;
- `served-html.spec.ts` and `axe.spec.ts:151` (`/beaute-divine`), unchanged and run;
- the five pages' gate (§1.7) for theirs.

### 1.9 Performance

**`sizes`.** `COVER_SIZES = '(min-width: 1536px) 984px, (min-width: 1024px) calc(66.67vw - 40px), 100vw'`, exact to the box at every width (arithmetic; the served preload's `imagesizes` read this value on A).

**The srcset keeps today's eight candidates**, 640, 750, 828, 1080, 1200, 1920, 2048 and 3840w. Next 14.2.35's `getWidths` counts only a `vw` after whitespace or the start (`/(^|\s)(1?\d?\d)vw/g`), so `calc(66.67vw…)` does not count and ` 100vw` does, and it keeps candidates at or above 640 × the smallest counted `vw` (read in `node_modules`). A `sizes` with no bare `vw` would list all 16 widths from 16w; a smallest `vw` of 60 keeps 384w.

| Screen | This slice | Today |
|---|---|---|
| 1024@1 | 750w | 1080w |
| 1280@1 | 828w | 1920w |
| 1280@2 | 1920w | 3840w |
| 1366@1, 1440@1, 1920@1 | 1080w | 1920w |
| 1920@2 | 2048w | 3840w |

Phones and tablets are unchanged, because both are `100vw`: 320@2 640w, 360@2 750w, 390@2 828w, 390@3 and 412@2.625 1200w; Lighthouse's 412 at DPR 1.75, 750w. The 1@1 rows and the phone rows at DPR 2 were read from `currentSrc` on A and match; the rest is arithmetic. **Vercel's transformations** (BACKLOG 93): the same eight candidate widths, so the number of transformations a photo can cost is unchanged. A computer now asks for a smaller width, a new cache entry, once.

**Expected (inferred):**
- **Phones:** the same file as today, in a taller box. LCP the same within noise.
- **Computers:** a smaller request, 828w in place of 1920w at 1280@1. Smaller bytes only if the source is wider than 828 px: Next's optimizer never enlarges (`withoutEnlargement: true`, `next/dist/server/image-optimizer.js:632`, read in 14.2.35). B11.3's 720×1080 `p1.jpg` comes back about 720 wide either way and cannot show the gain; hence the generated photo.
- **CLS 0:** the 3:2 box reserves its space before the photo, and the rail is server HTML.
- **Scripts:** no new client code beyond `FavoriteButton`'s guard.
- `priority` stays, so one `fetchpriority=high` preload follows the new `sizes`. The cover stays the likely LCP on phones and computers.

**How it is measured, by hand** (B11.3's method, web-swiss-cards.md §7, its tools in `b113/final-check3/lcp/`, scratch):
- `next build` and `next start` of #737's tip and of this branch, one at a time, against one stub;
- real bytes through the local optimizer: `rewrite.cjs` sends `https://cdn.stub/` to `serve.mjs`, which serves the generated photo as `p1.jpg`; B11.3's 720×1080 `p1.jpg` stays the phone control, where it was measured before;
- Lighthouse with `--throttling-method=devtools`, five runs each, a cold image cache per series, on `/beaute-divine` at 412×823 and 360×640 (the existing `lh-412.json`, `lh-360.json`) and at 1280×800 and 1920×1080 (a new desktop profile, DPR 1);
- recorded: the median LCP, which element it is (it must be the cover `<img>`, WEB.md §7), the request's `w=` and bytes, the photo preloads in the HTML (exactly one, with the new `imagesizes`), CLS and TBT;
- no picture of a demo photo is kept.

| Screen | Before (#737) LCP median | After LCP median | LCP element | `w=` and bytes | CLS, TBT |
|---|---|---|---|---|---|
| 412×823 | to be measured | to be measured | to be measured | to be measured | to be measured |
| 360×640 | to be measured | to be measured | to be measured | to be measured | to be measured |
| 1280×800 | to be measured | to be measured | to be measured | to be measured | to be measured |
| 1920×1080 | to be measured | to be measured | to be measured | to be measured | to be measured |

**Rule.** If the phone median rises by 100 ms or more at 412 or 360, stop and look before going on: the shape should not change the bytes there. The numbers become the baseline for B11.4's budget, which stays out of CI here: CI's stub fails the photo host on purpose, `lhci` uploads to temporary public storage (no demo photo may go there), and `cwv-budget.test.ts` wants an assert block for every collected URL. That machinery stays on B11.4's line for three pages at once. Measuring the salon page's LCP by hand meets direction §13's « Salon LCP measured » for this slice.

### 1.10 Tests

Each new guard is watched red on committed work, on a copy (`git worktree add --detach` or `git archive` into scratch), never by editing and checking out in the branch's tree. Each result is recorded with the commit.

**Unit (vitest)**

| Test | What it holds | The mutation that must turn it red |
|---|---|---|
| `hero-cover.test.tsx`, rewritten for `ProviderCover` | The cover's box has `aspect-cover`; the cover has `object-subject`; the logo has neither | Remove `aspect-cover`; move `object-subject` to the logo; remove it from the cover |
| New: the cover's srcset | `sizes === COVER_SIZES`; the srcset's widths are exactly 640…3840w, smallest 640; `fetchpriority="high"` | `sizes` with `60vw` (384w appears); a `sizes` with no bare `vw` (16w appears); drop `priority` |
| `tokens.theme-pin.test.ts` | `aspectRatio.cover === '3 / 2'`; the CSS has `.aspect-cover {` with `aspect-ratio: 3 / 2` | Set `'16 / 9'`; remove the key |
| New: the hero in the preview | `ProviderHero preview` draws « Réserver » as a disabled button, with no `/reserver` link | Drop `disabled={preview}` |
| New: `FavoriteButton` on load | Mounted with nothing focused, `document.activeElement` stays `<body>` | Remove the `called` guard |
| `consumer-optimistic-revert.test.tsx:421-437` | Focus comes back after a failed call | Must stay green with the fix |
| New: `ProviderView`'s order | The `<h1>` precedes every `<h2>`; the panel's « Réserver » precedes the heart; the bar is `main`'s last child | Move the rail after the sections; move the bar out of `main` |
| New: `ProviderView` with no photo | No cover element; the rail keeps `lg:col-start-9`; the `<h1>` is still first | Drop `lg:col-start-9` |
| New: the favourite toast | Its region carries the lift (`bottom-xxxl` under `lg`) | Drop `aboveFloatingControl` |
| `salon-rating-sites.test.tsx`, `provider-address-dedupe.test.tsx` | Unchanged | — |

**E2E (Playwright, its own ports 3000 and 8787)**

| Spec | What it holds | The mutation |
|---|---|---|
| `site-look.spec.ts:1029-1040` | The cover at 50% 20%, the logo and the gallery at 50% 50%. The selector becomes `main img[…]`, because the cover leaves `<header>` | Remove the position class, after the selector change |
| New, `site-look` | The cover's box is 1.5 ± 0.01 at 320, 390, 820, 1023, 1024, 1280 and 1920. From 1024: the cover's x equals the header logo's (± 1); the `<h1>`'s x ≥ the cover's right edge + 23; the name block's `<header>` top equals the cover's top (± 1), and the `<h1>` is 24 ± 1 below it (cover 49, `<h1>` 73 at 1280). Below 1024: the `<h1>`'s top is below the cover's foot | `aspect-cover` → `h-80`; drop `lg:col-span-8`; drop `lg:px-l`; drop `lg:pt-0` |
| New, first screen | At 1024×768, 1280×800 and 1366×768 the `<h1>`, the rating and the panel's « Réserver » are inside the viewport | Move the rail after the sections |
| New, sticky | At 1280×800 and 1024×768, scrolled to « Avis » and to « Questions fréquentes », the panel's top is 24 ± 1 and `elementFromPoint` at « Réserver »'s centre is that link. Nothing is asserted at the very end, where the panel rides up | Drop `sticky` |
| New, no jump | At 320×568, 844×390 and 1280×800, after load and the favourites call, `scrollY === 0` and focus is on `<body>`. At 1280 only the focus check can fail, since the heart is on screen | Revert the guard (expect 317 at 320 and 454 at 844×390) |
| New, the bar at the end | At 390×844 and 320×568, scrolled to the end, every footer link answers `elementFromPoint` at its centre | The bar back to `fixed inset-x-0` (red: « Instagram » under it, measured on A) |
| New, the bar mid-page | At 390×844 and 320×568, scrolled to « Avis », the bar's foot equals the screen's foot (± 0.5) and « Réserver » answers | Drop `sticky` (the bar falls to the page's end) |
| New, the toast against the bar | At 390×844 and 320×568, after a press on the heart (favourites answered in the browser, as `site-look.spec.ts:976` does), the toast's pill ends above the bar and a press at « Réserver »'s top-left corner lands on it | Drop `aboveFloatingControl` (red at 320: « Annuler » takes the corner, measured) |
| `type-overflow.spec.ts` | A long-name subject at 320, 1024 and 1280: « ✔ Vérifié » keeps one line | Drop `flex-wrap` (the chip goes to two lines, measured) |
| `provider.spec.ts:113-115` | « Réserver »'s href. Added: exactly one visible « Réserver » link at 1280 (two today) | Drop `lg:hidden` |
| `pro.spec.ts:962-973` | Added: no `a[href$="/reserver"]` in the preview | Drop `disabled={preview}` (red on `b0995489` too: the defect) |
| `tap-targets.spec.ts` | « Réserver » at 390 (hero and bar) and at 1280 (panel), and « Appeler » and « WhatsApp » at 1280, are at least 48 tall | Remove `min-h-12` |
| New, SEO unchanged | `/beaute-divine`'s `<h1>` text, canonical and JSON-LD equal a list taken from `b0995489` | Change a word of the `<h1>` |
| `axe.spec.ts:151`, `focus`, `controls-shape`, `slow-phone`, `account`, `redirects`, `served-html`, `store-linked-pages` | Existing; run, no change expected | — |
| Not added | A no-photo salon in the stub. A new slug changes `served-html`'s and `provider`'s counts, as B11.3 found; the unit test holds that path and A2's measurement saw it | — |

**Also:** the five pages' gate (§1.7) with its controls; `tsc`, ESLint with `--max-warnings=0`, `gen:api` with no drift, `next build`; the Lighthouse runs of §1.9. Full suites run one at a time, never in parallel.

**What these cannot see** (direction §12): no screenshot harness exists, so before-and-after pictures at 360, 768, 1440 and 1920 (and this spec's 320, 390, 820, 1280) are looked at, using the generated test photo only. The private sheets with stand-ins and demo rooms went to the owner only and never go into the PR. 768 was not shot yet.

### 1.11 Rollout

- **Branch:** `feat/web-salon-cover`, cut from #737's tip `57b252a8` (by the local ref, `origin/feat/web-swiss-cards` is `57b252a8`; nothing was fetched). Commits authored as the owner, conventional, no tool attribution.
- **This commit is docs only** (the spec first). The build follows on the same branch.
- **Its own PR, stacked on #737** (base `feat/web-swiss-cards`), merged right after #737, both after Apple's decision and on the owner's word (answer 98).
- **CI cannot check it until #737 merges.** `ci.yml` runs on pull requests into `main` only (`pull_request: branches: [main]`), so a PR based on #737's branch gets no CI until #737 merges and the PR is retargeted. So the full local suites run first, one at a time: vitest, `next build`, Playwright, the five pages' gate, the Lighthouse runs.
- **The merge train:** after #737's squash, `git rebase --onto main <#737's old tip>`, retarget the PR to `main` before the push, let CI run, then merge on the owner's word.
- **Two production deploys**, #737's and this one's, each on the owner's word. With no public salon and `dynamicParams = false`, production can show only the five store-linked pages and the shared CSS after each, so that is all a read-back can check until a salon is public: words and links on all five on `myweli.com`, as after #730.
- **The four « Carte » fixes** join this branch as their own commits, with their own tests, only after the owner signs off their plan (BACKLOG 91).
- **Rollback:** revert the PR. No data, no API, no flag.

### 1.12 Decisions (the owner's answers)

Asked on 2026-11-05 with four private sheets of pictures (`1-ordinateur`, `2-cadrage-ordinateur`, `3-telephone`, `4-option-A`; stand-ins and demo rooms, never published) and answered the same evening, each with its recommendation.

| # | BACKLOG | Question | Answer | Not chosen |
|---|---|---|---|---|
| 1 | 95 | On a computer, where does the salon's name go? | **« Beside photo, full width »** (recommended): option A, §1.2 | Beside the photo in today's narrower page (B); under the photo, as today (C) |
| 2 | 96 | Where is the 3:2 cover cut? | **« 20%, as the cards »** (recommended): one token, `object-subject`, 50% 20%, on the cover and the cards | Centre, on the cover only; 35%, on the cover only (each would have split the token) |
| 3 | 97 | On phones, what shape? | **« 3:2, as on computer »** (recommended): one ratio and one crop everywhere | Keep today's 224 px band below 640 |
| 4 | 98 | Ship it how? | **« Own update after #737 »** (recommended): this branch, its own PR stacked on #737, merged right after it | Inside #737, as one update |

**Answered the same night, on costs from S3:**
- **« Carte »'s four costs never put in words** (BACKLOG 91): at doubled text the toast paints over the word « Carte » for 170 px of scroll; with the banner the button stands on « Disponible aujourd'hui » at 360×640; on `?q=vide` at 320 it passes over « Aucun salon trouvé » while scrolling; at 1023×768 it has also left the screen by the page's end. **Answer: « Fix them in the cover update ».** A separate run is planning those fixes; they join this branch after the owner signs off that plan. Not built here.
- **The first photo's cost on a DPR 3 phone** (BACKLOG 92): a landing whose first two salons have no photo fetches one 1080–1200w file off-screen, from the third tile. **Answer: « Keep it ».**

### 1.13 Costs, in plain words

**Put to the owner with the questions, before the answers:**
- On big screens the service list and the gallery get wider than today: lists up to 952 px on a 1920 screen, gallery tiles 255 wide at 1280 and 312 at 1920 against 209, so their photos are cut a little more.
- Two style rules leave the site's shared styles. Only this page used them; the five pages Apple reviews never did.
- In the Pro preview, the notice at the top stays narrower than the page.
- At 20%, rooms show their upper half, lights, mirrors and the tops of the stations, with the chairs cut, and a plain room shows mostly wall; a tall bun keeps only its lower part.
- On phones the photo is 36 px taller than today on a common phone and 11 px shorter on the smallest.
- A phone held sideways, or a computer window under 1024 px wide, shows the photo first, with the name just below the first screen and « Réserver » in the bar. Today a phone held sideways already opens 454 px down the page.
- « Réserver » becomes 48 px tall, so the phone bar grows from 53 to 65 px and stops above the footer, because fixed it would hide the footer's last link. The page is 65 px longer than today on a common phone. At the very end of a page the bar sits at the top of a common phone's screen, and on a small phone it has left the screen: about 190–245 px of scrolling up gets « Réserver » back.
- With the browser's text at double size, « Ajouté aux favoris » still covers the top of « Réserver », and presses go through to it.
- CI cannot check this PR until #737 merges; the full checks run locally first. Two deploys, each on the owner's word.
- Found, and possibly waiting for Apple's decision: reached with the Tab key, three controls hide completely under the bottom bar, probably already today.

**Measured or inferred, and not put in these words, so the answers do not cover them.** They go to the owner with the PR, for their word at the merge:
- From 1006 to 1023 px wide on a 768-tall screen, the bar runs over the bottom of the salon's logo (cosmetic).
- On this page the `<h1>` does not start on the logo's x, the sections do not hang their headings beside the rail, and the sections' text starts at x 40 where the cover starts at 24 (WEB-SYSTEM §16's two exceptions, until B11.4's sections).
- A cover that fails to load is a grey block with Chromium's broken-image mark and the logo, with no letter.
- At the very end of a page on a computer, the booking box rides up with the rail and is only partly on screen (its top at −113 at 1280); « Réserver » still answers.
- At 1024 the gallery tiles get narrower than today, 198 against 209.
- Through a computer at 200% zoom, the photo fills the first screen (inferred).

### 1.14 Open items

- **The owner:** sign off the plan of the four « Carte » fixes before they join this branch (BACKLOG 91); give the word for each merge and deploy, after Apple's decision.
- **The owner:** installing Playwright's WebKit 2311 and Firefox 1532 (the machine has 2248 and 1509) is a download and needs their word; until then WebKit and Gecko are UNVERIFIED, focus under the bar included.
- **The Gate stage:** the LCP table of §1.9; the five pages' gate with the amended condition 3; `.pb-xxl`'s removal read with the Tailwind CLI, not a grep; `tokens.mirror` confirmed blind to `extend`; the page-scoped focus fix tried, or the defect registered.
- **Not shot yet:** any width at 768, a six-photo gallery (the stub salon has one), the install banner on this page with a store URL, the owner's preview in a browser, real phones and tablets.
- **Still open after the merge:** B11.3's line on a room on the salon page's cover stays open until a salon is public, and the first real salon's cover is looked at on the live site, because a generator's framing and a demo room are not a salon's photos.
- **The app** (B12.13): its comment « the website's `h-56` on phones » (`provider_detail_screen.dart:1590`) goes stale when this merges; the app keeps 224 dp, centred, until after Apple's decision.

### 1.15 Definition of done

- [ ] `tsc`, ESLint `--max-warnings=0`, `gen:api` with no drift, vitest, `next build`, Playwright, axe green; no budget raised.
- [ ] Every new guard of §1.10 watched red on a copy of committed work, recorded.
- [ ] Tokens only (closed theme, no arbitrary value); 48 px targets; visible focus; heading order; four states.
- [ ] SEO checks of §1.8 green: `<h1>`, canonical, JSON-LD unchanged.
- [ ] The five pages' gate: conditions 1–5, condition 3 as amended in §1.7, with controls.
- [ ] §1.9's table filled from real runs, the LCP element named.
- [ ] Pictures with the generated test photo only, looked at; nothing private in the PR.
- [ ] This spec, WEB-SYSTEM §16, the direction, BACKLOG, the README index and the roadmap entry true at the merge.
- [ ] Feature branch, PR stacked on #737, CI green after the retarget, no tool attribution, merged on the owner's word.

### 1.16 What this PR writes in BACKLOG, word for word

Each body below is in `docs/BACKLOG.md` exactly once, character for character. B11.3, B11.4, B12.13 and decisions 91, 92 and 94 are **appended to**, so what #737 wrote there stays whole (web-swiss-cards.md §15 mirrors it).

- **Decisions, group heading**, after decision 94: « **The salon page's cover in 3:2, B11.4 brought forward (B11.4)** — asked on 2026-11-05 with four private sheets of pictures, and answered the same evening (`web-swiss-salon.md` §1.12, §1.13). **On the record with the questions, not asked:** « Réserver » becomes 48 px tall, so the phone bar grows from 53 to 65 px and stops above the footer, as « Carte » does, because fixed it would hide the footer's last link; the page is 65 px longer than today on a common phone; at the very end of a page the bar sits at the top of a common phone's screen, and on a small phone it has left the screen, so « Réserver » comes back after scrolling up about 190–245 px; with the browser's text at double size « Ajouté aux favoris » still covers the top of « Réserver », and presses go through to it. »
- **Decision 95**: « 95. On a computer, where does the salon's name go? [B11.4] — ✅ **Answered (2026-11-05), from pictures: « Beside photo, full width »,** the recommendation, over « Beside the photo, in today's narrower page » and « Under the photo, as today ». From `lg` the page takes the site's container: the cover in columns 1–8 at 3:2, and beside it the name, the rating and the booking box, which alone stays in view while people read (web-swiss-direction §7.6). **Put to you with the question:** on big screens the service list and the gallery get wider, lists up to 952 px on a 1920 screen, and gallery photos are cut a little more; two style rules leave the site's shared styles, which only this page used and the five pages Apple reviews never did; in your Pro preview the notice at the top stays narrower than the page. »
- **Decision 96**: « 96. Where is the 3:2 cover cut? [B11.4] — ✅ **Answered (2026-11-05), from pictures: « 20%, as the cards »,** the recommendation, over « Centre, on the cover only » and « 35%, on the cover only ». One token, `object-subject`, 50% 20%, on the cover and the cards, as decision 89. **Put to you with the question:** faces and the fade stay whole and a tall bun keeps its lower part; rooms show their upper half, ceiling lights, mirrors and the tops of the stations, with the chairs cut, and a plain room shows mostly wall. The first real salon's cover still gets looked at on the live site (B11.3). »
- **Decision 97**: « 97. On phones, what shape? [B11.4, B12.13] — ✅ **Answered (2026-11-05), from pictures: « 3:2, as on computer »,** the recommendation, over « Keep today's phone band (224 px) ». One ratio and one crop on every screen. **Put to you with the question:** the photo is 36 px taller than today on a common phone and 11 px shorter on the smallest, and the name and « Réserver » stay on the first screen; a phone held sideways, or a computer window under 1024 px wide, shows the photo first, with the name just below the first screen and « Réserver » in the bar, where today a phone held sideways already opens 454 px down the page. The app keeps its 224 dp, centred, until after Apple's decision (B12.13). »
- **Decision 98**: « 98. Ship it how? [B11.4] — ✅ **Answered (2026-11-05): « Own update after #737 »,** the recommendation, over « Inside #737, as one update ». Its own branch, `feat/web-salon-cover`, cut from #737's tip, and its own PR stacked on #737, merged right after it; both wait for Apple's decision and your word, and each of the two deploys is on your word. **Put to you with the question:** the automatic checks cannot run on it until #737 merges and the PR is retargeted, so the full checks run locally first. »
- **Decision 91**, at its end: « **Those four, put to you afterwards in these words on 2026-11-05: answered « Fix them in the cover update ».** Their fixes are planned separately and join B11.4's cover branch (decision 98) once you sign off that plan. Until then nothing about them is fixed, and they stand as measured (`web-swiss-salon.md` §1.12). »
- **Decision 92**, at its end: « **That DPR 3 cost, put to you afterwards in these words on 2026-11-05: ✅ « Keep it ».** On a DPR 3 phone a landing whose first two salons have no photo still fetches one 1080–1200w file off-screen, from the third tile (`web-swiss-cards.md` §7). »
- **Decision 94**, at its end: « **The plan with pictures went to you on 2026-11-05, and you answered it the same evening: decisions 95–98.** »
- **B11.3**, at its end: « **The cover's new shape is decided (decisions 95–98, `web-swiss-salon.md` §1):** the line above on a room on the salon page's cover stays open until a salon is public, and is read on the first real salon's cover. »
- **B11.4**, at its end: « **The cover's shape, specified on 2026-11-06 (decisions 95–98):** `web-swiss-salon.md` §1, on its own branch, `feat/web-salon-cover`, stacked on #737, not built yet. It brings forward the `cover` token, the 3:2 cover at every width cut at `object-subject`, direction §7.6's layout from `lg` with only the booking box sticky, and exact `sizes`. It also fixes the focus jump above, the live « Réserver » in your preview, « Réserver », « Appeler » and « WhatsApp » under 48 px, the phone bar over the footer's last link, and the favourite message over « Réserver ». The four « Carte » fixes of decision 91 join that branch once you sign off their plan. **Still here after it:** Lighthouse budgets for the salon page, a landing and `/recherche`, with real bytes; `/recherche`'s hidden map on phones; the home page's off-screen photos; the `<h1>` and `<h2>` sizes of direction §5.3; the sections (hanging headings through `SiteSection`, `Faq` in the site look, flush left, the salon page in the full left-edge test, and until then the page's two exceptions in WEB-SYSTEM §16); square gallery tiles, review cards, map and review photos; gallery `sizes`; the hero's alt « Salon {name} »; a salon with no photo shown with its logo or letter; a failed cover's letter (today a grey block with Chromium's broken-image mark); focus hidden under the phone bar, if its fix needs global CSS; B12.5's description and `slow-phone.spec.ts:66`'s claim; B12.7's review photos; the parity gaps (in the app the cover opens the viewer and the heart sits on it); « ✔ Vérifié » inside the `<h1>`; the Pro preview's notice, which stays `max-w-5xl`. »
- **B12.13**, at its end: « **From B11.4's cover (decision 97):** the site's cover becomes 3:2 on phones too, so the comment « the website's `h-56` on phones » (`provider_detail_screen.dart:1590`) goes stale when `feat/web-salon-cover` merges. The app keeps its 224 dp, centred, until after Apple's decision; fix the comment with the crop. »

### 1.17 Where the plan was wrong at this branch's base

Read on `57b252a8`, 2026-11-06. Its `web/` and `mobile/` trees are the same as `b0995489`'s, where the plan read the code.
- The plan cuts this branch from `86d91f14`. #737 has moved on to `57b252a8`, which is `86d91f14` plus a merge of `main` (`5e3b3449`, #740, a legal manifest and a roadmap entry); `web-swiss-cards.md` is the same in both, so its line numbers held.
- The plan's list of `web-swiss-cards.md` lines to turn into history misses :1341 (decision 8's answer paragraph) and :1250–:1252 and :1325, where the never-put costs of « Carte » and the DPR 3 cost now have answers.
- « WEB-SYSTEM §15 rows 28 and 29 » for text size: row 28 is the tab strips. The rows on type in px are 29 and 31.
- `site-look.spec.ts:1031-1039`: the test runs :1029–:1040.
- The A2 raw files the plan cites (`b114/fix/raw/A2-*.json`) are no longer on disk; their numbers survive in the plan only.

---

## 2. The rest of S4 (not specified yet)

What stays in B11.4 is listed in §1.1. It is specified here, with its own questions and pictures, before it is built. Until then the salon page keeps the two exceptions recorded in WEB-SYSTEM §16.
