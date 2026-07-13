# Myweli Web — design & UX standards (canonical)

How the Myweli **web** UI looks and behaves — the web mirror of
[DESIGN-STANDARDS.md](DESIGN-STANDARDS.md). Consult this + the part's
`docs/design/web-<part>.md` spec **before designing or building any web page**.
Nothing should invent a color/size/pattern not defined here. Enforced by the
**`myweli-web-guardrails`** skill.

> Same brand as the apps — **minimalist monochrome**, color reserved for status +
> the single primary action. The web must feel like the same product as the
> Flutter apps, adapted to the browser + desktop.

## 1. Tokens — shared with the apps, never literals
The design tokens are **one source of truth**, exported from the Flutter theme to a
tokens file consumed by **Tailwind** (`tailwind.config` theme) + CSS variables.
Use the token, never a raw hex/px. Current values (keep in sync with
`mobile/lib/core/theme/`):

- **Color:** `primary #000000`; surfaces `surface`/`secondary`/`surfaceVariant`/`background`; text `textPrimary`/`Secondary`/`Tertiary`; `border`/`divider`; **semantic** `success`/`successLight #4A7C2A`/`error`/`warning #6B5B00`/`info #1A1A2E` (+ `*Light`). Status colors come from here — never `green`/`red` literals. Category accents only via the category token set (`categorySpa #5B6B4F`, `categoryBarber #6D5A4C`, `categorySalon #4F5B6B`).
- **Spacing:** 4 / 8 / 16 / 24 / 32 / 48 (`xs…xxl`). **Radius:** 4 / 8 / 12 / 16 / 24 (cards default = 16).
- **Type:** headline 32/28/24 (semibold), title 22/16/14 (medium), body 16/14/12, label. Map to Tailwind text scale; **no ad-hoc font sizes**.
- Only `transparent` / pure black|white (scrims) are acceptable raw literals.

## 2. Components — reuse before you build (`web/components/`)
Build a small shared library mirroring the app's: `Button` (primary/secondary/text;
loading), `TextField`, `Loading`, `EmptyState`, `ErrorState` (retry),
`Rating`/`StatusChip`, `ProviderCard`, `ServiceRow`, and **`AppInstallBanner` /
`OpenInAppButton`** (the standard install-push — see §7). Data-dense desktop (pro
dashboard) reuses an `AdminDataTable`-equivalent. Need something new? Add it as a
shared component, never a one-off inline.

## 3. UX rules (non-negotiable)
1. **Four states on every page/section:** loading · empty · error (+retry) · success.
2. **French copy** everywhere; **FCFA / phone / date** formatting; Ivorian taxonomy.
3. **Reuse the pattern** of the surrounding `web/` code (typed client, rendering
   rules, components) — don't invent a new shape.
4. **Plan the UX + sign-off first** for user-facing work (goal, flow, all states,
   edge cases, copy).
5. **Accessibility:** semantic HTML, ≥4.5:1 contrast (monochrome passes), labelled
   controls, keyboard-navigable, focus states, `alt` text, proper heading order.
6. **Performance:** meet the CWV budgets (WEB.md §7) — minimal public-page JS,
   optimised images.

## 4. Responsive & desktop (important for the pro dashboard)
- **Mobile-first** for public + consumer (most CI traffic is mobile browsers):
  single-column, thumb-friendly, fast.
- **Desktop-grade for the pro dashboard:** real breakpoints (not a stretched
  phone) — multi-pane agenda, dense tables, persistent nav, keyboard shortcuts,
  hover/right-click affordances. A salon runs this on a PC all day; it must feel
  like a desktop tool (the Planity bar).
- Standard breakpoints (Tailwind `sm/md/lg/xl`); design the layout per surface,
  don't just center a phone column.

## 5. French copy & locale
French throughout (labels, errors, empty/loading, SEO text); FCFA + Ivorian phone
formatting; CI service taxonomy (PRD Appendix A); commune-aware. Market facts
(communes, operators, currency, timezone) only via their seams, and times render
in **salon time**, never the browser's — see
[modules/multi-pays.md](../modules/multi-pays.md) §9 + [WEB.md §3](../WEB.md).

## 6. SEO / AEO / GEO presentation conventions (public pages)
- One `<h1>` = the page's core entity (salon name + commune; or "Coiffure à Cocody").
- **Answer-first**: a concise, extractable lead paragraph, then detail.
- **Structured data is part of the design**: every public page ships valid JSON-LD
  (LocalBusiness/Review/Service/**FAQPage**/Breadcrumb) — treat it as a first-class
  output, not an afterthought.
- Headings phrased as real user questions where natural; FAQ blocks on provider +
  landing pages. Keep the brand `Organization` entity + "À propos" page consistent.

## 7. The app-install push (standard pattern)
A recurring, **non-annoying** nudge to install/use the mobile app:
- **`AppInstallBanner`** — a dismissible top/bottom banner on public + consumer
  pages ("Réservez plus vite — téléchargez l'app", store links + deferred deep
  link). Remembers dismissal; never blocks content; one per session.
- **`OpenInAppButton`** — contextual ("Ouvrir dans l'app") on a provider/booking.
- After a successful web booking → a "continuez dans l'app" card (manage,
  reminders, rebook). Always token-styled; French; never a modal interstitial that
  hurts SEO/CWV.

## 8. Pre-build checklist (web UI)
- [ ] Read this + WEB.md + the part's `docs/design/web-<part>.md` spec.
- [ ] UX planned (states + copy) and **signed off**.
- [ ] Tokens only (no literal colors/sizes); shared components reused.
- [ ] Four states; French; formatters; responsive/desktop per surface.
- [ ] SEO/AEO/GEO (metadata + JSON-LD) for public pages; app-install push present.
- [ ] After: typecheck/lint/`next build`/tests green; Lighthouse budget met.

## 9. Consistency sweep (after web UI work)
From `web/`, these must not grow in `app/` + `components/` (use tokens instead):
```
grep -rEn "#[0-9a-fA-F]{3,6}" app components | grep -v styles/   # raw hex
grep -rEn "\b(text|bg|border)-(red|green|blue|amber|...)-[0-9]" app components  # raw Tailwind palette vs tokens
grep -rEn "fontSize|font-\[" app components                       # ad-hoc type
```
Keep raw color/size usage out of pages/components; everything goes through the
shared token theme.
