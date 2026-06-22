# Myweli — Product Requirements Document (PRD)

**Beauty, wellness & services booking platform for Côte d'Ivoire**
Platforms: iOS · Android · Web

| | |
|---|---|
| **Document owner** | Product (Myweli) |
| **Status** | Draft v1.0 |
| **Last updated** | 2026-06-20 |
| **Scope** | Full product vision, phased (V1 → V2 → V3) |
| **Monetization** | SaaS subscription (providers pay); Mobile Money used for deposits & in-app payment as product features, not as the primary revenue line |
| **Launch market** | Abidjan — 3-commune focus (Cocody, Marcory, Plateau) |
| **Current state** | Flutter consumer + pro apps with mock services; no backend; no payments; no notifications |

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Vision, strategy & positioning](#2-vision-strategy--positioning)
3. [Market context — Côte d'Ivoire](#3-market-context--côte-divoire)
4. [Goals, North Star & success metrics](#4-goals-north-star--success-metrics)
5. [Personas](#5-personas)
6. [Monetization & pricing](#6-monetization--pricing)
7. [Scope & phasing (V1 / V2 / V3)](#7-scope--phasing)
8. [Platform & technical strategy](#8-platform--technical-strategy)
9. [Functional requirements — Consumer apps](#9-functional-requirements--consumer-ios--android)
10. [Functional requirements — Provider (Pro) apps](#10-functional-requirements--provider-pro-apps)
11. [Functional requirements — Web surfaces](#11-functional-requirements--web-surfaces)
12. [Cross-cutting systems](#12-cross-cutting-systems)
13. [Data model](#13-data-model)
14. [Integrations](#14-integrations)
15. [Non-functional requirements](#15-non-functional-requirements)
16. [Trust, safety & verification](#16-trust-safety--verification)
17. [Analytics & instrumentation](#17-analytics--instrumentation)
18. [Compliance & legal (CI)](#18-compliance--legal-ci)
19. [Release plan & rollout](#19-release-plan--rollout)
20. [Risks & mitigations](#20-risks--mitigations)
21. [Open questions](#21-open-questions)
22. [Appendix A — Service taxonomy](#appendix-a--service-taxonomy-ci)
23. [Appendix B — Glossary](#appendix-b--glossary)

---

## 1. Executive summary

Myweli is a two-sided marketplace connecting Ivorian consumers with beauty, wellness, and grooming providers (salons, barbers, spas, nail bars, and independent "à domicile" freelancers), plus a business-management app ("Myweli Pro") that providers pay for via subscription.

The wedge is **not** "a booking app" — global incumbents (Fresha, Booksy) will eventually localize. The defensible position in Côte d'Ivoire is the combination of:

1. **Mobile Money–native deposits** (Wave, Orange Money, MTN MoMo, Moov) to kill the no-show problem that defines the market.
2. **WhatsApp-native communication** — meeting customers where booking already happens.
3. **"À domicile" (home service)** as a first-class model, not an afterthought — a segment global players will be slow to serve.
4. **Ivorian service taxonomy & pricing** (tresses, tissage, défrisage, dégradé, onglerie…) that feels native, not translated.
5. **Boots-on-the-ground supply onboarding** in dense commune clusters.

Revenue is a **SaaS subscription** charged to providers (tiered). Consumer use is free. Mobile Money deposits and payments are product features that reduce no-shows and increase trust; transaction fees are an optional later revenue lever, not the V1 model.

This PRD covers the full product across iOS, Android, and Web, phased so the team knows exactly what ships first.

---

## 2. Vision, strategy & positioning

### 2.1 Vision
> Make it as easy to book and pay for any appointment-based service in Côte d'Ivoire as it is to send money with Wave — starting with beauty and wellness, then expanding to every category that runs on reservations.

### 2.2 Long-term thesis
Beauty/wellness is the beachhead because it has high frequency (braids every 4–6 weeks, barber every 1–2 weeks), high no-show pain, and a young, smartphone-fluent customer base. Once the booking + deposit + reminder loop is proven, the same engine extends to any reservation business: tattoo, dentists & clinics, fitness/coaching, photographers, car wash & detailing, tailoring/couture, events.

### 2.3 Positioning statement
**For** urban Ivorians who book beauty & wellness services,
**Myweli is** a booking app that lets you discover trusted providers, reserve a slot, and lock it with a Mobile Money deposit,
**unlike** WhatsApp-only booking (no real calendar, no deposit, constant back-and-forth) or global apps (no Mobile Money, no home service, foreign service categories),
**because** it's built Mobile-Money-first, WhatsApp-aware, and around how Ivorians actually book.

### 2.4 Strategic principles
- **Liquidity over coverage.** Win 3 communes completely before adding a 4th.
- **Reduce no-shows first.** Every early feature decision is judged on "does this get the deposit paid and the customer to show up?"
- **The stylist's day, not the owner's dashboard.** The pro app must be usable by a stylist with one free hand between clients.
- **Offline-tolerant.** Bad signal is the norm, not the exception.
- **Don't become an ERP yet.** Resist building payroll/inventory/analytics before booking + payment + retention is proven.

### 2.5 Non-goals (explicitly out of scope for now)
- Full salon ERP (payroll, deep inventory, accounting) as a launch priority — deferred to V3 and gated on PMF.
- Markets outside Côte d'Ivoire — architecture should not preclude regional expansion, but no multi-currency/multi-country work in V1–V2.
- Card payment acquiring as a primary rail — Mobile Money first; cards are a low-priority secondary.
- A social network. Stories and reviews exist to drive bookings, not engagement for its own sake.

### 2.6 Product inspiration: YPLACES / YCLIENTS — and how Myweli goes further

Myweli is deliberately inspired by the **YCLIENTS** ecosystem (Russia/CIS) — the category-defining booking + business-management platform — and its consumer companion app **YPLACES**. The mapping is direct: **Myweli Pro ≈ YCLIENTS** (business side), **Myweli consumer ≈ YPLACES** (client side). We borrow the *ideas that made it sticky* and adapt them to Côte d'Ivoire, then go beyond. Inspired, not copied — and better.

**Borrowed from YPLACES (consumer):**
- A single **personal account** aggregating everything across every provider visited — visit history, bonus/loyalty cards, promos, memberships, certificates — not a per-salon silo.
- **Frictionless repeat booking & rescheduling** from history.
- **One-tap payment** with a remembered method + optional auto-pay.
- **Memberships/abonnements** (remaining visits + validity, renew in-app) and **gift certificates** bought in-app.
- **Auto-sync**: a booking the provider enters in its journal appears automatically in the client's app.

**Borrowed from YCLIENTS (pro):** the booking journal as operational heart, CRM/client base, loyalty & certificates, online-booking distribution, notifications, and (later) analytics/inventory/payroll.

**How Myweli is better / different (built for Abidjan, not Moscow):**

| YPLACES / YCLIENTS | Myweli |
|---|---|
| Card-linked one-click pay | **Mobile Money one-tap** (Wave/OM/MTN/Moov) — the actual rail |
| Prepayment optional | **Deposit-to-confirm native** — directly attacks the CI no-show problem |
| Push/SMS comms | **WhatsApp-native** comms where booking already lives |
| Shop-centric | **"À domicile" first-class** — pin + landmark + transport fee |
| Assumes good connectivity | **Offline-tolerant**, low-end-Android budget, small app |
| Russian service categories | **Ivorian taxonomy** (tresses, tissage, défrisage, dégradé, onglerie…) |
| Utilitarian discovery | **Stories/social-led discovery** + **referral-native** trust |
| Per-event booking | **Group/event bookings** (mariages, baptêmes) as a cultural edge |

**Strategic consequence (binding):** YPLACES proves the consumer stickiness comes from the *retention machine* (unified account, loyalty, memberships, one-tap pay, effortless rebooking). We therefore **pull loyalty, memberships, and gift certificates forward from V3 to V2** (on-thesis retention), while keeping back-office modules (inventory, payroll, deep analytics) at V3.

---

## 3. Market context — Côte d'Ivoire

This section is the "why" behind many requirements. Treat it as binding context.

### 3.1 Demand-side realities
- **Android-dominant, low-end devices.** Tecno/Infinix/Itel/entry Samsung; 2–4 GB RAM; Android 9–13. iOS is a single-digit minority (affluent, Abidjan). **Performance budget targets the low-end Android, not the iPhone.**
- **Expensive, intermittent data.** Offline-first behavior, image compression, and small install size are requirements, not optimizations.
- **WhatsApp is the default channel.** Booking, confirmations, and deposit screenshots already flow through WhatsApp. Compete by integrating, not replacing.
- **Trust via referral.** Word-of-mouth ("ma cousine m'a dit") closes more than star ratings. Referral mechanics are core growth, not a growth-hack add-on.
- **Address culture is descriptive, not numbered.** "Après la pharmacie Saint Jean, en face du maquis." GPS pin + landmark text both required; never rely on a street address alone.
- **Home service ("à domicile") is huge** — braids, makeup, nails, especially for working women, mothers, and event prep (mariages, baptêmes).

### 3.2 Payment landscape
- **Wave** — dominant, low/zero fee P2P, the UX benchmark.
- **Orange Money** — incumbent, broad reach.
- **MTN MoMo**, **Moov Money** — meaningful share.
- **Cards** — <10% in this category.
- **Cash** — still significant; the product must gracefully support "pay deposit online, balance in cash at the salon."
- **Aggregators** (CinetPay, PayDunya, Hub2, Semoa) let one integration cover all operators — strongly preferred over four direct integrations for V1.

### 3.3 Supply-side realities
- Salons run on WhatsApp + a paper "cahier de rendez-vous" (booking journal).
- Stylists are typically paid **commission (30–50%)**, not salary.
- The owner buys; the stylist must adopt. Onboarding is high-touch, in-person.
- Many top providers operate from Instagram, not a fixed shop (freelancers).

### 3.4 Competitive landscape

| Player | Model | Threat / lesson for Myweli |
|---|---|---|
| **Fresha** | Free for salons, monetizes payments | The real long-term threat. Free-forever pricing. Our defense: localize payments + WhatsApp + home service before they arrive. |
| **Booksy** | Per-stylist subscription | Validates the SaaS subscription model we're using; strong calendar UX to match. |
| **Mindbody** | Premium wellness SaaS (classes, memberships) | Roadmap reference for spa/wellness V3 (memberships, packages). |
| **GlossGenius / Vagaro / Square Appts** | SMB/solo tools | UX references for the solo/freelancer flow. |
| **Treatwell** | EU consumer marketplace | Marketplace + booking-page playbook. |
| **Wave** | Mobile Money | Not a competitor — the UX bar. Everything financial gets compared to "open → amount → send → done." |
| **GoBeauty (NG), Wadeely (EG), Salonika (KE)** | Local plays | Proof of regional appetite; none dominant; fragmentation = opportunity. |

**Conclusion:** Our moat is local execution (payments, WhatsApp, home service, taxonomy, supply ops), not features. The PRD prioritizes accordingly.

---

## 4. Goals, North Star & success metrics

### 4.1 North Star Metric
**Completed, paid appointments per week** (a booking that the customer attended and that was paid at least in part through Myweli). It captures both sides: real demand, real supply, real money, real retention.

### 4.2 Primary KPIs

| Layer | Metric | V1 target (first 90 days post-launch) |
|---|---|---|
| Liquidity | Completed appointments / week | 500+ across 3 communes |
| Supply | Active providers (≥1 booking in last 14 days) | 50+ |
| Supply quality | % providers verified (KYC) | ≥80% of active |
| Conversion | Search/profile-view → booking | ≥8% |
| No-show | No-show rate on deposit-backed bookings | <8% (vs. ~20–30% industry without deposits) |
| Retention (consumer) | 6-week rebooking rate | ≥30% |
| Retention (provider) | Monthly subscription churn | <6% / month |
| Monetization | Paying providers / active providers | ≥40% by day 90 |
| Reliability | Crash-free sessions | ≥99.5% |

### 4.3 Guardrail metrics
- Deposit dispute rate < 2% of deposit-backed bookings.
- WhatsApp/SMS reminder delivery rate ≥ 95%.
- p95 cold start < 3.5s on reference low-end Android.
- Off-platform leakage (providers pushing customers to pay outside) monitored via post-appointment survey.

---

## 5. Personas

**P1 — Aïcha, 27, consumer (core).** Plateau office worker. Gets braids every 6 weeks, manicure monthly. Books on WhatsApp today, pays deposits with Wave. Android (Infinix). Wants: see who's good and available, lock a slot without 20 messages, not lose her deposit unfairly.

**P2 — Fatou, 22, student / event consumer.** Books makeup + tresses for a wedding party of 4. Needs group booking, home service, clear total. Price-sensitive, promo-driven.

**P3 — Mariam, 41, salon owner (pro buyer).** Cocody salon, 2 chairs, 3 employed stylists. Loses money to no-shows and last-minute cancellations. Keeps a paper cahier. Wants fewer no-shows, a clean schedule, and to look professional. Will pay a subscription **if** it demonstrably reduces no-shows and fills empty slots.

**P4 — Koffi, 29, employed stylist (pro user, not buyer).** Paid 40% commission. Lives in the appointment list between clients. Needs: today's schedule at a glance, who's next, mark complete, his own earnings. Low patience for complex UI.

**P5 — Awa, 34, freelance "à domicile" provider.** No shop; works from Instagram. Travels to clients. Needs: manage her own calendar, take deposits to protect against no-shows and wasted travel, get the client's location (pin + landmark), look legit via a verified profile and a shareable booking page.

**P6 — Admin / Ops (internal).** Approves KYC, verifies providers, handles disputes and refunds, moderates content, manages featured placement, monitors marketplace health.

---

## 6. Monetization & pricing

### 6.1 Model
**Provider-paid SaaS subscription.** Consumers never pay Myweli a fee. Revenue = monthly/annual provider subscriptions. Mobile Money deposits/payments are product features (they protect providers and build trust); a small transaction fee is an **optional V3 lever**, not the V1 model.

> **Strategic note (binding):** CI providers are accustomed to free WhatsApp booking. The subscription must clear a hard ROI bar: the value narrative is **"one prevented no-show pays for the month."** Pricing, trials, and the free tier all exist to make that math obvious. A generous free tier is a customer-acquisition tool, not lost revenue.

### 6.2 Tiers (indicative FCFA — validate with market testing)

| Tier | Price (indicative) | Who | Key entitlements |
|---|---|---|---|
| **Découverte** (Free) | 0 | New/solo providers, freelancers | Public profile + booking page, accept bookings, calendar, 1 staff, **deposits enabled**, basic WhatsApp/SMS confirmations, capped at N bookings/month, Myweli branding on booking page |
| **Pro** | ~7 500 / mo (or annual discount) | Single-location salons | Unlimited bookings, up to 5 staff, automated WhatsApp reminders, no-show protection rules, client database, reviews management, remove Myweli branding, priority support |
| **Business** | ~20 000 / mo | Multi-chair / busy salons | Up to 15 staff, advanced calendar (resources, buffers), analytics & reports, marketing tools (promos, broadcast), commission tracking, featured-eligible |
| **Entreprise** | Custom | Chains / multi-location (V3) | Multi-location, roles & permissions, consolidated reporting, API access |

Add-ons (V2+): extra staff seats, featured placement (paid promotion), SMS bundles, advanced marketing.

### 6.3 Billing requirements
- Subscriptions billed via **Mobile Money** (recurring or reminder-based renewal; true auto-debit support varies by operator — design for both auto-renew where supported and a one-tap renewal reminder where not).
- In-app purchase rules: subscriptions sold to **providers** through the Pro app must respect Apple/Google policies — because Pro is a B2B SaaS tool, bill **outside** IAP via Mobile Money where store policy allows (B2B carve-out); otherwise gate provider signup/billing to web to avoid store IAP cut. **(Open question OQ-3.)**
- Free trial: 30 days of Pro on signup, no Mobile Money required to start.
- Dunning: grace period + WhatsApp/SMS renewal nudges before downgrade to Free.
- Proration, upgrade/downgrade, annual vs monthly, receipts (PDF), TVA handling (§18).

---

## 7. Scope & phasing

Phases are tagged on every requirement as **[V1]**, **[V2]**, **[V3]**.

### 7.1 V1 — "Book, deposit, show up" (Launch MVP)
The minimum to onboard salons in 3 communes and run real, deposit-backed bookings.

- Consumer: phone/OTP auth, discovery (search, category, **commune filter**, map), provider profile, booking flow, **Mobile Money deposit**, my bookings, cancel/reschedule (policy-bound), reviews (post-completion), favorites, rebook, push + SMS/WhatsApp notifications.
- Pro: phone/OTP auth, **KYC onboarding**, profile & photos (with upload), services (CI taxonomy, price ranges), staff, **availability with buffers**, incoming booking accept/reject, calendar/day view, mark complete, **deposit & no-show rules**, **automated WhatsApp/SMS reminders**, basic earnings, subscription (Free + Pro trial).
- Web: **per-provider public booking page (SEO)**, basic consumer marketplace (browse/search/book), provider sign-up landing.
- Admin: provider KYC approval queue, verification, basic dispute/refund handling, featured toggle.
- Cross-cutting: Mobile Money via aggregator, WhatsApp Business API, SMS fallback, push (FCM), offline-tolerant reads, French UI, FCFA, analytics baseline.

### 7.2 V2 — "Grow & retain"
- Consumer: home-service ("à domicile") end-to-end (location pin + landmark, transport fee, "send my location"), group/event bookings, packages/bundles, promo codes, referral program, wallet/store credit, **cross-salon loyalty wallet + memberships/abonnements + gift certificates (YPLACES-style retention machine)**, in-app chat or WhatsApp handoff, "open now"/"available today" filters, provider stories (UGC), rebook reminders (lifecycle push).
- Pro: provider-posted stories, marketing broadcasts, client segments (VIP/new/inactive), **issuing loyalty/memberships/certificates (FR-PRO-LOY-001)**, commission tracking (real), advanced calendar (resources/rooms), waitlist, recurring appointments, analytics that matter, full provider dashboard on web.
- Web: full consumer marketplace, provider dashboard (web), admin/ops console (full).
- Monetization: Business tier, paid featured placement, SMS bundles.

### 7.3 V3 — "Platform & expansion"
- Pro "operations" suite (gated on PMF): inventory tied to services, payroll, multi-location & roles, reports/analytics deep-dive. *(Loyalty, memberships, and gift certificates moved up to V2 — see §2.6.)*
- New verticals beyond beauty (clinics, fitness, tattoo, detailing…).
- Optional transaction-fee revenue lever; card payments; tipping via Mobile Money.
- Regional expansion architecture (multi-currency, multi-operator), additional languages (English, Nouchi marketing copy).

### 7.4 Feature → phase matrix (high level)

| Domain | V1 | V2 | V3 |
|---|---|---|---|
| Auth (phone/OTP) | ✅ | | |
| Discovery + commune filter | ✅ | "open now", AI ranking | |
| Booking flow + deposit | ✅ | group, packages, recurring | |
| Home service (à domicile) | partial (flag only) | ✅ full | |
| Payments | deposits + balance + one-tap (MoMo) | wallet, promo, referral credit | tipping, cards, txn fees |
| Loyalty / memberships / gifting (consumer + pro) | ❌ | ✅ wallet, abonnements, certificates | |
| Visit history + auto-sync + rebook | ✅ | | |
| Notifications | push + WhatsApp + SMS | lifecycle/rebook, broadcasts | |
| Reviews | ✅ post-completion + photos | | |
| Pro: schedule/staff/services | ✅ | resources, waitlist | multi-location, roles |
| Pro: earnings | basic | commission tracking | payroll |
| Pro: marketing | confirmations/reminders | promos, stories, segments, loyalty, memberships | — |
| Pro: ERP (inventory/payroll/analytics) | ❌ | ❌ | ✅ gated |
| Web: provider booking page | ✅ | | |
| Web: consumer marketplace | basic | ✅ full | |
| Web: provider dashboard | ❌ | ✅ | |
| Web: admin console | basic | ✅ full | |

---

## 8. Platform & technical strategy

### 8.1 Client platforms

| Surface | Stack | Rationale |
|---|---|---|
| Consumer iOS + Android | **Flutter** (existing) | One codebase, good perf on low-end Android, current investment. |
| Pro iOS + Android | **Flutter** (existing, `main_pro.dart`) | Same. |
| **Public web** (per-provider booking pages + consumer marketplace) | **Next.js / React (SSR/SSG)** | **SEO and shareability are the entire point** of these surfaces. Flutter Web cannot rank on Google or render fast on first paint. Public pages must be server-rendered. |
| Provider dashboard (web) | React (shared with public web) **or** Flutter Web | Behind login, SEO irrelevant; choose by team velocity. Recommend React to share components/design system with public web. |
| Admin/ops console | React | Internal, behind auth; reuse web stack. |

**Decision:** Do **not** build the public-facing web on Flutter Web. Public booking pages and the marketplace are SEO-first and must be SSR (Next.js). Authenticated surfaces (provider dashboard, admin) may use the same React stack.

### 8.2 Backend
- Single API (REST or GraphQL) serving all clients. Replace the existing mock `*ServiceInterface` implementations with real HTTP implementations — **the interface-then-mock architecture already in the codebase is preserved** and makes this swap localized.
- Recommended: managed Postgres, an app server (Node/NestJS or Dart/serverpod or Python/FastAPI — team's choice), object storage for images (S3-compatible) with on-upload compression/resizing, Redis for slot/availability caching.
- **Offline tolerance:** clients cache reads (provider lists, profiles, schedule) and queue mutations (e.g., mark-complete) for sync. Booking + payment are online-only (money requires connectivity) but must degrade gracefully with clear retry UX.

### 8.3 Migration from current state
The current app is 100% mock. Cutover plan:
1. Stand up backend + auth + provider/listing read APIs; swap `ProviderServiceInterface` + `AuthServiceInterface`.
2. Booking write + availability; swap `AppointmentServiceInterface`.
3. Payments (deposit) + notifications.
4. Pro write paths (services/staff/availability) + KYC.
5. Retire mock services behind a build flag (keep for tests/demos).

### 8.4 Environments
Dev / Staging / Prod. Feature flags for phased rollout and commune-by-commune launch. Remote config for tunables (deposit %, cancellation windows, reminder timing).

---

## 9. Functional requirements — Consumer (iOS + Android)

> Notation: each requirement has an ID, a phase tag, and (for key flows) acceptance criteria (AC). Existing screens are referenced where they already implement part of this.

### 9.1 Authentication & account

- **FR-AUTH-001 [V1]** Phone-number login with country code defaulted to **+225**, validated to Ivorian formats. *(exists: `phone_login_screen.dart`)*
- **FR-AUTH-002 [V1]** OTP verification via SMS; auto-read OTP on Android where possible; resend with cooldown; max attempts + lockout. *(exists in mock as `123456`)*
  - **AC:** Given a valid CI number, when the user requests OTP, then an SMS is delivered within 30s (p95) and a 6-digit code is accepted; after 5 failed attempts the number is rate-limited for 15 min.
- **FR-AUTH-003 [V1]** Session persistence via secure storage; silent re-auth on launch; explicit logout. *(exists: `flutter_secure_storage`)*
- **FR-AUTH-004 [V1]** Profile: name, optional email, optional photo. Edit profile. *(exists: `edit_profile_screen.dart`)*
- **FR-AUTH-005 [V1]** Account deletion & data export request (store-policy + data-law compliance, §18).
- **FR-AUTH-006 [V2]** Optional social/Google sign-in (secondary; phone remains primary).

### 9.2 Discovery & search

- **FR-DISC-001 [V1]** Home hub: search bar, category chips, featured providers, nearby providers, recent bookings, favorites strip. *(exists: `home_screen.dart`)*
- **FR-DISC-002 [V1]** **Commune filter as a first-class facet** (Cocody, Marcory, Plateau, Yopougon, Treichville, Abobo, Adjamé, Koumassi…). In Abidjan, commune matters more than generic distance.
- **FR-DISC-003 [V1]** Category browse using **CI service taxonomy** (Appendix A), not generic "hair/nails".
- **FR-DISC-004 [V1]** Search by provider name, service, and locality; typo-tolerant; French-aware.
- **FR-DISC-005 [V1]** Map discovery (flutter_map/OSM) with provider markers, commune awareness, tap-to-card. *(exists: `map_screen.dart`)*
- **FR-DISC-006 [V1]** Provider profile: hero gallery (pinch-zoom), description, services with **price ranges & durations**, staff/artists, working hours, reviews summary + list, contact (call + **WhatsApp deep link**), favorite toggle, sticky Book CTA, verified badge. *(exists: `provider_detail_screen.dart` — needs price ranges, WhatsApp, verified badge, before/after gallery)*
- **FR-DISC-007 [V1]** Sort & filter: by rating, price, availability ("available today"), commune, home-service capability.
- **FR-DISC-008 [V2]** "Open now" / "Available today" / "Open Sunday" / "Open late" time filters.
- **FR-DISC-009 [V2]** Home-service ("à domicile") filter and provider badge.
- **FR-DISC-010 [V2]** Provider stories (UGC) on profile and home. *(partial: `stories/` consumer-side exists for system stories)*
- **FR-DISC-011 [V3]** Personalized ranking/recommendations.

### 9.3 Booking flow

- **FR-BOOK-001 [V1]** Booking hub with service / artist / date-time sections, smart ordering, auto-advance, sticky summary (total price range, duration), real-time validation. *(exists & strong: `booking_hub_screen.dart`)*
- **FR-BOOK-002 [V1]** Multi-service selection; total duration drives slot length. *(exists)*
- **FR-BOOK-003 [V1]** Artist selection with "no preference," service-compatibility filtering. *(exists)*
- **FR-BOOK-004 [V1]** Slot availability respects provider hours, **buffer time between appointments**, blocked dates, and existing bookings. *(slot model exists; buffers must be added)*
- **FR-BOOK-005 [V1]** **Price ranges & length/type modifiers** — a service may price as min–max (e.g., tresses "15 000–25 000 selon la longueur"); booking shows estimated range, final confirmed by provider.
- **FR-BOOK-006 [V1]** **Variable duration by hair length/type** — service can declare duration variants (court/moyen/long) affecting slot length.
- **FR-BOOK-007 [V1]** Booking confirmation summary → **deposit step** (§9.4) → confirmed booking. *(confirmation exists; deposit must be added)*
- **FR-BOOK-008 [V1]** Auth gating: unauthenticated users can browse and assemble a booking; auth is required at confirm, with `returnTo` continuity. *(returnTo pattern exists)*
- **FR-BOOK-009 [V1]** **Rebook ("Réserver à nouveau")** — one tap to repeat a prior appointment (same services/artist), then pick a slot.
- **FR-BOOK-010 [V2]** **Home service booking** — when provider offers à domicile: capture client location (GPS pin + landmark text), compute/display transport fee, "send my location" share.
- **FR-BOOK-011 [V2]** **Group/event booking** — book multiple people/services for one date (mariages, baptêmes); per-person service selection; combined deposit.
- **FR-BOOK-012 [V2]** **Packages/bundles** — provider-defined multi-service packages with bundle pricing.
- **FR-BOOK-013 [V2]** **Promo codes** applied at confirm.
- **FR-BOOK-014 [V2]** **Waitlist** — join a waitlist for a full day/slot; notify on opening.
- **FR-BOOK-015 [V3]** **Recurring appointments** — "every 6 weeks, Saturday 10:00."

### 9.4 Payments & deposits (consumer side)

- **FR-PAY-001 [V1]** **Deposit to confirm** — provider-configurable deposit (% or fixed FCFA). Booking is only "confirmed" after deposit is paid via Mobile Money. *(does not exist — critical)*
  - **AC:** Given a provider requires a 30% deposit, when the customer confirms a 20 000 FCFA booking, then they are prompted to pay 6 000 FCFA via Wave/OM/MTN/Moov; on success the booking status → confirmed and both parties are notified; on failure the slot is held for a short TTL then released.
- **FR-PAY-002 [V1]** Mobile Money operator choice (Wave, Orange Money, MTN MoMo, Moov) via aggregator; **one-tap pay** with remembered operator/number and optional auto-pay confirmation (the YPLACES one-click analog, on Mobile Money rails).
- **FR-PAY-003 [V1]** Clear display of **deposit vs. balance** ("Acompte 6 000 FCFA payé · Solde 14 000 FCFA à régler au salon").
- **FR-PAY-004 [V1]** Receipts / transaction history in-app; downloadable.
- **FR-PAY-005 [V1]** **Refund handling** per cancellation policy (FR-APPT-005): automatic where rules allow; dispute path otherwise.
- **FR-PAY-006 [V2]** **Pay full amount in-app** (deposit + balance) optionally.
- **FR-PAY-007 [V2]** **Wallet / store credit** — refunds and referral rewards land here; usable on next booking.
- **FR-PAY-008 [V3]** **Tipping** via Mobile Money post-appointment.
- **FR-PAY-009 [V3]** Card payments (secondary rail).

### 9.5 Appointment management (consumer)

- **FR-APPT-001 [V1]** My bookings: Upcoming / Past / Cancelled tabs. *(exists: `my_bookings_screen.dart`)*
- **FR-APPT-002 [V1]** Appointment detail: status, services, provider, artist, date/time, location, deposit/balance, actions. *(exists)*
- **FR-APPT-003 [V1]** Cancel — **policy-bound**: shows deposit consequence before confirming ("Annulation à moins de 24h : acompte non remboursable").
- **FR-APPT-004 [V1]** Reschedule — within policy; re-checks availability; deposit carries over.
- **FR-APPT-005 [V1]** **Cancellation policy engine** — provider sets window (e.g., free cancel >24h, deposit forfeit <24h, full charge on no-show). Enforced automatically on deposit/refund.
- **FR-APPT-006 [V1]** Calendar add (.ics / native calendar) and directions (maps) to the provider.
- **FR-APPT-007 [V2]** In-app chat or WhatsApp handoff with provider for booking edge cases.
- **FR-APPT-008 [V1]** **Auto-sync of provider-entered bookings** (YPLACES-style) — when a provider books a client manually (FR-PRO-BOOK-002), matched by phone number, the appointment appears automatically in that client's app with full details. Bridges the paper journal and the consumer app and drives organic install ("your salon already booked you — see it here").
- **FR-APPT-009 [V1]** **Rich visit history** — a personal record per visit: date/time, provider, address, services, artist, amount paid (deposit/balance), receipts. The consumer's beauty journal; basis for rebook (FR-BOOK-009), loyalty, and lifecycle reminders.

### 9.6 Reviews & trust (consumer)

- **FR-REV-001 [V1]** Submit review only after a **completed** appointment at that provider; 1–5 stars + text. *(exists: `submit_review_sheet.dart`, gated on completion)*
- **FR-REV-002 [V1]** **Review photos** (before/after) and a **"verified booking"** badge on reviews.
- **FR-REV-003 [V1]** Per-stylist attribution optional (review the artist, not just the salon).
- **FR-REV-004 [V2]** Provider response to reviews (visible on profile).
- **FR-REV-005 [V1]** Report/flag review (moderation path, §16).

### 9.7 Favorites, notifications, retention

- **FR-FAV-001 [V1]** Add/remove favorites; favorites map view; deep-link focus. *(exists: `favorites/`)*
- **FR-NOTIF-001 [V1]** Push (FCM) + SMS fallback + WhatsApp for: booking confirmed, deposit received, reminder (24h & 2h), provider accepted/declined, reschedule, cancellation, refund. *(stub today)*
- **FR-NOTIF-002 [V1]** In-app notification center. *(stub: `notifications_screen.dart`)*
- **FR-NOTIF-003 [V2]** **Rebook lifecycle reminder** — "Il y a 6 semaines depuis vos dernières tresses chez Beauté Divine — réserver à nouveau ?" (single biggest repeat-booking driver).
- **FR-NOTIF-004 [V1]** Notification preferences (channel & category opt-out where law/store requires).
- **FR-REF-001 [V2]** **Referral program** — "Invite un ami : 2 000 FCFA chacun sur le prochain rendez-vous." Unique codes/links, attribution, credit to wallet, anti-abuse.

### 9.8 Localization & accessibility (consumer)
- **FR-L10N-001 [V1]** French UI throughout; FCFA currency formatting; CI phone formatting; `fr_FR` dates. *(exists)*
- **FR-L10N-002 [V3]** English locale + Nouchi-flavored marketing copy.
- **FR-A11Y-001 [V1]** Minimum: legible contrast, dynamic text scaling, semantic labels on primary actions, large tap targets (low-end touch).

### 9.9 Membership, loyalty & gifting (YPLACES-inspired retention machine)

The unified consumer "personal account" that aggregates value across all visited providers — the core of YPLACES's stickiness. Pulled forward to V2 (see §2.6). Issuance lives provider-side (FR-PRO-LOY-001).

- **FR-LOY-001 [V2]** **Cross-salon loyalty wallet** — one screen aggregating bonus/loyalty cards, points balances, promos, and discounts from every provider the user has visited. Not a per-salon silo.
- **FR-MEMB-001 [V2]** **Consumer memberships / abonnements** — "Mes abonnements": view remaining visits/sessions and validity period; renew or buy in-app via Mobile Money. Key for spa/wellness and high-frequency services (regular tresses, barber).
- **FR-GIFT-001 [V2]** **Gift certificates** — buy a certificate as a gift, send it (WhatsApp/SMS link), recipient redeems against a booking. Strong fit for CI gifting culture (fêtes, anniversaires).
- **FR-REBOOK-001 [V1]** **Frictionless rebooking from history** — surface "Réserver à nouveau" prominently in visit history and home; pre-fill last services/artist (pairs with FR-BOOK-009, FR-APPT-009).

---

## 10. Functional requirements — Provider (Pro) apps

Pro is a separate app/entry (`main_pro.dart`, `pro_router.dart`). Built for the stylist's day; the owner's reporting is secondary.

### 10.1 Onboarding, auth & KYC

- **FR-PRO-AUTH-001 [V1]** Phone/OTP login & registration: business name, **business type** (salon/barber/spa/nail/massage/freelance/other), address (pin + landmark), commune. *(exists: `pro_register_screen.dart`)*
- **FR-PRO-KYC-001 [V1]** **KYC & verification flow** (currently a data field with no UI): upload business registration / ID, owner photo, business address proof; status pending → verified/rejected; **"Verified" badge** surfaced on consumer profile.
  - **AC:** A provider cannot receive bookings with deposits until verified; admin can approve/reject with reason; provider sees status and required actions.
- **FR-PRO-ONB-001 [V1]** Guided onboarding (the empty `onboarding/` folder): create profile → add ≥3 services → add staff → set availability → upload ≥3 photos → set deposit & cancellation policy → go live. Progress checklist.
- **FR-PRO-AUTH-002 [V2]** Roles: owner / manager / stylist with permissions (the empty `settings/` + multi-staff needs).

### 10.2 Profile & media
- **FR-PRO-PROF-001 [V1]** Edit business profile: name, description, category, commune, address (pin + landmark), hours, contact, WhatsApp number, home-service capability + zone + transport fee. *(profile screen exists; add fields)*
- **FR-PRO-MEDIA-001 [V1]** **Image upload pipeline** (does not exist): hero photos, gallery, before/after, per-stylist photos; client-side compression; moderation queue.
- **FR-PRO-STORY-001 [V2]** Provider-posted stories (UGC supply, free engagement; extends existing consumer story UI).

### 10.3 Services, staff, availability
- **FR-PRO-SVC-001 [V1]** Service CRUD: name (from taxonomy), description, **price range (min–max)**, **duration variants** (court/moyen/long), category, which artists can perform it, active toggle, deposit override. *(CRUD + price range + duration variants done; taxonomy picker / category / active toggle / deposit override still ad-hoc)*
- **FR-PRO-STAFF-001 [V1]** Staff/artist CRUD: name, photo, specialization, services they perform, working hours, **commission rate**. *(exists; add commission, per-staff hours)*
- **FR-PRO-AVAIL-001 [V1]** Availability: weekly schedule per day, per-staff hours, **buffer time between appointments**, blocked dates/holidays, break times. *(exists: `availability_screen.dart`; add buffers, per-staff, breaks)*
- **FR-PRO-AVAIL-002 [V2]** Resources/rooms (a spa room, a chair) as bookable constraints.

### 10.4 Calendar, bookings & day-of operations
- **FR-PRO-CAL-001 [V1]** **Today/day view** = the stylist's home screen: chronological list of today's appointments, who's next, client name, services, status. *(calendar exists; make day-view the default landing for stylists)*
- **FR-PRO-CAL-002 [V1]** Week/month calendar; full-team "booking journal" view (all staff in one grid). *(`booking_journal` UI mock exists — wire it to real data)*
- **FR-PRO-BOOK-001 [V1]** Incoming booking request → **accept / reject (with reason)**. *(exists in interface)*
- **FR-PRO-BOOK-002 [V1]** **Manual booking entry** — stylist books a walk-in/phone client into the calendar (replaces the paper cahier; critical adoption feature).
- **FR-PRO-BOOK-003 [V1]** Mark complete; reschedule; cancel (policy-bound). *(exists)*
- **FR-PRO-BOOK-004 [V1]** **No-show marking** + no-show consequences (deposit forfeit, customer flagged). *(does not exist)*
- **FR-PRO-BOOK-005 [V2]** Waitlist management; fill cancellations from waitlist.
- **FR-PRO-BOOK-006 [V2]** Block/unblock slots quickly (lunch, personal).

### 10.5 Money (provider side)
- **FR-PRO-PAY-001 [V1]** **Deposit settings**: default deposit % or fixed, per-service override, cancellation policy windows.
- **FR-PRO-EARN-001 [V1]** Earnings: deposits collected, balance expected, completed revenue by day/week/month, transaction list. *(exists: `earnings_screen.dart`)*
- **FR-PRO-PAYOUT-001 [V1]** **Payout of collected deposits** to the provider's Mobile Money account (settlement schedule, statement). *(V1 frontend built on mock — balance/history + "Demander un virement"; real Mobile Money settlement + deposit-custody (OQ-1) are backend)*
- **FR-PRO-COMM-001 [V2]** **Commission tracking** — per-stylist commission computed from completed appointments (the payroll mock made this up; make it real).
- **FR-PRO-PAYROLL-001 [V3]** Payroll calculation (base + commission + bonus) — the `payroll_calculation_screen.dart` mock, properly modeled.

### 10.6 Dashboard, reviews, marketing
- **FR-PRO-DASH-001 [V1]** Dashboard: today's appointments, pending requests, today/week/month revenue, no-show rate. *(exists)*
- **FR-PRO-REV-001 [V1]** View reviews; **respond to reviews** [V2]. *(view exists)*
- **FR-PRO-MKT-001 [V1]** Automated client comms: confirmations + **WhatsApp/SMS reminders** (24h/2h). *(the `whatsapp_notifications` mock — ship it for real; this is the #1 paid value driver)*
- **FR-PRO-MKT-002 [V2]** Promo creation, broadcast messages to clients, client segments (VIP/new/inactive) — the `loyalty_programs` + `client_database` mocks, wired to real data.
- **FR-PRO-CLIENT-001 [V2]** **Client database** with visit history, notes (allergies/preferences), loyalty points — the `client_database` mock made real. **Per-stylist client notes** is a Fresha-killer feature in this market.
- **FR-PRO-LOY-001 [V2]** **Issue loyalty, memberships & certificates** (YCLIENTS-style) — provider creates bonus/points programs, memberships/abonnements (session packs), and gift certificates; these surface in the consumer wallet (FR-LOY-001 / FR-MEMB-001 / FR-GIFT-001). **Pulled forward from the V3 ops suite because retention is on-thesis** (see §2.6).

### 10.7 Pro "operations" suite — V3, gated on PMF
These exist today as **unrouted UI mocks** in `screens/provider/features/`. They are explicitly **deferred** and must be hidden/removed from the shipping Pro app until V3 and until booking+payment+retention is proven. **Exception:** loyalty, memberships, and gift certificates have been pulled forward to **V2** (§10.6, FR-PRO-LOY-001) because they drive retention; only the back-office modules below remain V3-gated.
- **FR-PRO-OPS-001 [V3]** Inventory management (products, stock, low-stock alerts; tie consumption to services).
- **FR-PRO-OPS-002 → moved to V2** Loyalty programs (points, cashback) & gift certificates — see FR-PRO-LOY-001 (§10.6).
- **FR-PRO-OPS-003 → moved to V2** Memberships / abonnements (incl. spa packages, Mindbody-style) — see FR-PRO-LOY-001 (§10.6).
- **FR-PRO-OPS-004 [V3]** Reports & analytics deep-dive (revenue, top services/staff, no-show analytics, retention).
- **FR-PRO-OPS-005 [V3]** Online booking widget / embeddable form (largely superseded by web booking pages, §11.1).
- **FR-PRO-OPS-006 [V3]** Multi-location & freelancer-network management (the empty `freelancers/`, `more/` folders).

### 10.8 Subscription (in-app)
- **FR-PRO-SUB-001 [V1]** View plan, entitlements, usage; 30-day Pro trial; upgrade/downgrade; pay via Mobile Money; renewal reminders; invoices/receipts (TVA). *(see §6; store-IAP constraint OQ-3)*

---

## 11. Functional requirements — Web surfaces

Four surfaces, two stacks: **public (SSR, Next.js)** and **authenticated (React app)**.

### 11.1 Per-provider public booking pages — [V1] (SEO-first)
- **FR-WEB-PP-001 [V1]** Each provider gets a public, shareable URL: `myweli.ci/<slug>` (e.g., `myweli.ci/salon-excellence`). For Instagram bios — the single biggest organic acquisition channel.
- **FR-WEB-PP-002 [V1]** Server-rendered (SSR/SSG) for SEO: title, description, services, prices, hours, photos, reviews, commune, map, verified badge — all in crawlable HTML with structured data (Schema.org `LocalBusiness`/`BeautySalon`).
- **FR-WEB-PP-003 [V1]** Full booking flow on web (service → staff → slot → deposit) without forcing app install; mobile-web optimized (most traffic is mobile browsers).
- **FR-WEB-PP-004 [V1]** Mobile Money deposit on web (aggregator hosted/redirect flow).
- **FR-WEB-PP-005 [V1]** "Open in app" smart banner; app-install attribution.
- **FR-WEB-PP-006 [V2]** Custom branding/colors per provider (Pro tier removes Myweli branding).

### 11.2 Consumer marketplace (web) — [V1 basic → V2 full]
- **FR-WEB-MP-001 [V1]** SEO landing + category/commune pages (`/tresses-cocody`, `/barbier-plateau`) — crawlable, drive organic search demand.
- **FR-WEB-MP-002 [V2]** Full browse/search/filter/map mirroring the app; account login (phone/OTP); my bookings on web.
- **FR-WEB-MP-003 [V2]** Web booking parity with app (group, packages, promos).

### 11.3 Provider dashboard (web) — [V2]
- **FR-WEB-PD-001 [V2]** Web login (provider). Manage profile, services, staff, availability, calendar, bookings, earnings, payouts, reviews, marketing, subscription — fuller-screen admin the owner prefers on desktop.
- **FR-WEB-PD-002 [V2]** Reports/analytics views (bigger screen real estate).
- **FR-WEB-PD-003 [V2]** Bulk operations (bulk service edit, schedule templates).

### 11.4 Admin / ops console — [V1 basic → V2 full]
- **FR-WEB-AD-001 [V1]** **KYC approval queue** — review submissions, approve/reject with reason, set verified badge.
- **FR-WEB-AD-002 [V1]** Provider & user management; suspend/ban; impersonate (audited) for support.
- **FR-WEB-AD-003 [V1]** **Dispute & refund handling** — deposit disputes, manual refunds, payout adjustments.
- **FR-WEB-AD-004 [V1]** Content moderation (reviews, photos, stories).
- **FR-WEB-AD-005 [V1]** Featured placement management.
- **FR-WEB-AD-006 [V2]** Marketplace health dashboards (liquidity by commune, no-show rates, supply funnel).
- **FR-WEB-AD-007 [V2]** Promo/referral campaign management; subscription/billing ops.
- **FR-WEB-AD-008 [V1]** Role-based access for the Myweli team; full audit log.

---

## 12. Cross-cutting systems

### 12.1 Availability & slot engine
- Single source of truth for slots, honoring: provider hours, per-staff hours, service duration (incl. variants), buffers, breaks, blocked dates, existing bookings, resources (V2). Server-authoritative; clients display cached views; **final slot validity re-checked at confirm** to prevent double-booking.

### 12.2 Booking state machine
`draft → pending_deposit → confirmed → completed` with branches `declined`, `cancelled_by_customer`, `cancelled_by_provider`, `no_show`, `expired (deposit TTL)`. Each transition fires notifications and payment/refund rules. (Extends existing `AppointmentStatus` enum: pending/confirmed/cancelled/completed.)

### 12.3 Deposit/refund rules engine
Provider-configured policy → deterministic outcomes on cancel/no-show/reschedule. Auditable. Disputes escalate to admin.

### 12.4 Notification orchestration
Channel priority: **Push → WhatsApp → SMS** with fallback if undelivered. Template management, rate limits, quiet hours, per-category preferences. Delivery receipts tracked (guardrail KPI).

### 12.5 Search & ranking
V1: filters + simple relevance (commune, rating, availability, verified). V2+: boost by responsiveness, completion rate, recency; paid featured slots clearly labeled.

### 12.6 Media service
Upload → virus/content scan → compress/resize variants → CDN. Moderation hooks.

### 12.7 Feature flags & remote config
Commune-by-commune rollout; tunable deposit %, cancellation windows, reminder timing, trial length.

---

## 13. Data model

Builds on existing models (`User`, `ProviderUser`, `Provider`, `Service`, `Artist`, `Appointment`, `Availability`, `TimeSlot`, `Review`). Additions in **bold**.

| Entity | Key fields | Notes |
|---|---|---|
| **User** | id, phone, name?, email?, photo?, **walletBalance**, createdAt | Consumer. |
| **ProviderUser** | id, phone, name, businessName, businessType, address, **pin(lat/lng)**, **landmarkText**, **commune**, verificationStatus, **kycDocs[]**, providerId, **subscriptionId**, createdAt | Owner/admin of a Provider. |
| **Provider** | id, name, description, address, commune, lat/lng, landmark, imageUrls[], logo, rating, reviewCount, category(enum), phone, **whatsapp**, **homeServiceEnabled**, **homeServiceZone**, **transportFee**, **slug**, **verified**, services[], artists[], availability, reviews[] | Public listing. `category` → typed enum + taxonomy. `slug` → web page. |
| **Service** | id, name(taxonomyRef), description, **priceMin**, **priceMax**, **durationVariants{court,moyen,long}**, providerId, artistIds[], active, **depositOverride?** | Price as range; duration variants. |
| **Artist/Staff** | id, name, photo?, providerId, specialization?, rating?, reviewCount?, **services[]**, **workingHours**, **commissionRate**, **role** | Commission + role added. |
| **Appointment** | id, userId, providerId, serviceIds[], artistId?, dateTime, **endTime**, status(stateMachine), totalPriceMin/Max, **depositAmount**, **depositStatus**, **balanceDue**, **isHomeService**, **clientLocation?**, notes?, **cancellationPolicySnapshot**, createdAt | Money + location + policy snapshot. |
| **Availability** | providerId, weeklySchedule(Map day→slots), **perStaffSchedule**, **bufferMinutes**, **breaks**, blockedDates[] | Buffers/breaks added. |
| **Review** | id, providerId, **artistId?**, userId, userName, rating, text, **photos[]**, **verifiedBooking**, **providerResponse?**, createdAt | Photos + verification + response. |
| **Payment** | id, appointmentId?, subscriptionId?, userId/providerId, amount, type(deposit/balance/refund/subscription/payout/tip), operator(wave/om/mtn/moov), status, providerRef, createdAt | New. Mobile Money txns. |
| **Subscription** | id, providerId, tier, status(trial/active/past_due/cancelled), startedAt, renewsAt, seats, addons[] | New. SaaS billing. |
| **Payout** | id, providerId, amount, period, status, mobileMoneyAccount, statement | New. Deposit settlement. |
| **Client (CRM)** | id, providerId, name, phone, visitHistory[], **notes**, loyaltyPoints, segment | V2. Per-provider CRM. |
| **PromoCode / Referral** | code, type, value, constraints, attribution | V2. |
| **LoyaltyProgram / LoyaltyCard** | id, providerId, rules(points/cashback), userBalance | V2. Surfaces in consumer cross-salon wallet (FR-LOY-001). |
| **Membership / Abonnement** | id, providerId, userId, title, totalSessions, remainingSessions, validFrom, validTo, price, status | V2. Consumer "Mes abonnements" (FR-MEMB-001). |
| **GiftCertificate** | id, providerId, purchaserId, recipientPhone?, amount/serviceRef, code, status(active/redeemed/expired), validTo | V2. Buy & gift (FR-GIFT-001). |
| **Notification** | id, userId/providerId, type, channel, payload, status, sentAt | New (replaces stub). |
| **StoryPost** | id, providerId/system, media, cta, expiresAt | Extends existing stories. |
| **Inventory / Payroll** | — | V3, gated. |

---

## 14. Integrations

| Integration | Purpose | Phase | Notes |
|---|---|---|---|
| **Mobile Money aggregator** (CinetPay / PayDunya / Hub2 / Semoa) | Deposits, balance, subscriptions, payouts across Wave/OM/MTN/Moov via one integration | V1 | Strongly prefer aggregator over 4 direct integrations. Validate Wave coverage specifically. |
| **WhatsApp Business API** (via BSP: Meta Cloud API / 360dialog / Twilio) | Confirmations, reminders, broadcasts | V1 | Template-message approval; opt-in compliance. |
| **SMS gateway** (local: LeTexto/CI operators, or Twilio) | OTP + notification fallback | V1 | OTP deliverability is critical; consider multi-provider. |
| **Push** (Firebase Cloud Messaging) | App notifications | V1 | iOS APNs via FCM. |
| **Maps** (OpenStreetMap via flutter_map; geocoding) | Discovery, directions, home-service pins | V1 | Already on flutter_map; add geocoding + "send my location." |
| **Object storage / CDN** (S3-compatible) | Media | V1 | With compression pipeline. |
| **Crash/perf** (Firebase Crashlytics / Sentry) | Stability | V1 | |
| **Analytics** (see §17) | Product analytics | V1 | |
| **Store billing** (Apple/Google) | Only if consumer IAP ever needed | — | Provider SaaS billed via Mobile Money/web to avoid store cut (OQ-3). |

---

## 15. Non-functional requirements

- **NFR-PERF-001** Reference device = low-end Android (e.g., 2–3 GB RAM, Android 9). Cold start p95 < 3.5s; key screens interactive < 1.5s on 3G.
- **NFR-PERF-002** APK size minimized (target < 30 MB initial); image-heavy content lazy-loaded & cached (existing `TimedCachedImage`).
- **NFR-OFFLINE-001** Reads (provider lists, profiles, schedule, my bookings) cached & available offline; mutations queued where safe (mark-complete, manual booking) with sync + conflict handling; money flows online-only with clear retry.
- **NFR-DATA-001** Mobile-data thrift: compress uploads, paginate, avoid autoplaying media on cellular.
- **NFR-SEC-001** OTP rate limiting, lockout, secure token storage; least-privilege backend; signed payment callbacks; PCI not required (no card data) but Mobile Money refs handled securely.
- **NFR-SEC-002** PII encryption at rest & in transit; KYC docs access-controlled & audited.
- **NFR-AVAIL-001** Backend 99.9% target; graceful degradation when payment provider is down (allow "reserve, pay deposit shortly" hold with TTL rather than hard fail).
- **NFR-SCALE-001** Slot engine handles concurrent booking attempts without double-book (server-authoritative locking).
- **NFR-I18N-001** All user-facing strings externalized (even though V1 is French-only) to enable English/Nouchi later.
- **NFR-A11Y-001** WCAG-informed basics: contrast, text scaling, tap targets, semantic labels.
- **NFR-OBS-001** Structured logging, tracing, alerting on payment failures, OTP delivery, notification delivery, crash spikes.

---

## 16. Trust, safety & verification

- **KYC for providers** (FR-PRO-KYC-001): registration/ID/address; verified badge; deposits gated on verification.
- **Review integrity**: only completed-booking reviews count as "verified"; flag/report; moderation queue; provider responses.
- **Dispute resolution**: deposit/refund disputes escalate to admin with evidence (chat, photos, status history).
- **No-show & cancellation fairness**: symmetric — protect providers from no-shows *and* customers from provider cancellations (provider repeated cancels affect ranking/standing).
- **Off-platform leakage monitoring**: detect/flag providers steering payment off-platform (erodes trust + future fee revenue).
- **Content moderation**: photos, stories, profiles; report flows; ban/suspend tooling in admin.
- **Anti-fraud**: referral/promo abuse detection; payment fraud monitoring via aggregator signals.

---

## 17. Analytics & instrumentation

- **Funnel events**: app_open, search, commune_filter, profile_view, book_start, service_selected, slot_selected, deposit_initiated, deposit_success/fail, booking_confirmed, reminder_sent/delivered, appointment_completed, review_submitted, rebook.
- **Supply funnel**: provider_signup, kyc_submitted/approved, profile_completed, first_booking, subscription_trial_start, subscription_paid, churn.
- **North Star dashboard**: completed paid appointments/week by commune.
- **Cohorts**: consumer rebooking by 6-week cohort; provider retention by signup cohort.
- **Guardrails**: no-show rate, deposit dispute rate, notification delivery, crash-free rate, off-platform leakage signal.
- Tooling: a product analytics stack (e.g., Firebase + a warehouse, or PostHog/Amplitude) — choose one with affordable event volume.

---

## 18. Compliance & legal (CI)

- **Data protection**: Côte d'Ivoire's personal-data law (ARTCI oversight) — lawful basis, consent for marketing comms, data subject rights (access/delete — FR-AUTH-005), local considerations on data residency. Validate with counsel.
- **Telecom/marketing**: WhatsApp/SMS opt-in & opt-out compliance; OTP and transactional vs. promotional separation.
- **Payments**: operate within Mobile Money aggregator/BCEAO/operator rules; KYC/AML expectations where Myweli handles/settles funds (deposit custody & payouts) — confirm whether a payment partner or agreement is required to hold funds.
- **Tax**: **TVA 18%** on subscription revenue for registered entities; compliant invoicing/receipts (FR-PRO-SUB-001); provider invoicing where applicable.
- **Consumer protection**: clear deposit/refund/cancellation terms surfaced before payment.
- **App store compliance**: Apple/Google policy for B2B SaaS billing (OQ-3), data-safety disclosures, account deletion.

---

## 19. Release plan & rollout

1. **Alpha (internal)** — backend + consumer V1 happy path + deposits on staging; 3–5 friendly salons in Cocody, hand-held.
2. **Closed beta (1 commune — Cocody)** — 15–25 verified providers; supply team onboards in person (profile + first photos + first reminders); fix retention loop; validate deposit → show-up improvement.
3. **V1 launch (3 communes — Cocody, Marcory, Plateau)** — gate expansion on density: ≥50 active providers + ≥500 weekly completed bookings before a 4th commune.
4. **V2** — home service, referral, marketing, web dashboard, full marketplace + admin.
5. **V3** — ops suite, new verticals, regional architecture.

**Rollout mechanics:** feature flags per commune; remote-config deposit/cancellation tunables; staged store releases; supply-side field playbook (door-to-door onboarding kit).

---

## 20. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Providers reject paid SaaS (used to free WhatsApp) | Revenue model fails | Generous free tier; "one prevented no-show pays the month" ROI; 30-day trial; charge only after value shown. |
| Mobile Money integration friction (esp. Wave) | No deposits = no core value | Use aggregator; validate Wave early; design hold-with-TTL fallback. |
| Off-platform leakage | Erodes trust + future fees | Reminders/CRM value lives in-app; monitor; standing/ranking incentives. |
| Cold-start liquidity | Empty marketplace | Single-commune density first; field onboarding; seed with strong providers. |
| Fresha/Booksy localize | Competitive squeeze | Move fast on payments/WhatsApp/home-service moat; lock supply via subscription + booking pages. |
| Low-end device perf | Churn | Strict perf budget; offline tolerance; small app size. |
| No-show disputes / refund fairness | Trust erosion both sides | Deterministic policy engine; clear pre-payment terms; admin dispute path. |
| Scope creep into ERP | Burns runway pre-PMF | V3 gating; hide unrouted feature mocks until then. |
| Store IAP policy on provider billing | Revenue leakage / rejection | Resolve OQ-3 early; prefer web/Mobile Money B2B billing. |

---

## 21. Open questions

- **OQ-1** Deposit custody: does Myweli hold deposits (escrow, requires payment-institution status/partner) or do deposits go directly to providers via aggregator split? Determines payout model & licensing.
- **OQ-2** Exact subscription pricing & free-tier caps — needs field validation with ~20 Cocody salons.
- **OQ-3** Apple/Google IAP treatment of provider SaaS billing — confirm B2B carve-out vs. web-only billing.
- **OQ-4** Which Mobile Money aggregator gives the best Wave + OM coverage and payout support in CI?
- **OQ-5** WhatsApp BSP choice & template approval timeline (gates V1 reminder feature).
- **OQ-6** Home-service transport-fee model: flat, distance-based, or provider-set? (V2 design input.)
- **OQ-7** Data residency expectations under ARTCI — any local-hosting requirement?
- **OQ-8** Provider dashboard web stack: share React with public web vs. Flutter Web reuse?

---

## Appendix A — Service taxonomy (CI)

Replace generic categories with Ivorian-native taxonomy. Top-level categories → services (each service supports price range + duration variants).

- **Coiffure femme (cheveux)** — Tresses & nattes (collées, libres, vanilles), Twists, Locks (entretien/démarrage), Tissage (pose/dépose), Perruque (pose/customisation), Défrisage, Lissage, Brushing, Coloration, Soin capillaire, Coupe femme.
- **Coiffure homme / Barbier** — Coupe / dégradé (fade), Taille de barbe, Rasage, Tresses homme, Locks homme, Coloration homme, Soin du visage homme.
- **Onglerie** — Manucure, Pédicure, Pose semi-permanent (vernis), Gel / Gel-X, Capsules, Nail art, Dépose.
- **Soins & spa** — Soin du visage, Gommage, Massage (relaxant, sportif, etc.), Hammam, Sauna, Épilation (cire/fil), Soins du corps.
- **Maquillage** — Maquillage jour/soirée, Maquillage mariée, Maquillage événement, Pose de faux cils.
- **Sourcils & cils** — Restructuration sourcils, Teinture, Extension de cils, Rehaussement.
- **À domicile** — any of the above with home-service flag, transport fee, location pin + landmark.
- **Événementiel** — packages mariage/baptême, group bookings (multi-person).

(Taxonomy is data-driven and extensible to new verticals in V3.)

---

## Appendix B — Glossary

- **À domicile** — home service; provider travels to the client.
- **Acompte** — deposit paid to confirm a booking.
- **Solde** — remaining balance, often paid in cash at the salon.
- **Cahier de rendez-vous** — paper booking journal Myweli Pro replaces.
- **Commune** — Abidjan administrative district (Cocody, Marcory, Plateau, Yopougon, …); primary geo facet.
- **FCFA** — West African CFA franc (XOF).
- **Mobile Money** — Wave, Orange Money (OM), MTN MoMo, Moov Money.
- **KYC** — provider identity/business verification → "Verified" badge.
- **No-show** — confirmed customer who doesn't attend; deposit-forfeit applies.
- **BSP** — WhatsApp Business Solution Provider.
- **Nouchi** — Ivorian urban slang (future marketing-copy locale).
- **Abonnement** — prepaid membership / session pack (e.g., 10 visits valid 6 months); consumer-side "Mes abonnements."
- **YCLIENTS** — Russia/CIS booking + business-management platform; inspiration for Myweli Pro (business side).
- **YPLACES** — YCLIENTS's consumer companion app; inspiration for the Myweli consumer app (unified account, loyalty, memberships, one-tap pay, effortless rebooking).

---

*End of PRD v1.0. This document supersedes ad-hoc feature notes. Requirement IDs are stable references for tickets, design, and QA traceability.*
