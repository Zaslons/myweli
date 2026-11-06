# Web — the salon page in the new look (S4) — design spec

| | |
|---|---|
| **Status** | **§1: its plan approved by the owner's answers, from pictures, on 2026-11-05 (BACKLOG 95–98). This spec was written on 2026-11-06 before any code, then built the same day on `feat/web-salon-cover` (§1.10 records its guards watched red), read by three reviews and corrected (§1.18); not merged.** §1 is B11.4's cover shape, brought forward by the owner (BACKLOG 94). Its branch, `feat/web-salon-cover`, is cut from #737's tip `57b252a8`. Its PR is stacked on #737 and merges right after it, both after Apple's decision and on the owner's word. **§2, the rest of S4, is not specified yet.** |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-06 |
| **PRD ref / phase** | FR-WEB-PP-001/002 (presentation only) · V1 |
| **Module** | Web public: `app/[slug]`, `components/provider/Hero.tsx`, `ProviderView.tsx`, `BookingPanel.tsx`, `FavoriteButton.tsx`, `ReviewList.tsx`, `components/BookingCta.tsx`, `components/Toast.tsx` (a second lift), `tailwind.config.ts`; `tool/test-photo.mjs`, `.gitignore` and `package.json` (`jpeg-js`) under `web/` |
| **ROADMAP entry** | [2026-11-06-web-swiss-salon-cover.md](../roadmap/entries/2026-11-06-web-swiss-salon-cover.md) |
| **Parent** | [web-swiss-direction.md](web-swiss-direction.md) §6, §7.6, §12, §13 (S4). Follows [web-swiss-cards.md](web-swiss-cards.md) (S3, PR #737), whose crop token it reuses |
| **Skills checked** | myweli-web-guardrails ✓ · no backend change · no `mobile/` change (the app's side is BACKLOG B12.13) |
| **Depends on** | #737 merged first. Apple's decision on build 719 (BACKLOG B0.1) before either merge |

**How to read this.** §1 is the one slice built now. Every number in it says where it comes from:
- **measured (A)**: the pictures stage, 2026-11-05, Chromium, on a real `next build` of option A against the e2e stub (`b114/pics-facts.json`, scratch, never committed);
- **measured (A2)**: the review stage, the same day, on A plus the two edits in §1.6 (the bar and the toast). Those raw files are no longer on disk; the numbers are the plan's record. The build and the reviews re-measured some of them, and say so where they did;
- **measured (build)** and **measured on the build**: the build stage's own runs on `feat/web-salon-cover`, 2026-11-06;
- **measured (review)**: the three reviews of the built branch at `1ca5664e`, the same day, each on its own `git archive` build against the e2e stub, every request off localhost aborted (§1.18);
- **measured (fix)**: the fix stage's own runs after those reviews, the same day;
- **arithmetic**, from classes and image sizes;
- **inferred**, said as such, and **UNVERIFIED** where nothing checked it.

No browser but Chromium was used. Paths under `b113/`, `b114/` and `b116/` name a scratch folder on the machine that measured: never committed, and not reproducible from this repository. The numbers this spec relies on are written here.

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
7. **The favourite toast lifts above the bar.** Today it covers part of « Réserver ». The build used « Carte »'s px lift (`aboveFloatingControl`); a review found it short with the browser's text at double size, so the fix stage gave `Toast` a lift in rem, `aboveBookingBar` (§1.4).
8. **The `<h1>` wraps its chip** (`flex-wrap`), because the rail is narrow.
9. **A generated test photo.** Upright, face-free, at least 2048 px wide, at a real camera's weight, drawn by a small committed script that is deterministic and procedural: no face, no stand-in, no demo photo, so its bytes need no licence and no large binary is committed. It is the only photo allowed in anything committed or in the PR. Without it the computer's gain cannot be measured (§1.9) and the PR has no photo it may show.
10. **Focus under the phone bar** (WCAG 2.4.11), added by the build as §1.4 allowed: fixed on this page alone, at normal text, with nothing set on `<html>`; its one rule in the shared stylesheet matches only inside the page's two columns (§1.4).

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
- at a doubled browser font, the last 17–19 px of a focused control under the 113 px phone bar (§1.4): a px margin against a rem bar. The toast's was the same kind and is fixed in rem (§1.4); a rem clearance token, and a named Tailwind variant in place of the arbitrary `[&_*]`, wait for §2 (§1.18);
- the page's two layout exceptions in WEB-SYSTEM §16, until the sections take `SiteSection`;
- B12.5 (the salon's description) and `slow-phone.spec.ts:66`'s claim; B12.7's review photos;
- the parity gaps: in the app, tapping the cover opens the viewer, and the heart sits on the cover;
- « ✔ Vérifié » inside the `<h1>`'s text;
- the Pro preview's notice bar, which stays `max-w-5xl` above a page that is now wider (`SalonPreviewClient.tsx:81`);
- found by a review, outside this diff and the same on #737's tip (measured by the review): « Itinéraire » (57.5×20) and a review's « Signaler » (46.4×48) under SYSTEM §13.2's 48 px; the map's zoom buttons, 29 tall, and its « MapLibre » link, 14; and with the browser's text at double size, a price range such as « 15 000 – 25 000 FCFA » in `ServiceList` (`whitespace-nowrap`) makes the page scroll sideways, 441 px wide at 320, 360 and 390.

**How it fits.** Presentation only, as the direction says: no route, API, contract, JSON-LD or copy change. `Hero` and `ProviderView` stay server components, and the only client changes are `FavoriteButton`'s focus guard and its toast's lift, which takes a new prop of `Toast`, `aboveBookingBar` (§1.6). The token lives in `tailwind.config.ts` beside `card`, never in `styles/tokens.ts` (which `Icon`, and so the five store-linked pages, import).

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
| **Signed in, favourite** | The heart under the intro as today. Its toast « Ajouté aux favoris » with « Annuler » sits above the bar under `lg`, at normal and at doubled text (§1.4) |
| **Favourite refused** | The heart's sentence under it as today (`FavoriteButton.tsx`), and focus comes back to the heart after a failed call (`consumer-optimistic-revert.test.tsx:421-437`, unchanged) |
| **Unknown slug** | 404, unchanged |
| **Text at 200% (browser font setting)** | Type is px and does not grow (WEB-SYSTEM §9, §15 rows 29 and 31). `aspect-cover` has no length, so the cover keeps its shape where today's rem `h-56`/`sm:h-80` grew (inferred). `min-h-12` is rem, so at a 32 px root the bar is 113 tall. The build's px lift, 80 px, left the toast 33 px into the bar, and at 320 and 360 « Annuler » over a corner of « Réserver », 17×24 px at 320 and 7×24 at 360, where a press undid the favourite; at 390 every press reached « Réserver » (measured by the review). A2 had measured 390 only, and the build wrote « presses go through » from it. **Fixed** with a lift in rem, `bottom-20`: the pill ends 47 px above the 113 px bar at 320, 360, 390, 844×390 and 1023×768, and all 45 points sampled across « Réserver » answer (measured (fix)), and at normal text exactly where it was. Held at 320 and 360 by `salon-page.spec.ts`. The focus clearance is 96 px, so 17–19.3 px of a control focused at the screen's foot stays under that bar, none hidden whole (measured on the build, §1.4). A px offset against a rem box is a defect by WEB-SYSTEM §9: the clearance's is recorded; « Carte »'s toast, the same kind, is decision 91's first cost and keeps its px lift until the owner signs off that plan |
| **Page zoom 200%** | 1280×800 becomes 640×400: the layout below `lg`, the photo fills the first screen and the bar shows « Réserver » (inferred, not measured). Today's heart sits below that screen too, so the focus jump would scroll today's page (inferred) |
| **320 wide, reflow** | The phone layout with a 213-tall cover, 11 px shorter than today: nothing new can overflow. No sideways scroll was found at any size shot (measured, A) |
| **A phone held sideways, 844×390** | Header and photo, with the bar's « Réserver » at the bottom (325–390), and the `<h1>` at 659.7, below the first screen (measured, A). Today lands scrolled 454 px instead, the `<h1>` at −37, past the cover (measured, `main`) |
| **640 to 1023 wide** | Full-width 3:2: 427 tall at 640, 512 at 768, 547 at 820, 682 at 1023. At 1023×768 the `<h1>` is at 779, below the first screen (today 417), and the bar's « Réserver » is on it. From 1006 to 1023 px wide on a 768-tall screen the bar runs over the logo's ring (651–715 at 1023, the bar from 703; measured at 1023, the range by arithmetic) |
| **Upright tablets** | 768×1024 and 820×1180 show the name on the first screen: the `<h1>` at 609 (arithmetic) and 643.7 (measured) |
| **Tablets held sideways** | Common ones are at least 1024 CSS px wide and get the computer layout |
| **Install banner** | Everything moves down 64 px (76 at 320 and 360, where its line wraps; web-swiss-cards.md §2.4). At 320×568 « Réserver » would end at 498, about 5 px above the bar (arithmetic). UNVERIFIED on this page: these builds had no store URL |
| **Forced colours** | Unchanged by this slice. B11.5 records that a filled button loses its fill there (`Button.tsx`); `BookingCta`'s « Réserver » is filled the same way, so likely the same (inferred, not looked at) |

### 1.4 Interaction

**The sticky panel, from `lg`.** Only the panel sticks, at `top-l` (24 px), as today. The name and the rating scroll away: the panel is 226 tall and the name block 108 (y 49–157 at 1280, measured), so a sticky column holding both would be about 334 tall, and with larger text or a four-line name it could pass a 768-tall screen and hide its own foot. Measured on A at « Avis » and on A2 at « Questions fréquentes »: the panel's top is 24 at 1024, 1280 and 1920, and a press at « Réserver »'s centre lands on it. **At the very end of the page** it rides up with the rail's end: its top at −113 at 1280 and −94 at 1024, so it is only partly on screen there, and « Réserver » still answers; at 1920 it stays at 24. At 1366×768 the panel's « Réserver » is off the screen there, y −73 to −25 (−51 to −15 on #737's tip), and with the browser's text at double size the whole panel leaves the screen at 1024, 1280, 1366 and 1440 (measured by the review; the same on #737's tip). The header is static (`Header.tsx:25`) and the install banner is in the flow, so nothing fixed sits at the top from `lg`. From `lg` the panel sits in columns 9–12 and never covers a focused element in 1–8 (WCAG 2.4.11).

**The phone bar, sticky above the footer.** `sticky bottom-0`, still the last child of `main`, in place of `fixed inset-x-0 bottom-0`; `main` loses `pb-xxl lg:pb-0`. `z-sticky`, `lg:hidden` and its content stay. Measured on A2:
- in the middle of the page its foot is the screen's foot, at 390×844 and 320×568;
- at the page's end all eight footer links answer at their centre, at 390×844, 360×640 and 320×568;
- at first load it sits where A's fixed bar did (779–844 at 390, 575–640 at 360, 503–568 at 320).

At the page's very end it is no longer at the screen's foot: at 390×844 it sits at the top of the screen (0–65), above the footer, and on a shorter screen it has left it. Scrolled up from the very end, « Réserver » is wholly back on the screen after 185 px at 360×640 and 243 px at 320×568 (A2 had 188 and 244), 263 px at 1023×768, 501 px at 640×400 (a 1280×800 screen at 200% zoom) and 580 px on a phone held sideways, 844×390, where the bar's top is at −588.3 (measured by the review on the build, and again by the fix stage on its own build, `02955881`, to the pixel). On upright tablets the bar is still on the screen at the very end: 71–136 at 768×1024 and 209.7–274.7 at 820×1180 (measured (fix)). #737's fixed bar never leaves the screen: at 844×390 it sits at 337–390 at the end (measured by the review). A thinner fixed bar was not offered: with `py-xs` it would be 57 px and still start at 787, above the link's centre at 788 (arithmetic), so the footer fix would still be needed.

**The favourite toast.** `FavoriteButton` places its `<Toast>` at `bottom-l`, 24 px, on `z-toast` above the bar. Measured on A2 with the toast's classes swapped back: at 390×844 the pill (764–820) covers 32 px of « Réserver »'s height (788–836) over its left 23.5 px, and « Annuler » ends at x 268.5 where « Réserver » starts at 269, so presses still reach « Réserver »; at 320×568 « Annuler » covers a corner of « Réserver » 17 px wide and 18 px tall, and a press there undoes the favourite. With the px lift, `aboveFloatingControl`, the pill ends 15 px above the bar at 390 and 320 (measured, A2), at normal text. With the browser's text at double size the bar is 113 px and that lift fell short: the pill ran 33 px into it, and at 320 and 360 « Annuler » covered a corner of « Réserver » (found by the review, §1.3). **The fix:** `Toast` gains `aboveBookingBar`, `bottom-20 lg:bottom-l`, rem like the bar: 80 px at normal text, the same place as before, and 160 px at a 32 px root (at normal text the pill ends 15 px above the 65 px bar at 320, 360, 390, 844×390 and 1023×768, at a 32 px root 47 px above the 113 px bar, and all 45 points sampled across « Réserver » answer at both; measured (fix)). « Carte »'s `aboveFloatingControl` does not change: its toast at doubled text is decision 91's first cost, planned separately, and the same rem lift is there for that plan to take. `Toast` is outside the five store-linked pages' graph (§1.7).

**No jump on load.** The focus effect runs only after a call the user started (a `called` guard, about six lines, outside the five pages' graph). On A, B, C and A2 the page lands at 0 everywhere measured. A probe « on load, focus stays on `<body>` » passed on A2 and failed on #737's `b0995489`, and `consumer-optimistic-revert.test.tsx:421-437` stays green with it (34 of 34 on A2's copy).

**« Réserver » in the preview** is `disabled={preview}` on the hero's `BookingCta` too: a button, with the title « Disponible après la mise en ligne », and no `/reserver` link anywhere on the preview.

**Focus order.**
- Phone: unchanged. The header, the hero's « Réserver », the heart, the gallery, … the FAQ, then the bar's « Réserver ».
- From `lg`: the header, then the panel's « Réserver », « Appeler » and « WhatsApp », then the heart, the gallery, … the FAQ. Today the panel is reached after the whole FAQ; now right after the name, which is also where it is on screen.

**Focus hidden under the phone bar (WCAG 2.4.11): found in planning, fixed by the build on this page alone.** A Tab walk on A2 in Chromium, at 390×844 and 1023×768, hid three controls entirely under the bar: the FAQ's « Quels sont les tarifs… » summary, and the map's « Toggle attribution » and « MapLibre ». « Où se trouve… » was mostly hidden, 46 of 48 px at 1023. Chromium scrolls a focused element just into view at the bottom and does not centre it. Today's fixed 53 px bar should do the same (inferred, not measured): it is not new.

The build walked it again on its own tree before the fix (Chromium, from the top of the page to the footer, the map's tiles blocked, 2026-11-06), and measured how much of each focused control stood under the bar:
- at 390×844: « Quels sont les tarifs… » 48 of 48 px, « Où se trouve… » 8 of 48, the first gallery photo 65 of 160;
- at 1023×768: « Quels sont les tarifs… » 48 of 48, « Où se trouve… » 46 of 48, the gallery photo 65 of 160;
- at 320×568: « Comment réserver… » 63.7 of 64, the gallery photo 33.3 of 160, « Comparaison 1 » and « 2 » 29.3 of 56;
- at a 32 px root (the bar 113 tall): at 390, « Comparaison 1 » and « 2 » 110 of 112 and « Comment réserver… » 109 of 112; at 320, « Agrandir » 95.7 of 96 and « Quels sont les tarifs… » 113 of 160.
The map's controls did not come up in that walk, unlike A2's: the map mounts only once it nears the screen, and the walk had already passed it (found by the review). The guard now mounts the map first and starts again from the top. The walk then reaches its six stops, « Map », « Voir Beauté Divine sur la carte », « Zoom in », « Zoom out », « Toggle attribution » and « MapLibre », and none stands under the bar at 390, 320 or 1023 (measured by the review, and held by the walk since the fix stage).

**The fix.** `max-lg:[&_*]:scroll-mb-fab` in `ProviderView`, on the rail and on the sections' column (the build held it in a constant, `CLEAR_OF_BAR`): below `lg`, whatever is focused in them is scrolled to stop 96 px (`fab`, the clearance a floating control is owed, SYSTEM §5) above the screen's foot. Not on `main`, which holds the bar, whose own « Réserver » would then chase its margin. It sets nothing on `<html>`: `scroll-padding-bottom` there would do the same once, but every page would take it, the five store-linked pages included. Its one rule does go into the shared stylesheet, `.max-lg\:\[\&_\*\]\:scroll-mb-fab * { scroll-margin-bottom: 96px }` inside `@media not all and (min-width: 1024px)`, and only an element inside one of the page's two columns matches it. It is an arbitrary *variant* with a token value, the first in the code, and WEB-SYSTEM §16 records it. **It is written in the two `className`s, not in a constant** (since the fix stage), because ESLint's Tailwind rules read class names only there: in the build's constant, `CLEAR_OF_BAR`, `scroll-mb-[96px]` and a misspelt `scroll-mb-fabb` both passed; inline, the first fails `no-arbitrary-value` and the second `no-custom-classname` (watched, §1.10, L1 and L2 with their controls). The build's sentence here, that `no-arbitrary-value` « reads values and passes it », was wrong: it never read the constant. **After:** nothing under the bar at 390×844, 320×568 and 1023×768; at a 32 px root, 17–19.3 px of each control focused at the foot stays under the 113 px bar, none hidden whole (2.4.11 asks that a focused control not be entirely hidden), the hero's « Réserver » at 320 included (75.3 of 96 before). Held by `salon-page.spec.ts`'s Tab walk at normal text; the doubled font is recorded, not held. WebKit and Gecko are UNVERIFIED (§1.14).

**Headings and landmarks.** The `<h1>`, in the rail, comes before every `<h2>` in the DOM. The `<h2>` list is unchanged, with no `<h3>`. The landmarks are today's: the `<header>` inside `<main>` (generic, not a banner) and an unlabelled `<aside>` inside `<main>`. Chromium exposes that `<aside>` as a `complementary` landmark, unnamed, on this branch and on #737's tip alike, because an `<aside>` scoped to `main` is complementary with a name or without one (read in Chromium's accessibility tree by the review). The build's reason for leaving it unlabelled, that a name would make it a landmark, was wrong. axe finds no violation of `landmark-complementary-is-top-level`, `landmark-unique`, `heading-order` or `region` on either (measured by the review). A name stays out of this slice.

**Copy.** No word changes. « Réserver », « Appeler », « WhatsApp », « À partir de », « Ajouté aux favoris », « Annuler », « ✔ Vérifié », the alts « Salon {name} » and « Logo {name} » stay.

### 1.5 API, data, contract

None. `imageUrls[0]` is already the cover, `logoUrl` the logo. No `openapi.yaml`, backend or migration change.

### 1.6 Architecture & components

The code basis is two scratch patches, never committed: `b114/patches/A.patch` and `b114/patches/A2-over-A.patch`. They were made on `b0995489`, whose `web/` is the same as `57b252a8`'s, and on an archive of `57b252a8` A applies cleanly and A2 applies over it (dry run), read 2026-11-06. On `b0995489`, A passed `tsc --noEmit` and ESLint with `--max-warnings=0` on the changed files, and both checks were watched red (planning stage). **The build** applied both to this branch with `git apply`, cleanly, and added what they lacked: `flex-wrap` on the `<h1>`, `CLEAR_OF_BAR` (§1.4), the `// Design:` lines and corrected citations, the class-less `<div>` removed, the test photo's script, and the tests of §1.10.

- **Token.** `tailwind.config.ts`, `theme.extend.aspectRatio`: `{ card: '4 / 3', cover: '3 / 2' }`, and the comment's « `cover` waits for its first user in S4 » goes. Not in `styles/tokens.ts`: `Icon` imports that file. A web layout ratio with no app mirror: `tokens.mirror` does not read `extend`, which is how `card` already works (inferred from `card`; the build confirms it).
- **`components/provider/Hero.tsx`** splits into two exports:
  - `ProviderCover({ provider, sizes, className })`: `<div class="relative aspect-cover w-full bg-surfaceVariant …">` with the `<Image fill priority sizes={sizes} class="object-cover object-subject">` (alt `Salon {name}`) and the logo block, unchanged. `null` without a photo.
  - `ProviderHero({ provider, slug, preview, className })`: the `<header>` with the category line, the `<h1>` (gaining `flex-wrap`) with its chip, the rating, and « Réserver » in `mt-m lg:hidden` with `disabled={preview}`. `slug` defaults to `provider.slug ?? ''`; the page passes its route slug.
  - Its comment cites salon-cover-photo.md §2.1, item 4, for the logo.
- **`components/provider/ProviderView.tsx`**: the grid and DOM order of §1.2; the old `lg:grid-cols-3` wrapper and old aside go, and so does the class-less `<div>` the patches kept inside the sections' column (no box changes); `COVER_SIZES` (§1.9) exported for its test; the bar as in §1.4; the focus clearance, `max-lg:[&_*]:scroll-mb-fab`, written in the rail's and the sections' `className`s (§1.4; the build kept it in a constant, `CLEAR_OF_BAR`, which ESLint did not read).
- **`components/BookingCta.tsx`**: `min-h-12` on both branches.
- **`components/provider/BookingPanel.tsx`**: « Appeler » and « WhatsApp » become `inline-flex min-h-12 flex-1 items-center justify-center`. The panel's `rounded-xl` box stays: direction §6.3 keeps `Card` for real containers.
- **`components/provider/ReviewList.tsx`**: a review's text gets `max-w-content`. The intro and the FAQ are already capped.
- **`components/provider/FavoriteButton.tsx`**: the `called` guard (§1.4) and `<Toast toast={toast} aboveBookingBar />`. The build had `aboveFloatingControl`, « Carte »'s px lift (§1.4).
- **`components/Toast.tsx`** (since the fix stage): a second lift, `aboveBookingBar`, `bottom-20 lg:bottom-l`, in rem, for the salon page's bar. `aboveFloatingControl` and its classes stay as they were, for « Carte ».
- **Unchanged:** `Gallery`, `BeforeAfter`, `MapEmbed`, `Faq`, `Hours`, `ServiceList`, `SalonVisitsCard`, `lib/siteGrid.ts`, the JSON-LD, `providerMetadata`, `buildFaq`, `app/[slug]/page.tsx`.
- **The test photo's script** (§1.1 item 9): `web/tool/test-photo.mjs`, with its types in `test-photo.d.mts`. `node tool/test-photo.mjs` writes `web/tool/out/salon-test-photo.jpg`; a path may be passed instead. `web/.gitignore` ignores every JPEG under `web/` (`*.jpg`, `*.jpeg` and their capitals, since the fix stage; the build ignored `/tool/out` only), so neither the test photo nor a demo photo written elsewhere in `web/` goes in with `git add -A` (watched with `git check-ignore`, §1.10, G). It draws a room from numbers, with one seeded generator: a ceiling with three pendant lights, three mirrors over a counter with bottles, three black chairs, a cabinet, a plank floor and a plant, under a camera's grain and vignette, and ticks on both edges at every tenth of the height, longer at the half, so a picture of the cover shows which band it keeps. No person and nothing from a model. 2448×3264 (3:4, an 8-megapixel phone's shape), JPEG quality 92, 2,373,939 bytes, sha256 `820144ba…1898`, the same bytes on two runs (measured 2026-11-06, 2.3 s). `jpeg-js` is declared at exactly 0.4.4 in `devDependencies` since the fix stage, as two reviews asked: the copy `@lhci/cli`'s Lighthouse already locked, so only the lockfile's root entry changed (`npm install --package-lock-only --offline` left the hand-edited lockfile as it was), and a bump of `@lhci/cli` can no longer move or drop the encoder the pinned hash depends on. The build had left it undeclared to spare the lockfile. `tests/test-photo.test.ts` holds it: a 96×128 render's hash pinned, upright, at least 2048 wide, 1.5–4 MB.
- `Hero.tsx` and `ProviderView.tsx` gain `// Design: docs/design/web-swiss-salon.md §1`.

### 1.7 Security, privacy, and the five store-linked pages

**No new surface.** No route, API call, cookie, origin or secret. CSP unchanged. The page reads what it read.

**Privacy.** No face and no AI image anywhere. The demo salon photos (their licence is unknown, BACKLOG 37) and the owner's private stand-ins are never committed, uploaded or put in the PR. The only photo in anything committed or in the PR is the generated test photo. Scripted browsers abort every request that is not to localhost and block popups.

**The five store-linked pages** (`/support`, `/politique-confidentialite`, `/cgu`, `/mentions-legales`, `/suppression-compte`) must not change in content or computed style while Apple reviews.
- **Their code.** The walker (`b114/map-tools/closure2.py`, scratch) gives a 56-file closure at `57b252a8`, and none of the files this slice edits is in it: `ProviderView`, `Hero`, `BookingPanel`, `BookingCta`, `FavoriteButton`, `ReviewList` and `tailwind.config.ts` are all outside, and so is `Toast`, which the fix stage changed (run 2026-11-06 on the build, by the review on `1ca5664e`, and again on the fix stage's tree, §1.18). Its control, seeded from `app/[slug]/page.tsx`, reaches 65 files including `Hero`, `FavoriteButton` and `lib/siteGrid.ts`, so it can say yes. `lib/siteGrid.ts`, `styles/tokens.ts`, `lib/format.ts` and `lib/seo/jsonld.ts` are inside, and this slice does not edit them.
- **Their stylesheet.** `tailwind.config.ts` and the classes in the code shape the one shared stylesheet. Planning read A with the Tailwind CLI and A2's `.pb-xxl` with a grep. **Read on built output by the review**, `1ca5664e` against `57b252a8`: 584 rules became 589. Removed: `.pb-xxl` and `.lg:col-span-2`. Added: `.aspect-cover`, `.lg:col-span-8`, `.lg:col-start-9`, `.lg:row-span-2`, `.lg:px-0`, `.lg:pt-0`, and the focus clearance's `.max-lg\:\[\&_\*\]\:scroll-mb-fab *` inside `@media not all and (min-width: 1024px)`. The other 582 rules are all present, in their old order; the two other CSS files are byte-identical. Neither removed class has another user: not in any `web/` source, test or stylesheet, not for Tailwind's own extractor over the 345 content files, and in no file of the branch's build (the base's build has them only in the salon pages and `pro/apercu`). **The fix stage adds one rule,** `.bottom-20`, the toast's lift: on the fix stage's build of `02955881` against the review's build of `57b252a8`, 584 rules became 590, the same two removed and eight added, the 582 kept in their old order (`css-order.py`; its two controls, two rules swapped and one dropped, caught 100 and 1). Its first build, of `9f3e337c`, also carried `.scroll-mb-\[96px\]`: a code comment spelt that class, and Tailwind reads comments; `02955881` reworded the comment, and the rule went.
- **The gate before the merge** is B11.3's five conditions (web-swiss-cards.md §13), with its tools, on the real branch against #737's tip, each from a fresh `git archive`, `npm ci` and `next build` against one stub. **Condition 3 changes for this PR:** « every old CSS rule still present, in order, added rules allowed » becomes « every old CSS rule still present, in order, except `.lg:col-span-2` and `.pb-xxl`, which none of the five uses; added rules allowed ». Condition 5, computed styles by property name and full-page pixels at 390 and 1280, must hold identical on all five, and is what proves the removal harmless. **How condition 3 is read:** B11.3's `static.py` checks order with one iterator, which the first removed rule uses up, so on this branch it reports 239 rules « missing or out of order » where the true number is 0 (found by the review). So the kept rules are checked in order on their own, as the review's `css-order.py` does, with two controls that must fail: two rules swapped, and one dropped.

### 1.8 SEO / AEO / GEO

**Unchanged:** the `<h1>` text, `<title>`, meta description, canonical, Open Graph and `og:image`, the JSON-LD (`LocalBusiness`, `FAQPage`, `BreadcrumbList`), the sitemap, `robots` and `llms.txt`. The served HTML keeps every word; its order changes in one place, the booking panel now coming before the sections instead of after them. The preview still renders no JSON-LD.

**Checks:**
- a new e2e on `/beaute-divine` (`salon-page.spec.ts`): the `<h1>` text, the `<title>`, the canonical, the meta description, `og:image`, every JSON-LD block, the `<h2>` list and, since the fix stage, every `<meta>` with all its attributes and every canonical or alternate link (the build read only `og:image` of Open Graph's and Twitter's tags) equal a list taken from `57b252a8`, whose `web/` is `b0995489`'s, built against the stub before any edit (`tests/e2e/salon-seo-before.json`). This is the salon page's row of direction §12's « SEO unchanged » guard, which S3 left to S4;
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

**How it was measured, by hand, on 2026-11-06** (B11.3's method, web-swiss-cards.md §7, with the gate's copies of its tools, scratch):
- `next build` of #737's tip `57b252a8` and of this branch at `1933a88b`, each from a fresh `git archive`, against one stub and with the same environment, then both served side by side;
- real bytes through the local optimizer: `rewrite.cjs` sends `https://cdn.stub/` to a local file server whose only file is the generated photo, served as `p1.jpg` (`node tool/test-photo.mjs`: 2448×3264, 2,373,939 B). The stub's other photos answer 404 on both sides. B11.3's 720×1080 demo photo was not used as a phone control: only the generated photo was served;
- Lighthouse 12.1.0 in Chrome 156, `--throttling-method=devtools` (decision 6, read back from all 50 reports), five runs per series, the image cache emptied before each series, so each series' first run includes the photo's transformation. The series alternated between the two builds;
- phones: Lighthouse's slow 4G, 562 ms latency, 1,474 kbps down and CPU ×4, at 412×823 and 360×640 (DPR 1.75, the existing `lh-412.json` and `lh-360.json`) and at 390×844 (DPR 3, a new profile). Computers: the desktop form factor at DPR 1, at 1280×800 and 1920×1080, with Lighthouse's desktop preset applied as devtools throttling, 150 ms latency, 9,216 kbps and CPU ×1. The preset's own devtools values are 0, which means « unset », so it would have applied none;
- Chrome resolved only 127.0.0.1. The one image the page asks the photo host for directly, a review's photo, failed on both sides without leaving the machine;
- no picture of any photo is kept.

Medians of five, with the range in brackets:

| Screen | Before (#737) LCP median | After LCP median | LCP element | `w=` and transfer | CLS, TBT |
|---|---|---|---|---|---|
| 390×844, DPR 3 | 1,648 ms (1,643–1,833) | 1,643 ms (1,632–1,710) | The cover `<img>` in 5 of 5 on both sides: 390×224 before, 390×260 after | 1200w, 47.9 KiB, on both | CLS 0.0036 in 4 runs and 0 in 1, on both; TBT 0 |
| 1280×800, DPR 1 | 558 ms (541–1,786) | 408 ms (398–721) | The cover `<img>`, 5 of 5: 1024×320 before, 813×542 after | 1920w, 163.4 KiB before; 828w, 24.7 KiB after | 0, 0 |
| 412×823, DPR 1.75 | 1,533 ms (1,518–2,683) | 1,528 ms (1,521–1,681) | The cover `<img>`, 5 of 5: 412×224 before, 412×275 after | 750w, 21.4 KiB, on both | CLS 0.0009 in 4 runs and 0 in 1, on both; TBT 0 |
| 360×640, DPR 1.75 | 1,528 ms (1,521–1,533) | 1,537 ms (1,519–1,567) | The cover `<img>`, 5 of 5: 360×224 before, 360×240 after | 640w, 18.0 KiB, on both | CLS 0.0026 in 5 of 5, on both; TBT 0 |
| 1920×1080, DPR 1 | 558 ms (556–1,773) | 426 ms (414–910) | The cover `<img>`, 5 of 5: 1024×320 before, 984×656 after | 1920w, 163.4 KiB before; 1080w, 39.1 KiB after | 0, 0 |

**The preloads, read from the served HTML:** exactly one photo preload on each side, `fetchpriority="high"`, with the same eight widths, 640 to 3840w. Its `imagesizes` is `100vw` before and `COVER_SIZES` after. The optimizer's bodies for this photo were 24,046 B at 828w, 38,812 B at 1080w, 47,756 B at 1200w and 166,018 B at 1920w, the same from both builds.

**What it shows.**
- **Phones:** the same file and the same bytes, in a taller box (36, 51 and 16 px taller at 390, 412 and 360). The median moved by −5, −5 and +9 ms, so the rule below is not reached. CLS reads the same small value on both sides; where it comes from was not looked at.
- **Computers:** 828w in place of 1920w at 1280, and 1080w in place of 1920w at 1920: 24.7 and 39.1 KiB against 163.4 KiB. The median LCP is 150 and 132 ms earlier. The first run of a series, the one that transforms the photo, took 721 and 910 ms after against 1,786 and 1,773 ms before.
- These are a local server's numbers, not the live site's: there is no CDN, the optimizer runs on the same machine, and another run's servers were up on the machine at the time. The salon page has no Lighthouse budget yet (B11.4).

**Rule.** If the phone median rises by 100 ms or more at 412 or 360, stop and look before going on: the shape should not change the bytes there. **Not reached on 2026-11-06:** −5 ms at 412 and +9 ms at 360. The numbers become the baseline for B11.4's budget, which stays out of CI here: CI's stub fails the photo host on purpose, `lhci` uploads to temporary public storage (no demo photo may go there), and `cwv-budget.test.ts` wants an assert block for every collected URL. That machinery stays on B11.4's line for three pages at once. Measuring the salon page's LCP by hand meets direction §13's « Salon LCP measured » for this slice.

### 1.10 Tests

Each new guard is watched red on committed work, on a copy (`git worktree add --detach` or `git archive` into scratch), never by editing and checking out in the branch's tree. Each result is recorded with the commit.

**Unit (vitest).** The build's names; « mutation » is what must turn the test red, watched in the record below.

| Test | What it holds | The mutation that must turn it red |
|---|---|---|
| `hero-cover.test.tsx`, rewritten for `ProviderCover` | The cover's box has `aspect-cover`; the cover has `object-subject`; the logo has neither, and its box is not a cover; no photo draws nothing | Remove `aspect-cover`; move `object-subject` to the logo; remove it from the cover |
| `salon-page.test.tsx`: the cover's srcset | Rendered in `ProviderView`: `sizes === COVER_SIZES`; the srcset's widths are exactly 640…3840w; `fetchpriority="high"`, not lazy | `sizes` with `60vw` (384w appears); a `sizes` with no bare `vw` (16w appears); drop `priority` |
| `tokens.theme-pin.test.ts` | `aspectRatio.cover === '3 / 2'`, `card` still `4 / 3`; the CSS has `.aspect-cover { aspect-ratio: 3 / 2 }` | Set `'16 / 9'`; remove the key |
| `salon-page.test.tsx`: the preview | `ProviderHero preview` draws « Réserver » as a disabled button with its title, and no `/reserver` link; `ProviderView preview` has no `/reserver` link anywhere and three disabled « Réserver » | Drop `disabled={preview}` |
| `salon-page.test.tsx`: the heart on load | Mounted with nothing focused, after its read, `document.activeElement` stays `<body>` | Remove the `called` guard |
| `consumer-optimistic-revert.test.tsx:421-437` | Focus comes back after a failed call | Must stay green with the fix (34 of 34) |
| `salon-page.test.tsx`: the order | The `<h1>` precedes every `<h2>`; the panel's « Réserver » precedes the heart; `main`'s last child is the bar, with its « Réserver » and « À partir de » | Move the rail after the sections; move the bar out of `main` |
| `salon-page.test.tsx`: no photo | No cover image and no `.aspect-cover`; the rail, which holds the panel, keeps `lg:col-start-9`; the `<h1>` is still first | Drop `lg:col-start-9` |
| `salon-page.test.tsx`: the toast | `FavoriteButton`'s toast region carries `bottom-20` and `lg:bottom-l`, and not the px `bottom-xxxl` (since the fix stage; the build's test read `bottom-xxxl`) | Drop the lift; put the px lift back |
| `test-photo.test.ts` | A 96×128 render twice gives the same bytes, and its hash is pinned; the full photo is upright, at least 2048 wide, 1.5–4 MB, and decodes at its size | `Math.random` in the grain; width 2000 |
| `salon-rating-sites.test.tsx`, `provider-address-dedupe.test.tsx` | Unchanged, green | — |

**E2E (Playwright, its own ports 3000 and 8787)**

| Spec | What it holds | The mutation |
|---|---|---|
| `site-look.spec.ts`, « where a photo is cut » | The cover at 50% 20%, the logo and the gallery at 50% 50%. The selector is now `main img[…]`, because the cover left `<header>` | Remove `object-subject` from the cover |
| `site-look.spec.ts`, new, « the salon page's cover » | At 320, 390, 820, 1023, 1024, 1280 and 1920: the cover's box is 1.5 ± 0.01; its width is the layout's (± 1) and, since the fix stage, the width the `<img>`'s own `sizes` names at that screen, its first matching condition read through `matchMedia` and its length resolved on a probe (± 1; the build compared its own formula only); the file asked for is the smallest candidate at or above it at density 1 (`currentSrc`'s `w=`: 640, 640, 828, 1080, 750, 828, 1080). From 1024: the cover's x is the header logo's (± 1); the `<h1>`'s x ≥ the cover's right edge + 23; the name block's `<header>` top is the cover's (± 1), and the `<h1>` 24 ± 1 below it. Below 1024: the cover at x 0 and the `<h1>` under it | `aspect-cover` → `h-80`; drop `lg:col-span-8`; drop `lg:px-l`; drop `lg:pt-0`; `sizes` naming 1060px where the box is 984 |
| `salon-page.spec.ts`, first screen | At 1024×768, 1280×800 and 1366×768 the `<h1>`, the rating and the panel's « Réserver » are inside the viewport, at scroll 0 | Move the rail after the sections |
| `salon-page.spec.ts`, sticky | At 1280×800 and 1024×768, scrolled to « Avis » and to « Questions fréquentes » (scroll > 400), the panel's top is 24 ± 1 and `elementFromPoint` at « Réserver »'s centre is that link. Nothing is asserted at the very end, where the panel rides up | Drop `sticky` |
| `salon-page.spec.ts`, no jump | At 320×568, 844×390 and 1280×800, after load and the favourites read, `scrollY === 0` and focus is on `<body>`. At 1280 only the focus can fail, since the heart is on screen | Revert the guard |
| `salon-page.spec.ts`, the bar at the end | At 390×844 and 320×568, scrolled to the end, the bar ends above the footer and every footer link, « Instagram » among them, answers `elementFromPoint` at its centre | The bar back to `fixed inset-x-0` |
| `salon-page.spec.ts`, the bar mid-page | At 390×844 and 320×568, scrolled to « Avis » (scroll > the screen), the bar's foot is the screen's foot (± 0.5) and its « Réserver » answers | Drop `sticky` (the bar falls to the page's end) |
| `salon-page.spec.ts`, the toast against the bar | At 390×844 and 320×568, after a press on the heart (favourites answered in the browser, as `site-look.spec.ts` does for « Carte »), « Annuler » showing, the pill ends above the bar and a press 1 px inside « Réserver »'s top-left corner lands on it | Drop `aboveFloatingControl` |
| `salon-page.spec.ts`, the toast at doubled text (since the fix stage) | At 320×568 and 360×640 with Chrome's font setting at 32 px (the root read back at 32 px, the bar over 100 tall): the pill ends above the bar, and a press 1 px inside « Réserver »'s top-left corner lands on it | The px lift back |
| `salon-page.spec.ts`, focus under the bar | At 390×844, 320×568 and 1023×768, a Tab walk from the top to the footer, which has to reach « Faut-il payer un acompte ? »: no focused control outside the bar has a pixel under it. Since the fix stage the map is mounted first and the walk must start at « Aller au contenu » and reach the map's controls | The clearance emptied; the sections' clearance dropped; the map not mounted; the start not put back |
| `salon-page.spec.ts`, SEO unchanged | `/beaute-divine`'s `<h1>` text, `<title>`, canonical, meta description, `og:image`, every JSON-LD block and the `<h2>` list equal `salon-seo-before.json`, read from `57b252a8` (whose `web/` is `b0995489`'s) against the stub before any edit; since the fix stage, every `<meta>` and every canonical or alternate link too; one `<h1>` | Change a word of the `<h1>`; change `og:title` |
| `salon-page.spec.ts`, a review's reading width (since the fix stage) | At 1920×1080 a review's text is at most 720 wide, in a card wider than 760 | Drop `max-w-content` |
| `type-overflow.spec.ts`, new | At 320, 1024 and 1280, the stub salon renamed in the page to « Institut de beauté et coiffure afro Excellence Riviera Palmeraie »: the name takes more than one line, « ✔ Vérifié » one line, and nothing scrolls sideways | Drop `flex-wrap` |
| `provider.spec.ts`, new | At 1280×800 exactly one displayed « Réserver » link, the panel's (two before) | Drop `lg:hidden` |
| `pro.spec.ts`, the go-live test | Added: no `main a[href$="/reserver"]` on the preview | Drop `disabled={preview}` |
| `tap-targets.spec.ts`, new | At 390 both « Réserver » (hero and bar), at 1280 the panel's « Réserver », « Appeler » and « WhatsApp », are at least 48 tall | Remove `min-h-12` from `BookingCta`'s link; from the panel's two links |
| `axe.spec.ts:151`, `focus`, `controls-shape`, `slow-phone`, `account`, `redirects`, `served-html`, `store-linked-pages` | Existing; green in the full run, no change | — |
| Not added | A no-photo salon in the stub. A new slug changes `served-html`'s and `provider`'s counts, as B11.3 found; the unit test holds that path and A2's measurement saw it | — |

**Watched red (the record).** On 2026-11-06, on the build's committed tree (`9d0f4c67`): each mutation on its own fresh `git archive` of `web/` in scratch, `node_modules` cloned from the branch (the same lockfile), the mutation applied by exact replacement (a replacement that matched nothing would have voided the run), only the guarding test run, the copy deleted after. Vitest with `TZ=UTC`; Playwright one run at a time on its own ports, each with its own `next build`. Every guard went red on its own assertion, read in the log, not on a build or syntax error. The driver and the logs are scratch (`b116/mutate.py`, `b116/mutations/`), never committed.

| # | Mutation | Test run | Red? What it said |
|---|---|---|---|
| U1 | `aspect-cover` off the cover's box | `hero-cover.test.tsx` | Red: the box's classes lack `aspect-cover` |
| U2 | `object-subject` moved from the cover to the logo | `hero-cover.test.tsx` | Red: the cover lacks `object-subject` |
| U3 | `object-subject` off the cover | `hero-cover.test.tsx` | Red: the same |
| U4 | `COVER_SIZES` with `60vw` in place of `calc(66.67vw - 40px)` | `salon-page.test.tsx`, the srcset | Red: nine widths, 384w among them |
| U5 | `COVER_SIZES` with `calc(100vw - 0px)`, no bare `vw` | the same | Red: sixteen widths from 16w |
| U6 | `priority` off the cover | the same | Red: no `fetchpriority="high"` |
| U7 | `cover: '16 / 9'` | `tokens.theme-pin.test.ts`, the cover's test | Red: `'16 / 9'` is not `'3 / 2'` |
| U8 | the `cover` key removed | the same | Red: `undefined` |
| U9 | `disabled={preview}` off the hero's « Réserver » | `salon-page.test.tsx`, the preview | Red, both tests: no disabled button, and a `/reserver` link |
| U10 | the `called` guard removed (the old effect) | `salon-page.test.tsx`, the heart on load | Red: the heart has the focus |
| U10b | none: the control that must stay green | `consumer-optimistic-revert.test.tsx` | **Green**, 34 of 34: focus still comes back after a failed call |
| U11 | the rail moved after the sections | `salon-page.test.tsx`, the order | Red: « Services & tarifs » before the `<h1>` |
| U12 | the bar moved out of `main` | the same | Red: `main`'s last child has no « Réserver » |
| U13 | `lg:col-start-9` off the rail | `salon-page.test.tsx`, no photo | Red |
| U14 | `aboveFloatingControl` off the heart's toast | `salon-page.test.tsx`, the toast | Red: no `bottom-xxxl` |
| U15 | `Math.random` in the photo's grain | `test-photo.test.ts` | Red: the pinned hash moved |
| U16 | the photo 2000 wide | `test-photo.test.ts` | Red: 2000 < 2048 |
| E1 | `object-subject` off the cover | `site-look`, « cover is at 50% 20% » | Red at 390, 820, 1280: `50% 50%` |
| E2 | `aspect-cover` → `h-80` | `site-look`, the cover's box | Red at all seven widths: 320×320, ratio off by 0.5 |
| E3 | `lg:col-span-8` off the cover | the same | Red at 1024, 1280, 1920: drawn 59 wide where `sizes` names 643 (1024); green below `lg`, where the class does nothing |
| E4 | `lg:px-l` off `main` | the same | Red at 1024, 1280, 1920: drawn 32 px wider than `sizes` names |
| E5 | `lg:pt-0` off the name block | the same | Red at 1024, 1280, 1920: the `<h1>` 48 below the photo's top, not 24 |
| E6 | the rail moved after the sections | `salon-page`, first screen | Red at 1280×800 and 1366×768: the panel's « Réserver » ends at 836 and 874. Green at 1024×768, where the rail then sits under the shorter cover and still ends on the screen |
| E7 | `sticky` off the panel | `salon-page`, sticky | Red, all four: the panel's top at −2009 and −2780 |
| E8 | the `called` guard removed | `salon-page`, no jump | Red, all three: scrolled 366 at 320×568 and 757 at 844×390 (317 and 454 on `main`; the taller cover puts the heart lower), and the focus on the heart at 1280×800 |
| E9 | the bar back to `fixed inset-x-0 bottom-0` | `salon-page`, the bar at the end | Red at both: the bar's foot at 844 and 568, below the footer's top |
| E9b | the same, with the test's first assertion taken out of the copy | the same | Red at both on the links alone: « Instagram » does not answer |
| E10 | `sticky` off the bar | `salon-page`, the bar mid-page | Red at both: the bar's foot at 1599 and 1493, off the screen |
| E11 | `aboveFloatingControl` off the heart's toast | `salon-page`, the toast against the bar | Red at both: the pill ends at 820 (the bar from 779) and 544 (from 503) |
| E11b | the same, with the test's pill assertion taken out of the copy | the same | Red at 320: « Annuler » takes « Réserver »'s corner. Green at 390, where it ends 0.5 px short, as A2 measured |
| E12 | `CLEAR_OF_BAR` emptied | `salon-page`, focus under the bar | Red at all three: « Quels sont les tarifs… » 48 px under the bar at 390, « Comment réserver… » 63.7 at 320 |
| E13 | « Salon » added before the name in the `<h1>` | `salon-page`, SEO | Red: `h1` « Salon Beauté Divine✔ Vérifié » |
| E14 | `flex-wrap` off the `<h1>` | `type-overflow`, a long name | Red at 320, 1024, 1280: « ✔ Vérifié » on two lines |
| E15 | `lg:hidden` off the hero's « Réserver » | `provider`, one « Réserver » | Red: two at 1280 |
| E16 | `disabled={preview}` off the hero's « Réserver » | `pro`, the go-live test | Red: one `/reserver` link in the preview |
| E17 | `min-h-12` off `BookingCta`'s link | `tap-targets`, the salon page | Red: « Réserver » 36 tall |
| E18 | `min-h-12` off the panel's two links | the same | Red: « Appeler » 22 tall |

The rows above ran on `9d0f4c67`, when the toast's lift was `aboveFloatingControl` and the clearance was the constant `CLEAR_OF_BAR`.

**Watched red after the reviews (the fix stage, 2026-11-06),** on `9f3e337c` (`02955881` after it changes one comment) by the same method (driver `b116/mutate2.py`, logs in `b116/mutations2/`, scratch):

| # | Mutation | Test run | Red? What it said |
|---|---|---|---|
| F1u | the px lift back on the heart's toast (`aboveFloatingControl`) | `salon-page.test.tsx`, the toast | Red: no `bottom-20` |
| F1 | the same | `salon-page`, the toast at doubled text | Red at both: the pill ends at 488 where the bar starts at 455 (320×568), and at 560 against 527 (360×640) |
| F1b | the same, with the test's pill assertion taken out of the copy | the same | Red at both on the corner press alone: it does not land on « Réserver » |
| F2 | the sections column's clearance dropped (the map is in it) | `salon-page`, focus under the bar | Red at all three, the map's controls among the offenders: « Map » 65 px under the bar, « Toggle attribution » 24 and « MapLibre » 14, each its whole height, beside the gallery photo and the FAQ's questions |
| F2b | the test's map mount taken out of the copy (the build's walk) | the same | Red at all three: « the walk never reached the map », none of its four controls among the stops |
| F2c | the test's sentinel taken out of the copy | the same | Red at all three: the walk started at « Map », not « Aller au contenu » |
| F3 | `COVER_SIZES` naming `1060px` from 1536 | `site-look`, the cover's box | Red at 1920, the one width that condition reaches: « drawn 984 wide, « (min-width: 1536px) 1060px » names 1060 »; green at the other six |
| F4 | `max-w-content` off a review's text | `salon-page`, reading width | Red: the review 920 wide |
| F5 | `og:title` given a trailing « · » | `salon-page`, SEO | Red: `og:title` and `twitter:title` differ in the `meta` list, every other key equal |
| L1 | `scroll-mb-[96px]` in the sections' `className` | ESLint on `ProviderView.tsx` | Red: `no-arbitrary-value` |
| L2 | `scroll-mb-fabb` there | the same | Red: `no-custom-classname` |
| L1c | `scroll-mb-[96px]` in `1ca5664e`'s constant | the same, on `1ca5664e` | **Green**, exit 0: the control; ESLint did not read the constant |
| L2c | `scroll-mb-fabb` in that constant | the same | **Green**, exit 0 |
| G | `git check-ignore` on `web/p1.jpg`, `web/tool/salon-test-photo.jpg`, `web/tests/e2e/p1.jpeg` and `web/IMG_0001.JPG` | detached worktrees of `1ca5664e` and `9f3e337c`, removed after | None ignored on `1ca5664e`, where only `web/tool/out/…` was; all four on `9f3e337c`; a PNG under `web/public/` on neither |

**Also:** the five pages' gate (§1.7) with its controls; `tsc`, ESLint with `--max-warnings=0`, `gen:api` with no drift, `next build`; the Lighthouse runs of §1.9. Full suites run one at a time, never in parallel.

**What these cannot see** (direction §12): no screenshot harness exists, so before-and-after pictures at 360, 768, 1440 and 1920 (and this spec's 320, 390, 820, 1280) are looked at, using the generated test photo only. The private sheets with stand-ins and demo rooms went to the owner only and never go into the PR. 768 was not shot yet.

### 1.11 Rollout

- **Branch:** `feat/web-salon-cover`, cut from #737's tip `57b252a8` (by the local ref, `origin/feat/web-swiss-cards` is `57b252a8`; nothing was fetched). Commits authored as the owner, conventional, no tool attribution.
- **The spec first, in its own docs-only commit,** then the build on the same branch, in its own commits (§1.10's record names them).
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
- « Réserver » becomes 48 px tall, so the phone bar grows from 53 to 65 px and stops above the footer, because fixed it would hide the footer's last link. The page is 65 px longer than today on a common phone. At the very end of a page the bar sits at the top of a common phone's screen, and on a small phone it has left the screen: about 190–245 px of scrolling up gets « Réserver » back. **Incomplete, found by the review:** that range holds for upright phones only; see the second list.
- With the browser's text at double size, « Ajouté aux favoris » still covers the top of « Réserver », and presses go through to it. **Wrong, found by the review:** that held at 390 only. At 320 and 360 « Annuler » covered a corner of « Réserver », and a press there undid the favourite. Fixed since (§1.4): the message now ends above the bar at doubled text too, so this cost is gone. The owner hears it with the PR.
- CI cannot check this PR until #737 merges; the full checks run locally first. Two deploys, each on the owner's word.
- Found, and possibly waiting for Apple's decision: reached with the Tab key, three controls hide completely under the bottom bar, probably already today.

**Measured or inferred, and not put in these words, so the answers do not cover them.** They go to the owner with the PR, for their word at the merge:
- From 1006 to 1023 px wide on a 768-tall screen, the bar runs over the bottom of the salon's logo (cosmetic).
- Found and fixed by the build: reached with the Tab key, a control near the screen's foot no longer goes under the bottom bar on a phone; it stops 96 px above the foot. With the browser's text at double size the bar is 113 px tall, and up to 19 px of the control can still sit under it, never all of it (§1.4). The fix uses a Tailwind form new to the code, a token on every element inside the page's two columns.
- On this page the `<h1>` does not start on the logo's x, the sections do not hang their headings beside the rail, and the sections' text starts at x 40 where the cover starts at 24 (WEB-SYSTEM §16's two exceptions, until B11.4's sections).
- A cover that fails to load is a grey block with Chromium's broken-image mark and the logo, with no letter.
- At the very end of a page on a computer, the booking box rides up with the rail and is only partly on screen (its top at −113 at 1280); « Réserver » still answers. At 1366×768 its « Réserver » has left the screen there, and with the browser's text at double size the whole box has, at 1024, 1280, 1366 and 1440; the same today (measured by the review).
- At the very end of a page, on screens the questions did not name, the bar's « Réserver » comes back only after scrolling up 580 px on a phone held sideways (844×390), 501 px on a 1280×800 computer at 200% zoom (640×400) and 263 px in a 1023×768 window; on upright phones, 185 px at 360×640 and 243 px at 320×568, inside the range put to the owner. Today's fixed bar never leaves the screen (§1.4).
- Found and fixed after the build: with the browser's text at double size the favourite message stood over the bottom bar, and on 320 and 360 phones over a corner of « Réserver », where a press undid the favourite. It now rises with the text (§1.4).
- At 1024 the gallery tiles get narrower than today, 198 against 209.
- Through a computer at 200% zoom, the photo fills the first screen (inferred).

### 1.14 Open items

- **The owner:** sign off the plan of the four « Carte » fixes before they join this branch (BACKLOG 91); give the word for each merge and deploy, after Apple's decision.
- **The owner:** installing Playwright's WebKit 2311 and Firefox 1532 (the machine has 2248 and 1509) is a download and needs their word; until then WebKit and Gecko are UNVERIFIED, focus under the bar included.
- **The Gate stage:** the five pages' gate on the branch as it will merge, since the « Carte » fixes join it, with condition 3 as amended and read by the kept rules' order (§1.7); `tokens.mirror` confirmed blind to `extend`. Done since: the review ran conditions 1–5 on `1ca5664e` and all held, and the fix stage ran 3 and 5 again on its own tree (§1.18). The focus fix's rule sits in `@media not all and (min-width: 1024px)`, not « a `max-width` query » as the build wrote, and the condition allows it. `.pb-xxl`'s removal was read by the review with Tailwind's extractor and in the built output (§1.7). The page-scoped focus fix holds at normal text (§1.4). **The gate on `1933a88b`, 2026-11-06,** measured §1.9's LCP table, and ran conditions 1–5 against `57b252a8`, each tree from a fresh `git archive`: all five held. The closure is the same 56 files with none of the 24 changed `web/` files; words, links and `class` attributes are identical; the decoded payload is identical; the 582 kept CSS rules are in order, with the same two removed and eight added; 12 scripts per page, the gzipped sum −2 to +1 B; 0 computed-style differences over 1,737,926 property reads, with identical PNG bytes, 10 of 10. That run is not the branch as it will merge, because the « Carte » fixes have not joined it.
- **The owner, with the PR:** the costs corrected in §1.13: the toast's sentence was wrong and its cost is fixed; the bar's end on a phone held sideways, at 200% zoom and in a 1023-wide window; the booking box at the very end at 1366 and at doubled text.
- **For the « Carte » fixes' plan (BACKLOG 91):** `Toast`'s rem lift, `aboveBookingBar`, is there for its first cost, the toast over « Carte » at doubled text. This branch does not change « Carte »'s lift.
- **Not shot yet:** any width at 768, a six-photo gallery (the stub salon has one), the install banner on this page with a store URL, the owner's preview in a browser, real phones and tablets.
- **Still open after the merge:** B11.3's line on a room on the salon page's cover stays open until a salon is public, and the first real salon's cover is looked at on the live site, because a generator's framing and a demo room are not a salon's photos.
- **The app** (B12.13): its comment « the website's `h-56` on phones » (`provider_detail_screen.dart:1590`) goes stale when this merges; the app keeps 224 dp, centred, until after Apple's decision.

### 1.15 Definition of done

- [x] `tsc`, ESLint `--max-warnings=0`, `gen:api` with no drift, vitest, `next build`, Playwright, axe green; no budget raised. *(Locally on the build, 2026-11-06: vitest 203 files, 2672 tests; the whole Playwright suite, 585 tests, axe among them. Again on the fix stage's tree: on `02955881`, `tsc`, `next lint` clean, `gen:api` with no drift, vitest 203 files and 2672 tests, the whole Playwright suite once, 588 tests (three new), all green. And in the gate on `1933a88b`, 2026-11-06, from a fresh `git archive`, one suite at a time: the same, 203 files and 2,672 tests, 588 Playwright tests with 0 unexpected and 0 flaky, Lighthouse CI's three URLs within their budgets with its upload left out, and the backend's and the app's tests that read docs. CI cannot run until #737 merges, §1.11.)*
- [x] Every new guard of §1.10 watched red on a copy of committed work, recorded. *(§1.10's record.)*
- [x] Tokens only (closed theme, no arbitrary value); 48 px targets; visible focus; heading order; four states. *(One arbitrary variant with a token value, `max-lg:[&_*]:scroll-mb-fab`, written inline so ESLint reads it, recorded in WEB-SYSTEM §16. The toast's lift, `bottom-20`, is an inset from `defaultTheme.spacing`, open by design and in rem, as the bar is.)*
- [x] SEO checks of §1.8 green: `<h1>`, canonical, JSON-LD unchanged.
- [ ] The five pages' gate: conditions 1–5, condition 3 as amended in §1.7, with controls. *(All five held on `1ca5664e`, run by the review; 3 and 5 again on the fix stage's tree; to run once more on the branch as it will merge.)*
- [x] §1.9's table filled from real runs, the LCP element named. *(2026-11-06, `1933a88b` against `57b252a8`, 50 runs; the cover `<img>` in all 50.)*
- [ ] Pictures with the generated test photo only, looked at; nothing private in the PR.
- [ ] This spec, WEB-SYSTEM §16, the direction, BACKLOG, the README index and the roadmap entry true at the merge.
- [ ] Feature branch, PR stacked on #737, CI green after the retarget, no tool attribution, merged on the owner's word.

### 1.16 What this PR writes in BACKLOG, word for word

Each body below is in `docs/BACKLOG.md` exactly once, character for character. B11.3, B11.4, B12.13 and decisions 91, 92 and 94 are **appended to**, so what #737 wrote there stays whole (web-swiss-cards.md §15 mirrors it).

- **Decisions, group heading**, after decision 94: « **The salon page's cover in 3:2, B11.4 brought forward (B11.4)** — asked on 2026-11-05 with four private sheets of pictures, and answered the same evening (`web-swiss-salon.md` §1.12, §1.13). **On the record with the questions, not asked:** « Réserver » becomes 48 px tall, so the phone bar grows from 53 to 65 px and stops above the footer, as « Carte » does, because fixed it would hide the footer's last link; the page is 65 px longer than today on a common phone; at the very end of a page the bar sits at the top of a common phone's screen, and on a small phone it has left the screen, so « Réserver » comes back after scrolling up about 190–245 px; with the browser's text at double size « Ajouté aux favoris » still covers the top of « Réserver », and presses go through to it. »
- **Decisions, group heading**, at its end (the fix stage, after the build's review; the body above stays as the owner read it): « **Corrected after the build's review (2026-11-06), for your word with the PR:** the sentence on double-size text was measured on a 390 phone only. On 320 and 360 phones « Annuler » covered a corner of « Réserver », so a press there undid the favourite; the message now rises with the text and ends above the bar, so that cost is gone. And « about 190–245 px » holds for upright phones only: at the very end of a page « Réserver » comes back after scrolling up 580 px on a phone held sideways, 501 px on a 1280×800 computer at 200% zoom and 263 px in a 1023×768 window, where today's fixed bar never leaves the screen. »
- **Decision 95**: « 95. On a computer, where does the salon's name go? [B11.4] — ✅ **Answered (2026-11-05), from pictures: « Beside photo, full width »,** the recommendation, over « Beside the photo, in today's narrower page » and « Under the photo, as today ». From `lg` the page takes the site's container: the cover in columns 1–8 at 3:2, and beside it the name, the rating and the booking box, which alone stays in view while people read (web-swiss-direction §7.6). **Put to you with the question:** on big screens the service list and the gallery get wider, lists up to 952 px on a 1920 screen, and gallery photos are cut a little more; two style rules leave the site's shared styles, which only this page used and the five pages Apple reviews never did; in your Pro preview the notice at the top stays narrower than the page. »
- **Decision 96**: « 96. Where is the 3:2 cover cut? [B11.4] — ✅ **Answered (2026-11-05), from pictures: « 20%, as the cards »,** the recommendation, over « Centre, on the cover only » and « 35%, on the cover only ». One token, `object-subject`, 50% 20%, on the cover and the cards, as decision 89. **Put to you with the question:** faces and the fade stay whole and a tall bun keeps its lower part; rooms show their upper half, ceiling lights, mirrors and the tops of the stations, with the chairs cut, and a plain room shows mostly wall. The first real salon's cover still gets looked at on the live site (B11.3). »
- **Decision 97**: « 97. On phones, what shape? [B11.4, B12.13] — ✅ **Answered (2026-11-05), from pictures: « 3:2, as on computer »,** the recommendation, over « Keep today's phone band (224 px) ». One ratio and one crop on every screen. **Put to you with the question:** the photo is 36 px taller than today on a common phone and 11 px shorter on the smallest, and the name and « Réserver » stay on the first screen; a phone held sideways, or a computer window under 1024 px wide, shows the photo first, with the name just below the first screen and « Réserver » in the bar, where today a phone held sideways already opens 454 px down the page. The app keeps its 224 dp, centred, until after Apple's decision (B12.13). »
- **Decision 98**: « 98. Ship it how? [B11.4] — ✅ **Answered (2026-11-05): « Own update after #737 »,** the recommendation, over « Inside #737, as one update ». Its own branch, `feat/web-salon-cover`, cut from #737's tip, and its own PR stacked on #737, merged right after it; both wait for Apple's decision and your word, and each of the two deploys is on your word. **Put to you with the question:** the automatic checks cannot run on it until #737 merges and the PR is retargeted, so the full checks run locally first. »
- **Decision 91**, at its end: « **Those four, put to you afterwards in these words on 2026-11-05: answered « Fix them in the cover update ».** Their fixes are planned separately and join B11.4's cover branch (decision 98) once you sign off that plan. Until then nothing about them is fixed, and they stand as measured (`web-swiss-salon.md` §1.12). »
- **Decision 92**, at its end: « **That DPR 3 cost, put to you afterwards in these words on 2026-11-05: ✅ « Keep it ».** On a DPR 3 phone a landing whose first two salons have no photo still fetches one 1080–1200w file off-screen, from the third tile (`web-swiss-cards.md` §7). »
- **Decision 94**, at its end: « **The plan with pictures went to you on 2026-11-05, and you answered it the same evening: decisions 95–98.** »
- **B11.3**, at its end: « **The cover's new shape is decided (decisions 95–98, `web-swiss-salon.md` §1):** the line above on a room on the salon page's cover stays open until a salon is public, and is read on the first real salon's cover. »
- **B11.4**, at its end: « **The cover's shape, specified on 2026-11-06 (decisions 95–98):** `web-swiss-salon.md` §1, on its own branch, `feat/web-salon-cover`, stacked on #737, not built yet. It brings forward the `cover` token, the 3:2 cover at every width cut at `object-subject`, direction §7.6's layout from `lg` with only the booking box sticky, and exact `sizes`. It also fixes the focus jump above, the live « Réserver » in your preview, « Réserver », « Appeler » and « WhatsApp » under 48 px, the phone bar over the footer's last link, and the favourite message over « Réserver ». The four « Carte » fixes of decision 91 join that branch once you sign off their plan. **Still here after it:** Lighthouse budgets for the salon page, a landing and `/recherche`, with real bytes; `/recherche`'s hidden map on phones; the home page's off-screen photos; the `<h1>` and `<h2>` sizes of direction §5.3; the sections (hanging headings through `SiteSection`, `Faq` in the site look, flush left, the salon page in the full left-edge test, and until then the page's two exceptions in WEB-SYSTEM §16); square gallery tiles, review cards, map and review photos; gallery `sizes`; the hero's alt « Salon {name} »; a salon with no photo shown with its logo or letter; a failed cover's letter (today a grey block with Chromium's broken-image mark); focus hidden under the phone bar, if its fix needs global CSS; B12.5's description and `slow-phone.spec.ts:66`'s claim; B12.7's review photos; the parity gaps (in the app the cover opens the viewer and the heart sits on it); « ✔ Vérifié » inside the `<h1>`; the Pro preview's notice, which stays `max-w-5xl`. »
- **B11.4, built**, at its end, after the line above (reworded by the fix stage, so it no longer reads as if the « Still here » list were built): « **Built on 2026-11-06 on that branch, not merged:** everything this line brings forward and fixes (the « Still here after it » list stays), and the focus hidden under the phone bar is fixed on the page itself, with nothing set on `<html>`: on a phone, a control reached with the Tab key stops 96 px above the screen's foot, clear of the bar. With the browser's text at double size the bar is 113 px tall and up to 19 px of that control can still sit under it, never all of it (`web-swiss-salon.md` §1.4). **After three reviews the same day:** with the browser's text at double size the favourite message stood over the bar, and on 320 and 360 phones over a corner of « Réserver », so a press there undid the favourite; it now rises with the text and ends above the bar. **Found by the reviews, not this slice's, the same today:** « Itinéraire », a review's « Signaler », the map's zoom buttons and its « MapLibre » link are under 48 px; with the browser's text at double size a price range in the services makes the page scroll sideways on phones. **Measured on 2026-11-06 with the generated test photo:** the page loads as fast as before on phones, and a computer fetches a smaller file and shows the photo sooner (`web-swiss-salon.md` §1.9). Still to come before your word: the five store-linked pages' gate on the branch as it will merge; the pictures, with the generated test photo only; Safari and Firefox, never run on this code; your sign-off of the « Carte » fixes' plan. »
- **B12.13**, at its end: « **From B11.4's cover (decision 97):** the site's cover becomes 3:2 on phones too, so the comment « the website's `h-56` on phones » (`provider_detail_screen.dart:1590`) goes stale when `feat/web-salon-cover` merges. The app keeps its 224 dp, centred, until after Apple's decision; fix the comment with the crop. »

### 1.17 Where the plan was wrong at this branch's base

Read on `57b252a8`, 2026-11-06. Its `web/` and `mobile/` trees are the same as `b0995489`'s, where the plan read the code.
- The plan cuts this branch from `86d91f14`. #737 has moved on to `57b252a8`, which is `86d91f14` plus a merge of `main` (`5e3b3449`, #740, a legal manifest and a roadmap entry); `web-swiss-cards.md` is the same in both, so its line numbers held.
- The plan's list of `web-swiss-cards.md` lines to turn into history misses :1341 (decision 8's answer paragraph) and :1250–:1252 and :1325, where the never-put costs of « Carte » and the DPR 3 cost now have answers.
- « WEB-SYSTEM §15 rows 28 and 29 » for text size: row 28 is the tab strips. The rows on type in px are 29 and 31.
- `site-look.spec.ts:1031-1039`: the test runs :1029–:1040.
- The A2 raw files the plan cites (`b114/fix/raw/A2-*.json`) are no longer on disk; their numbers survive in the plan only.

### 1.18 Three reviews of the build, and what the fix stage did

On 2026-11-06 three reviews read `57b252a8..1ca5664e`: layout and accessibility; the five store-linked pages, the shared CSS, SEO and security; the docs, the tests and their truth. Each built its own `git archive` against the e2e stub, in Chromium, with every request off localhost aborted. None found a blocker. The fix stage checked each finding against the code, or watched it in a browser, before changing anything; none was refuted. Its commits: `c9c8b2a7` (the toast's rem lift, the clearance in the `className`s, the guards), `9f3e337c` (`jpeg-js` declared, every JPEG under `web/` ignored), `02955881` (a comment that spelt a bracketed class, which Tailwind turned into a rule, found by the gate below), and the docs commit that carries this section.

| Finding (review) | How it was checked | Outcome |
|---|---|---|
| **Major.** At doubled text « presses go through to « Réserver » » was false at 320 and 360: « Annuler » took a corner, and a press there undid the favourite (layout) | The px lift put back on a copy of `9f3e337c`: the pill ran into the 113 px bar at 320 and 360, and the corner press missed (F1, F1b) | **Fixed:** `Toast`'s `aboveBookingBar`, rem (§1.4); held at 320 and 360; the cost corrected in §1.3, §1.13, the roadmap entry and a line appended to BACKLOG's decision heading, for the owner with the PR |
| **Major.** The bar's end understated: 844×390, 640×400 and 1023×768 missing (docs) | Measured again by the fix stage on its own build (§1.4) | **Fixed** in §1.4 and §1.13, in the roadmap entry and in the appended BACKLOG line |
| **Major.** Three status lines still said « not built » (docs) | Read by grep | **Fixed:** the README's index row, the direction's status, BACKLOG's batch-11 row |
| **Major.** « `no-arbitrary-value` reads values and passes it » was false: ESLint never read `CLEAR_OF_BAR` (docs) | On `1ca5664e`'s constant, `scroll-mb-[96px]` and `scroll-mb-fabb` both passed ESLint (L1c, L2c) | **Fixed:** the class written in the two `className`s, where both fail (L1, L2); §1.4 and WEB-SYSTEM §16 corrected |
| **Minor.** The Tab walk never reached the map's controls (layout) | Without mounting the map, the walk's stops have none of them (F2b) | **Fixed:** the map is mounted first and the start put back at the top; the walk must reach four of its controls (F2, F2b, F2c) |
| **Minor.** « Never committed » rested on `/tool/out` alone (five pages) | `git check-ignore` on `1ca5664e`: `web/p1.jpg` not ignored | **Fixed:** `*.jpg`, `*.jpeg` and their capitals ignored under `web/` (G) |
| **Minor.** The cover test did not hold the width `sizes` names (docs) | `sizes` naming 1060 at 1920 fetches the same 1080w file as 984 | **Fixed:** the `<img>`'s `sizes` read through `matchMedia` and resolved on a probe (F3) |
| **Minor.** « six règles »; « a `max-width` query »; `.pb-xxl`'s CLI item open; « no global CSS » (docs) | The review's CSS diff and the fix stage's (§1.7) | **Fixed:** eight added rules with the toast's, `@media not all and (min-width: 1024px)`, the item closed, « nothing set on `<html>` » |
| **Minor.** The review text's reading width untested (docs) | No test names it | **Fixed:** an e2e at 1920 (F4) |
| **Minor.** B11.4's built line read as if the « Still here » list were built, and left out items (docs) | Read | **Fixed:** reworded, the pictures, WebKit and Gecko and the « Carte » plan added, §1.16 mirrored, `check-salon-16.py` run again |
| Nit. The `<aside>`'s role (layout) | Chromium's accessibility tree, read again by the fix stage at 1280: one `complementary` landmark, unnamed, beside `main`, `banner`, `contentinfo`, four `navigation` and the map's `region` | **Fixed** in §1.4 |
| Nit. The panel at the page's end at 1366 and at doubled text (layout) | Measured again by the fix stage (§1.4) | **Recorded** in §1.4 and §1.13 |
| Nit. The first arbitrary selector, and a px clearance under a rem bar (layout) | Read: `[&_*]` is the only one in `app`, `components` and `lib` | **Recorded** for §2: a named variant in `tailwind.config.ts` and a rem clearance; not built, because both change the shared stylesheet again and the clearance meets WCAG 2.4.11 at doubled text already |
| Nit. Targets under 48 px and a sideways scroll at doubled text, the same on #737's tip (layout) | Not measured again: outside this diff | **Recorded** in §1.1's out of scope and BACKLOG B11.4 |
| Nit. 185 and 243, not 188 and 244 (layout) | Measured again (§1.4) | **Corrected** |
| Nit. `static.py` cannot judge the amended condition 3 (five pages) | Its output on the fix stage's build (§1.7) | **Recorded** in §1.7: the kept rules' order is read instead |
| Nit. §1.14's media query and §1.7's planning-stage reading (five pages) | Read | **Fixed** |
| Nit. `jpeg-js` undeclared (five pages, docs) | `package.json` read | **Fixed:** `"jpeg-js": "0.4.4"`, the lockfile's root entry only |
| Nit. The SEO e2e read only `og:image` of the head's tags (five pages) | Read | **Fixed:** every `<meta>` and canonical or alternate link, read from a fresh build of `57b252a8`, whose other keys matched the committed file (F5) |
| Nit. Scratch paths cited as evidence (five pages) | Read | **Fixed:** « How to read this » says what they are; the numbers are in this spec |
| Nit. « 160px apart » in `provider.spec.ts` (docs) | §1.2's own numbers, 493 and 658 | **Fixed:** 165 |
| Nit. The status row said « written before any code » and « built » at once (docs) | Read | **Fixed** |
| Nit. `check-15b.py` exits 0 when its control fails (docs) | A scratch tool | **Recorded:** read its output, not its exit code |

**The five store-linked pages after the fix (measured (fix), on its builds of `9f3e337c` and `02955881`):** the import graph is the same 56 files as at `57b252a8`, and none of the 24 `web/` files this branch changes is in it, `Toast.tsx` included (`closure2.py`; its control from `app/[slug]/page.tsx` reaches 65 files, `Hero`, `FavoriteButton` and `siteGrid` among them). Against the review's build of `57b252a8`, with the same environment and stub port:
- **condition 1:** words, links and `class` attributes identical on all five, and so are the HTML's bytes (32,138, 60,128, 40,151, 34,427 and 49,960);
- **condition 2:** the decoded payload and everything outside it identical on all five, its controls as expected;
- **condition 3:** as in §1.7, eight rules added, two removed, the 582 kept in order;
- **condition 4:** 12 scripts a page on both sides. After UUIDs, hashes, module ids and minified names outside strings are normalised, all 12 are identical on the first build (`9f3e337c`). On the second (`02955881`, a comment's change from the first) 10 of 12 are; the other two, the chunks `5878` and `webpack`, are identical to the versions the review's build of `1ca5664e` produced, and the review showed both trees produce both versions, so this is build noise. Its three controls (two different chunks; one string changed; one word changed) were all caught;
- **condition 5:** 0 differences over 1,737,926 property reads and identical PNG bytes at 390 and 1280 on all five; its controls, 135 differences between two different pages and 0 for one page loaded twice, as expected.

Only 127.0.0.1 was contacted, and each page made its one 401 on `/api/me/notifications`, as on the base. B11.3's `static.py` still printed `static_ok False` on its condition-3 line, for the reason in §1.7.

**Not done here, and why:** the four « Carte » fixes (they wait for the owner's sign-off of their plan); a name on the `<aside>`; the named variant and the rem clearance (above); WebKit and Gecko (a download, the owner's word, §1.14).

---

## 2. The rest of S4 (not specified yet)

What stays in B11.4 is listed in §1.1. It is specified here, with its own questions and pictures, before it is built. Until then the salon page keeps the two exceptions recorded in WEB-SYSTEM §16.
