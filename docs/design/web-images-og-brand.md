# Web — image optimization + OG / brand assets

| | |
|---|---|
| **Part** | Web deployment-readiness #4 (public-web). |
| **Status** | Built. No backend change. |
| **Spec** | [public-web.md](public-web.md) · [WEB.md](../WEB.md) · [WEB-DESIGN-STANDARDS.md](WEB-DESIGN-STANDARDS.md). |

## 1. Goal & scope
Finish the web's performance + share/brand polish that was deferred to the
accounts phase (the `<img>` comments in `Hero`/`Gallery` literally say "wired at
the accounts phase"):

1. **`next/image` on public pages** — migrate the provider page's CDN images
   (`Hero`, `Gallery`, `BeforeAfter`) from `<img>` to `next/image` for CWV (lazy,
   responsive `srcset`, no layout shift). The hero is `priority` (LCP).
2. **CDN allowlist** — `next.config.mjs` `images.remotePatterns` for the R2
   public host (`cdn.myweli.com`), the R2 default (`**.r2.cloudflarestorage.com`),
   and the e2e stub host (`cdn.stub`).
3. **OG image** — `app/opengraph-image.tsx` (`next/og` `ImageResponse`,
   on-brand monochrome 1200×630) → auto-wires `og:image` + `twitter:image`
   site-wide (shares were previously blank).
4. **Brand assets** — `app/icon.svg` (favicon) + `public/logo.svg`; point the
   Organization JSON-LD `logo` at `/logo.svg` (it referenced a non-existent
   `/logo.png` → 404).

**Out of scope:** the **pro** authed images (`MediasClient`,
`ProAppointmentDetailClient`) stay `<img>` — they're noindex, dynamic, and mix in
blob previews where `next/image` adds no value. A real raster `logo.png` +
designed OG artwork can replace the generated/SVG ones later.

## 2. Design
On-brand monochrome (tokens: primary `#000`, secondary `#FFF`). OG = black field,
white "Myweli" wordmark + FR tagline "Réservation beauté & bien-être en Côte
d'Ivoire". Logo = the wordmark as SVG. No new colors/sizes.

## 3. Perf / SEO
`next/image` meets the CWV budget (responsive `srcset` + lazy + reserved space);
hero `priority`. OG/twitter image improves share CTR; the logo fixes the
Organization rich-result (was a 404). No JS added to public pages beyond the
image runtime.

## 4. Tests / rollout
Typecheck + lint + unit + e2e (provider page sections still render) + `next build`
(statically generates the OG image). No API/contract change → no drift. The real
CDN host is supplied via `R2_PUBLIC_BASE_URL` at deploy.
