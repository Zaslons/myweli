# Web M7.3e — pro Profil + Acompte + Médias

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001, M7.3e ([web-m7-3-catalogue.md](web-m7-3-catalogue.md)). The **last pro slice**. |
| **Mirrors** | the app's `/pro/profile` (read-only card + links), `/pro/deposit-settings`, `/pro/photos` + `/pro/before-after`. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **7.3e-i built** — **editable** Profil (new backend `PATCH /providers/{id}`, threat **T30**) + Acompte (deposit policy) + home « Configurer mon profil » nudge. Backend +2 tests; web +8 unit + 1 e2e. **7.3e-ii Médias pending.** |

## 0. Sub-split
- **7.3e-i — Profil (read-only) + Acompte** *(this PR)*.
- **7.3e-ii — Médias** (Photos du salon + Avant/Après) — needs image upload; the
  upload approach is decided then.

## Decision update (owner): Profil is **editable** on web
The app's Profil is read-only (editing via onboarding) and `/providers/{id}` was
GET-only. The owner wants web Profil **editable**, so 7.3e-i adds a backend
**`PATCH /providers/{id}`** (owner-only; field allowlist name/description/address/
city/commune/phoneNumber/whatsapp; threat **T30**) and the web Profil is a form,
not a read-only card. Protected fields keep their own endpoints.

---

# 7.3e-i — Profil (read-only) + Acompte

## 1. Profil `/pro/profil` (read-only, mirrors the app)
- Sidebar "Profil" → live. Authed gate as M7.0.
- **Read-only salon card** from `GET /me/provider` (`account`): Nom de l'entreprise,
  Type, Adresse, Téléphone, **statut de Vérification**.
- **Section links** (cards), mirroring the app's Profil hub: **Acompte**
  (`/pro/acompte`), **Abonnement** (`/pro/abonnement`), **Médias** (`/pro/medias`,
  lands in 7.3e-ii). Déconnexion already lives in the sidebar.
- A note: « Pour modifier ces informations, utilisez l'app Myweli Pro. » (editing =
  onboarding, app-side) — flagged, with the app push.
- **Home nudge:** add the deferred « Configurer mon profil » nudge to `/pro` →
  links here.

## 2. Acompte `/pro/acompte` (deposit policy, editable)
- Reached from Profil. Mirrors the app's « Acompte » screen.
- Form: **Exiger un acompte** (toggle). When on → **Pourcentage** (0–100 % →
  stored 0..1), **Politique d'annulation** (fenêtre, heures, 0..720), **Opérateur
  Mobile Money** (Wave / Orange Money / MTN MoMo / Moov), **Numéro Mobile Money**
  (E.164). **Enregistrer**.
- Validation (client, server re-validates): when required → % > 0, operator +
  number present; number looks E.164; window 0..720.

## 3. Data (no backend change)
- Profil load = `GET /me/provider` (account already returned; extend the web
  `account` type with businessType/address/verificationStatus).
- Acompte load = `GET /api/pro/acompte?providerId=` → `GET /providers/{pid}/deposit-policy`;
  save = `PUT /api/pro/acompte` → `PUT /providers/{pid}/deposit-policy`. Client sends
  its own `providerId`; backend enforces ownership + re-validates. (DepositPolicy DTO:
  `{depositRequired, depositPercentage, cancellationWindowHours, mobileMoneyOperator,
  mobileMoneyNumber}`.)

## 4. States
Profil: loading · error · success (read-only). Acompte: loading · error · success
(toast) · validation.

## 5. Security
Pro httpOnly cookies + `callApiPro` (one call/request); deposit policy owner-only
server-side; client passes its own `providerId` (authz server-side). `/pro/*` `noindex`.

## 6. Tests
- **Unit:** `validateDeposit` (required → % > 0 + operator + number; window range) +
  percent↔fraction conversion + operator labels.
- **e2e:** provider → `/pro/profil` shows the salon card + links; → `/pro/acompte`
  toggle on, set %, operator, number → **Enregistrer** → success. Stub:
  `GET/PUT /providers/{id}/deposit-policy`; `account` fields on `/me/provider`.

## 7. Open questions (proposed defaults)
- **OQ-7.3e-1** Profil = **read-only** (editing stays in the app/onboarding; no
  endpoint) → default.
- **OQ-7.3e-2** Acompte here (7.3e-i); **Médias → 7.3e-ii** (upload decision then) → default.
- **OQ-7.3e-3** Deposit % entered as **0–100** in the UI, stored as 0..1 → default.
