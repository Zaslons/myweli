# Web M7.3d — pro Abonnement + Tableau de bord (revenue stats, G3)

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 + FR-PRO-SUB-001; closes parity gap **G3** ([web-parity-audit.md](web-parity-audit.md)). |
| **Mirrors** | the app's `/pro/subscription` (« Mon abonnement ») + `/pro/dashboard` revenue cards. |
| **Surface** | `web/app/pro/(dash)/abonnement` + enhanced `/pro` home + 2 pro-BFF GETs — **no backend change**. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built** — `/pro/abonnement` (read-only PRO-SUB) + revenue cards on `/pro` (G3 closed); 4 unit + 1 e2e. Profile nudge → 7.3e. |

## 1. Goal & app parity
Two pieces, both **read-only** over existing endpoints:
- **Abonnement** — show the salon's plan/trial (« Mon abonnement », PRO-SUB-001).
- **Tableau de bord (G3)** — add **revenue** (aujourd'hui + ce mois) to the `/pro`
  home, matching the app dashboard (web currently shows only counts).

## 2. Abonnement `/pro/abonnement` (read-only)
- Sidebar "Abonnement" → live. Authed gate as M7.0.
- **Statut** (from `GET /me/subscription` → `{tier,status,trialEndsAt,trialDaysLeft}`):
  trial → « Essai gratuit — {n} jour(s) restant(s) · Se termine le {date} »; else →
  « Essai terminé — offre Gratuite · Vous profitez de l'offre Découverte (gratuite) ».
- **Offre Pro** card mirroring the app: **70 000 FCFA/mois barré** + « Gratuit
  pendant 3 mois » + `proEntitlements` + ROI line («Un seul rendez-vous manqué
  évité paie le mois.») + **« Nous contacter »** (WhatsApp, prefilled "Bonjour
  Myweli, je souhaite passer à l'offre Pro."). Current free plan = `freeEntitlements`.
- Pricing/copy mirrored client-side in `lib/pro/subscription-plans.ts` (trialMonths
  3, anchor 70 000, entitlements, ROI) — same as the app's `subscription_plans.dart`.
- **No billing** (V1 = no payments — psychology/anchor only; `payments-no-custody`).

## 3. Tableau de bord (G3) — `/pro` home
Add to Aujourd'hui, from `GET /providers/{id}/dashboard` →
`{todayAppointments,pendingRequests,todayRevenue,weekRevenue,monthRevenue}`:
- **Revenus aujourd'hui** + **Revenus ce mois** cards (FCFA), alongside the existing
  à-confirmer/confirmés/total counts.
- **Deferred (flag):** the app's « Configurer mon profil » nudge → **7.3e** (it links
  to `/pro/profil`, which lands in 7.3e).

## 4. Data (no backend change)
- Pro BFF GETs (client passes its own `providerId` for dashboard; backend is
  owner-only): `GET /api/pro/subscription` → `/me/subscription`;
  `GET /api/pro/dashboard?providerId=` → `/providers/{pid}/dashboard`.
- Stats are **server-computed** (revenue from confirmed+completed) — the client
  only displays.

## 5. States
Abonnement: loading · error (+retry) · success. Dashboard cards: show "—" if the
stats fetch fails (don't block the bookings list — degrade gracefully).

## 6. Security
Pro httpOnly cookies + `callApiPro`; dashboard is owner-only server-side; no PII
beyond the caller's own salon. `/pro/*` `noindex`. WhatsApp number via env
(`NEXT_PUBLIC_MYWELI_WHATSAPP`, filled at the accounts phase).

## 7. Tests
- **Unit:** subscription status copy (`subscriptionStatusLabel(sub)`), pricing config.
- **e2e:** provider → `/pro/abonnement` shows the trial status + « Nous contacter »;
  `/pro` shows a **Revenus** card. Stub: `/me/subscription` + `/providers/{id}/dashboard`.

## 8. Open questions (proposed defaults)
- **OQ-7.3d-1** Abonnement = **read-only** PRO-SUB view (no billing) → default.
- **OQ-7.3d-2** « Nous contacter » = WhatsApp link via env number → default.
- **OQ-7.3d-3** G3 now = revenue cards; « Configurer mon profil » nudge → 7.3e → default.
