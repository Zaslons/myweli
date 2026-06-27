# Pro subscription — plan & trial view (FR-PRO-SUB-001)

| | |
|---|---|
| **Requirement** | FR-PRO-SUB-001 [V1] — "View plan, entitlements, usage; 30-day Pro trial; upgrade/downgrade; pay via Mobile Money; renewal reminders; invoices/receipts (TVA)." |
| **Phase** | V1 small-gap sweep (ROADMAP §1.8). |
| **Surfaces** | Backend (`GET /me/subscription`, derived) · Pro app (`ProSubscriptionScreen`). |
| **Status** | **Built** (single PR) — derived `GET /me/subscription` + "Mon abonnement" screen. In-app billing deferred. |

## 1. Goal & scope
Give a provider a clear **"Mon abonnement"** screen: their current plan, **free-trial
status**, what Pro includes, indicative pricing, and a way to reach Myweli.

**Deferred (PRD §6.3 + OQ-3):** in-app **Mobile Money billing**, auto-renew,
proration, dunning, PDF/TVA invoices. Collecting subscriptions = Myweli
**receiving funds** → same no-custody/incorporation block as deposits; paid
collection turns on post-incorporation. Until then it "rides the free trial +
free tier," and **early paid salons are handled manually** (→ the "Nous contacter"
CTA). So V1 = a **read-only plan & trial view**, no payment rail.

## 2. Pricing & trial — decisions (provisional; pricing is OQ-2)
Centralized as **config**, easy to change at launch:
- **Free period:** **3 months** (trial = signup + 90 days). Single source of truth:
  backend `kProTrialDays = 90` drives the derivation; the app shows the dynamic
  "X jours restants" from the response + a "Gratuit pendant 3 mois" headline.
- **Anchor price (displayed "regular"):** **70 000 FCFA / mois** for Pro — an
  intentional **price anchor**. Planned real base is **20 000–40 000 FCFA/mo**
  (internal, *not shown*); when paid launches at that level it reads as a discount
  off the 70 000 anchor. Stored in `core/config/subscription_plans.dart`.
- Tiers shown: **Découverte (Free, 0)** + **Pro (70 000 anchor, free now)**. Business
  tier omitted from V1 (multi-chair; not the launch target).

## 3. Backend — derived, no table, no write path
- `GET /me/subscription` (role **provider**, self-scoped). Resolves the provider
  account via `ProviderAuthRepository.accountById(principal.userId)` → uses its
  `createdAt` as the trial anchor.
- `SubscriptionService.compute({accountCreatedAt, now, trialDays = 90})` — **pure**:
  - `trialEndsAt = accountCreatedAt + trialDays`
  - `now < trialEndsAt` → `{ tier: pro, status: trial, trialEndsAt, trialDaysLeft }` (days left rounded up, ≥0)
  - else → `{ tier: free, status: free, trialEndsAt, trialDaysLeft: 0 }`
- No migration / no `subscriptions` table yet — there is **no billing state** to
  store in V1. The full `Subscription` table (PRD §17.7: seats, addons, renewsAt,
  past_due…) lands with paid billing post-incorporation.
- **Errors:** no principal → 401; non-provider → 403; account missing → 404.
  `405` for non-GET. Standard envelope.

### DTO (`Subscription`) — mirrors the app model
`{ tier: 'free'|'pro', status: 'trial'|'free', trialEndsAt: date-time, trialDaysLeft: int }`

## 4. Security (threat model T25)
Self-scoped read keyed by `principal.userId` (the provider account); **provider
role required**; no id in the path (nothing to enumerate / cross-access). No PII
beyond the caller's own trial dates. Server is authoritative on tier/status
(derived server-side; the client never sets them). Read-only — no money moves.

## 5. App
- `models/subscription.dart` — `Subscription { tier (SubscriptionTier), status
  (SubscriptionStatus), trialEndsAt?, trialDaysLeft }` + `fromJson` (+ helpers
  `isTrialing`, `trialActive`). Enums tolerant of unknown → safe defaults.
- `SubscriptionServiceInterface.getSubscription()` — **Mock** (latency; a trialing
  default) + **ApiProSubscriptionService** (`GET /me/subscription`, **provider**
  `RefreshingHttpClient` with `SecureSessionStore(key: 'myweli_provider_session')`).
- `ProSubscriptionProvider` (ChangeNotifier): `load()` → loading/error/success.
- `ProSubscriptionScreen` ("Mon abonnement"):
  - **Plan badge** — *Pro — essai gratuit* (trialing) / *Découverte (Gratuit)*.
  - **Trial banner** — *« Essai gratuit — X jours restants »* + end date; after →
    *« Essai terminé — vous êtes sur l'offre Gratuite »*.
  - **Tier cards** — Découverte (0) + Pro: anchor **« 70 000 FCFA / mois »** shown
    as the struck/"prix normal" with a prominent **« Gratuit pendant 3 mois »**;
    entitlements checklist per tier.
  - **ROI line** — *« Un seul rendez-vous manqué évité paie le mois. »* (PRD §6.1 binding).
  - **CTA** — *« Nous contacter »* → WhatsApp deep link to Myweli
    (`AppConfig.supportWhatsApp`, set via `--dart-define` at launch; empty →
    graceful *« Contact bientôt disponible »* snackbar). Plus an info line that
    paid plans arrive at launch.
  - **States:** loading · error+retry · success (empty N/A). Tokens only; FR copy.
- **Entry:** a *« Mon abonnement »* tile (`Icons.workspace_premium`) in
  `pro_profile_screen`; route `/pro/subscription` in `pro_router`; provider
  registered in `main_pro.dart`; service in DI (Api when `useApiBackend`, else Mock).

## 6. Tests
- **Backend:** `SubscriptionService.compute` — trialing (days-left rounding, just-
  before/after boundary) · expired → free. Route: provider trialing → 200 shape ·
  non-provider → 403 · anon → 401 · missing account → 404 · non-GET → 405.
- **App:** model `fromJson` (trial/free + unknown enum fallback); mock get;
  provider load success/error; `ApiProSubscriptionService` parse.

## 7. Rollout
Pure additive; **no migration, no config required to run** (trial derives from
signup; pricing/contact are provisional constants/env). Mock unchanged for demo.
When paid billing turns on (post-incorporation): add the `subscriptions` table +
Mobile Money renewal + real upgrade flow (new slice).
