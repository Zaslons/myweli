# MyWeli — Module Map

**The product thesis, made explicit (2026-07-07):** MyWeli is a **YCLIENTS
replica for francophone Africa** — the same journal-centric module architecture
(YCLIENTS's own docs: *the appointment journal is the foundation; every module
attaches to the visit record*), adapted to the Ivorian market (mobile-first,
French, FCFA, communes, à domicile, WhatsApp, Mobile-Money no-custody) and
extended with the **marketplace/trust layer** YCLIENTS lacks (consumer
discovery, KYC, moderation, disputes), because MyWeli is a marketplace *and* a
salon SaaS, where YCLIENTS is SaaS with a marketplace bolted on (YPLACES).

This file is the **living module inventory**: the canonical module names, what
each contains, where it lives in the code, its status, and its phase. It is the
**vocabulary** for all planning — every design spec, ROADMAP entry, and PR
declares which module it belongs to.

| | |
|---|---|
| **Companion docs** | [PRD.md](PRD.md) (phases §7) · [ROADMAP.md](ROADMAP.md) (build state) · [design/README.md](design/README.md) (part specs) |
| **Per-module deep docs** | Each module gets `docs/modules/<slug>.md` — vision, YCLIENTS reference, full UX, data model, API, phasing — written **before** its build phase begins |
| **The full-depth rule** | Every module is developed **fully — every flow, every state, every detail, best-in-class UI/UX**. We take the time; no rushed slices inside a module's committed scope. Encoded in `myweli-dev-guardrails`. |

**Status legend:** 🟢 Built & live · 🟡 Partial · ⏳ Planned V2 · 🔮 Planned V3

---

## The map at a glance

| # | Module | Slug | YCLIENTS analog | Status |
|---|---|---|---|---|
| 1 | Journal & bookings | `journal` | Электронный журнал | 🟢 core built |
| 2 | Marketplace & online booking | `online-booking` | Онлайн-запись + YPLACES | 🟢 built |
| 3 | Services, team & media | `catalogue` | Услуги / Сотрудники / Ресурсы | 🟢 built (resources ⏳) |
| 4 | Client base (salon CRM) | `clients` | Клиентская база | 🟡 partial → ⏳ |
| 5 | Notifications & messaging | `notifications` | Уведомления | 🟢 core built |
| 6 | Marketing & campaigns | `marketing` | Рассылки / промо | ⏳ V2 |
| 7 | Loyalty, memberships & certificates | `loyalty` | Лояльность / абонементы / сертификаты | ⏳ V2 (pulled from V3) |
| 8 | Payments & deposits | `payments` | Прием платежей | 🟢 built (no-custody, by decision) |
| 9 | Finance & earnings | `finance` | Финансовый учет | 🟡 basic |
| 10 | Analytics & reports | `analytics` | Аналитика / конструктор отчетов | 🟡 basic |
| 11 | Team access (RBAC) | `access` | Пользователи и доступ | 🟡 owner-only → ⏳/🔮 |
| 12 | Payroll | `payroll` | Расчет зарплат | 🔮 V3 |
| 13 | Inventory | `inventory` | Складской учет | 🔮 V3 |
| 14 | Multi-location networks | `network` | Сети | 🔮 V3 |
| 15 | Trust & operations | `trust` | *(no YCLIENTS analog — marketplace-specific)* | 🟢 built |

**Cross-cutting foundations** (not modules — every module stands on them):
identity & auth (Google/Apple/email OTP, JWT + rotating refresh), the design
system ([design/DESIGN-STANDARDS.md](design/DESIGN-STANDARDS.md) +
[design/WEB-DESIGN-STANDARDS.md](design/WEB-DESIGN-STANDARDS.md), MyWeli brand),
the security model ([BACKEND.md](BACKEND.md) §3 + STRIDE §7), the API contract
([api/openapi.yaml](api/openapi.yaml)), and infra (Render · Vercel · R2 ·
Cloudflare · Resend · FCM).

**Not replicated (deliberately):** fiscal cash registers (Российские ККМ — a
Russian legal requirement, not a feature; revisit only if DGI/FNE e-invoicing
ever demands it), IP telephony (later luxury; WhatsApp is the CI channel),
1C/AmoCRM-style integrations (local equivalents when needed).

---

## 1. Journal & bookings — `journal` 🟢

**The core.** Everything attaches to the visit record, exactly as in YCLIENTS.

- **Scope:** appointment lifecycle (pending → confirmed → completed /
  cancelled / rejected / no-show), reschedule (role-aware), the slot engine
  (durations, buffers, breaks, working hours), manual booking by the salon,
  calendar + list views, double-booking protection (app-level + Postgres
  exact-start unique index + `btree_gist` duration-overlap exclusion).
- **Code:** `backend/routes/appointments/*`, `/providers/[id]/appointments`,
  `/availability`; app `screens/booking/`, `screens/appointments/`,
  `screens/provider/appointments/`, `screens/provider/calendar/`; web
  `/pro/rendez-vous`, consumer booking flow.
- **Gaps → phase:** waitlist ⏳ · group bookings ⏳ · recurring ⏳ ·
  a **desktop journal grid** (staff-column day view — YCLIENTS's signature
  screen) for the web pro dashboard ⏳.
- **Module doc:** `docs/modules/journal.md` *(to write)*.

## 2. Marketplace & online booking — `online-booking` 🟢

Our YPLACES — but consumer-first, which is MyWeli's edge.

- **Scope:** consumer discovery (search, categories with Ivorian taxonomy,
  commune filter, map), provider public pages (SEO slugs, sitemap, JSON-LD),
  the consumer booking funnel (app + web), favorites, reviews (post-completion,
  photos, reporting), à domicile (flag).
- **Code:** `backend/routes/providers/` (+ `by-slug`, `/sitemap/providers`,
  reviews, gallery, before-after), app `screens/home|providers|map|favorites|
  stories`, web public pages + booking funnel.
- **Gaps → phase:** « open now » ⏳ · AI ranking ⏳ · booking placement on
  Google Maps / socials (YCLIENTS puts its widget on Yandex Maps/2GIS/VK) ⏳.
- **Module doc:** `docs/modules/online-booking.md` *(to write)*.

## 3. Services, team & media — `catalogue` 🟢

- **Scope:** service catalogue (categories, prices « à partir de », durations),
  team (artists, specializations, assignment), availability (hours, breaks,
  buffers), media (gallery, before/after, R2 uploads via signed POST).
- **Code:** `backend/routes/providers/[id]/services|artists|availability|
  gallery|before-after`, `/uploads/sign`; app `screens/provider/services|
  artists|availability|photos`; web `/pro/catalogue|disponibilites|medias`.
- **Gaps → phase:** resources (rooms/equipment as bookable constraints) ⏳ ·
  per-artist service pricing 🔮.
- **Module doc:** `docs/modules/catalogue.md` *(to write)*.

## 4. Client base (salon CRM) — `clients` 🟡

YCLIENTS's Клиентская база — the salon's own view of its customers.

- **Today:** clients are visible **per booking only**; consumer-side visit
  history + auto-sync (verified phone) exists. The pro placeholder screen
  (`screens/provider/features/client_database_screen.dart`) is flag-hidden.
- **To build (⏳ V2):** salon client list (from completed visits), client card
  (visit history, total spend, notes), categories/tags, **client-data access
  audit** (both YCLIENTS and Booksy track staff reads of the client base —
  ships with `access`).
- **Module doc:** `docs/modules/clients.md` *(to write)*.

## 5. Notifications & messaging — `notifications` 🟢

- **Scope:** transactional notifications to both sides (booking lifecycle),
  reminders (24 h / 2 h cron), push (FCM), in-app notification center +
  preferences, and the **channel cascade** — YCLIENTS's каскадная отправка is
  exactly our WhatsApp → SMS fallback (`MessagingProvider` seam; Termii/WhatsApp
  gated on company registration).
- **Code:** `backend/routes/me/notifications|notification-preferences|devices`,
  `/internal/cron/reminders`, `/webhooks/messaging/status`; messaging + push
  seams in `backend/lib/src/`; app `screens/notifications/`.
- **Gaps → phase:** real FCM impl (account follow-up) 🟡 · WhatsApp ContentSid
  (post-Meta-verification) ⏳ · lifecycle/rebook nudges ⏳.
- **Module doc:** `docs/modules/notifications.md` *(to write)*.

## 6. Marketing & campaigns — `marketing` ⏳

- **Scope (V2):** bulk campaigns/broadcasts to the salon's client base
  (WhatsApp-first), promos/discounts, stories (consumer `screens/stories/`
  exists as a surface), client segments, birthday/win-back automations.
- **Depends on:** `clients` (segments need a client base), `notifications`
  (channels), company registration (WhatsApp/Termii).
- **Module doc:** `docs/modules/marketing.md` *(to write)*.

## 7. Loyalty, memberships & certificates — `loyalty` ⏳

The YPLACES retention thesis — already pulled forward from V3 to V2 in the PRD
(§2.6): the consumer stickiness comes from the retention machine.

- **Scope (V2):** loyalty cards/points, **abonnements** (memberships:
  prepaid visit packs, freezing, expiry), **gift certificates** (sale +
  redemption), promo credits — consumer wallet + pro configuration, cross-salon
  in the consumer account (the YPLACES aggregation edge).
- **Placeholder:** `screens/provider/features/loyalty_programs_screen.dart`.
- **Module doc:** `docs/modules/loyalty.md` *(to write)*.

## 8. Payments & deposits — `payments` 🟢

Deliberately different from YCLIENTS's online acquiring: **no-custody**
(decision, PRD OQ-1 — MyWeli never holds funds).

- **Scope:** deposit policy per salon (percentage, Mobile Money operator +
  number), screenshot-based deposit proof, deposit review in the booking
  lifecycle; balance settled at the salon.
- **Code:** `backend/routes/appointments/[id]/deposit|deposit-screenshot`,
  `/providers/[id]/deposit-policy`; app + web deposit flows;
  `screens/provider/settings/deposit_settings_screen.dart`.
- **Gaps → phase:** wallet / promo / referral credit ⏳ · tipping 🔮 · cards +
  transaction fees 🔮 (only if custody decision ever changes).
- **Module doc:** `docs/modules/payments.md` *(to write)*.

## 9. Finance & earnings — `finance` 🟡

- **Today:** pro earnings screen + dashboard revenue (`/providers/[id]/
  earnings|dashboard`), subscription tier derived server-side
  (`/me/subscription`, trial from `createdAt`).
- **To build:** commission tracking ⏳ · full финансовый учет (cash
  movements, P&L per salon) 🔮 — lands with `payroll`/`inventory` since they
  share the money model.
- **Module doc:** `docs/modules/finance.md` *(to write)*.

## 10. Analytics & reports — `analytics` 🟡

- **Today:** platform-level admin analytics (north-star + overview); pro
  dashboard basics (today, revenue).
- **To build:** salon KPIs (fill rate, retention/return rate, no-show rate,
  average ticket) ⏳/🔮 · report constructor (YCLIENTS's Конструктор отчетов)
  🔮 — the last mile of the replica.
- **Placeholder:** `screens/provider/features/reports_analytics_screen.dart`.
- **Module doc:** `docs/modules/analytics.md` *(to write)*.

## 11. Team access (RBAC) — `access` 🟡

Designed 2026-07-07 (chat), YCLIENTS-style: **preset roles seeding a
capability matrix**, per-user overrides exposed later.

- **Today:** one login per salon (the owner); `role` claim ∈ user/provider/
  admin + tenant ownership on every route; artists are records, not logins.
- **To build (⏳ V2 slice 1):** `provider_members` (provider_id, account_id,
  role_preset owner/manager/staff, artist_id?, status), email invitations,
  capability enforcement (`journal.all`, `journal.own`, `clients.view`,
  `catalogue.manage`, `finances.view`, `team.manage`, …) — roles resolved
  per-request (instant revocation), Specialist↔artist auto-link, owner-protected
  actions, client-data access audit. Staff seats = paid add-on.
  **(🔮 V3):** the per-user override matrix UI, accountant-type roles.
- **Module doc:** `docs/modules/access.md` *(to write — first in line)*.

## 12. Payroll — `payroll` 🔮

YCLIENTS's Расчет зарплат (30+ compensation rules). V3, gated on PMF; needs
`finance` + `access`. Placeholder: `payroll_calculation_screen.dart`.
**Module doc:** `docs/modules/payroll.md` *(to write at V3 approach)*.

## 13. Inventory — `inventory` 🔮

YCLIENTS's Складской учет (products, stock, write-offs tied to services,
multi-warehouse). V3, gated on PMF. Placeholder:
`inventory_management_screen.dart`.
**Module doc:** `docs/modules/inventory.md` *(to write at V3 approach)*.

## 14. Multi-location networks — `network` 🔮

YCLIENTS's Сети: shared clients/staff/catalogue/analytics across branches,
network-level users. The `access` membership model is built to extend here
(one account ↔ many salons). V3.
**Module doc:** `docs/modules/network.md` *(to write at V3 approach)*.

## 15. Trust & operations — `trust` 🟢

**No YCLIENTS analog** — this is the marketplace layer that makes MyWeli more
than a SaaS clone: consumers must be able to trust salons they've never met.

- **Scope:** provider KYC (submit → admin approve/reject, signed-GET docs),
  moderation (review reports, hide/restore), disputes (open + resolve, evidence,
  no money moves), admin console (suspend/restore/feature providers, ban/unban
  users, audit log on every mutation, Cloudflare-Access-gated).
- **Code:** `backend/routes/admin/*`, `/me/kyc`, `/reviews/[id]/report`;
  admin Flutter-web app (`main_admin.dart`) at admin.myweli.com.
- **Module doc:** `docs/modules/trust.md` *(to write)*.

---

## How this file is used

1. **Vocabulary** — ROADMAP entries, design specs, and PRs name their module
   (e.g. `feat(journal): …`, spec header `Module: access`).
2. **Per-module deep docs** — before a module's build phase starts, write
   `docs/modules/<slug>.md`: vision & YCLIENTS reference, complete UX (every
   flow/state/edge case, FR copy), data model, API contract slice, security
   (threat-model deltas), performance, tests, phased rollout. The design-spec
   rule (`design-spec-per-part`) then governs each slice *within* the module.
3. **The full-depth rule** — a module's committed scope ships complete: every
   flow, every state, every detail, best-in-class UI/UX, on all relevant
   surfaces (app, pro, web, admin). Taking longer is accepted; shipping a
   hollow module is not. (Phasing still applies **between** modules — V1→V3 —
   the rule is about depth *within* what we commit to.)
4. **Status upkeep** — when a module's status changes, update the table AND the
   module section here, in the same PR (like ROADMAP refresh).
