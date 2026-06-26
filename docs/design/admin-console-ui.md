# Admin / ops console — UX & design plan (Flutter Web)

| | |
|---|---|
| **Status** | UX signed off · UI-2a/2b · UI-3a/3b (mgmt + support views) · **UI-4 Built** (disputes: list + detail with deposit-evidence + résoudre; open-from-booking) · audit-log viewer next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **Backend** | [admin-console.md](admin-console.md) (Slices 1–3 — the API this UI drives) |
| **PRD ref** | §11.4 (FR-WEB-AD-*), §6.1 (stack — **Flutter Web**) |
| **Skills** | myweli-dev-guardrails (**UX-first**: plan + sign-off before code) |

> **Why this doc exists.** UI-1 (login + dashboard + KYC, PR #88) was shipped functional but **without a real UX/design pass or sign-off** — a process miss. This plan defines the admin **design system** and every screen's UX *first*, gets sign-off, then UI-1 is reworked to it and the remaining screens are built to the same bar.

## 1. Principles & fit with the app's identity
The app is **minimalist monochrome**: pure-black primary (`#000`), white / very-light-gray surfaces (`#FAFAFA`, `#F5F5F5`, bg `#F6F7F9`), muted-dark semantic colors (success `#2D5016`, error `#8B0000`, warning `#6B5B00` + lighter variants), semibold headlines, spacing 4/8/16/24/32, radius 12 default. **The admin reuses these exact tokens** — same `AppColors`/`AppTextStyles`/`AppTheme` — so it reads as "Myweli, for the team."

The admin is **not a phone screen blown up**. It's an **internal desktop tool**, so the design optimizes for:
- **Scannability & density** — operators triage queues fast → **data tables**, not stacked cards.
- **A persistent frame** — sidebar + top bar always visible; content scrolls.
- **Status at a glance** — consistent **status chips** (verified/pending/suspended/open) in the semantic palette.
- **Safe, reversible actions** — destructive actions (suspend, hide, reject) confirm + take a reason; everything's audited server-side.
- **Calm monochrome** — black/white/gray dominates; color is reserved for **status + the single primary action**, never decoration.

## 2. The admin design system
**Layout (desktop-first):**
- **Sidebar** (240px, white, right border): wordmark "Myweli · Admin" → nav groups (**Vue d'ensemble**; **Modération**: KYC, Avis; **Marché**: Salons, Clients, Litiges; **Journal**: Audit) → footer: admin email + Déconnexion. Active item = black text + a 3px black left rule on `surfaceVariant`.
- **Top bar** (64px): current page title (`headlineSmall`) left; contextual actions (search/refresh/filter) right; thin bottom divider.
- **Content** (`background` `#F6F7F9`, padding 32): a max-width ~1200 column; cards/tables on white with `border` + radius 12.
- **Responsive:** desktop-first. < ~1000px → sidebar collapses to icons; tables become horizontally scrollable. (Admin use is desktop; this is graceful-degrade, not a mobile redesign.)

**Components (shared admin widgets):**
- **`AdminScaffold`** — the sidebar + top-bar frame; every screen is a body inside it.
- **`StatCard`** — KPI: big value (`headlineMedium`), label (`bodySmall` secondary), optional accent for attention metrics (pending KYC, open disputes, no-show rate). White, border, radius 12.
- **`AdminDataTable`** — the workhorse: header row (`labelMedium`, tertiary), zebra-free rows with a 1px divider, row hover = `surfaceVariant`, right-aligned actions, click-row → detail. Built-in **states**: loading (skeleton rows), empty (icon + title + line), error (line + Réessayer). Footer: "X résultats · page N" + prev/next.
- **`StatusChip`** — pill, semantic color on a light tint: `vérifié`/`actif` (green), `en attente`/`ouvert` (amber), `rejeté`/`suspendu`/`banni`/`masqué` (red), neutral (gray).
- **`PageHeader`** — title + optional subtitle + right-aligned filter/segment control.
- **`ConfirmDialog` / `ReasonDialog`** — standard confirm; reason variant for reject/suspend/hide (textarea + required/optional rule).
- **Buttons:** reuse `AppButton` (primary = black, secondary = outline, text). One primary action per context.
- **States everywhere:** loading (skeleton), empty (EmptyState), error (retry), success (snackbar). No raw spinners on data tables.

**Interaction standards:** server-side pagination (50/puis "Charger plus" or prev/next); destructive actions always confirm; success → snackbar + optimistic row removal from queues; French copy throughout; keyboard: Enter submits dialogs, Esc cancels.

## 3. Screens (flow · states · copy)
Every screen lives in `AdminScaffold`. States = loading · empty · error · success unless noted.

1. **Login** (`/admin`, no frame) — centered card on `background`: wordmark, email, password, "Se connecter". States: idle · loading · `Identifiants invalides` (401) · `Trop de tentatives, réessayez plus tard` (429). No signup.
2. **Vue d'ensemble** (`/admin/dashboard`) — `PageHeader` + a **StatCard grid** (responsive wrap): Rendez-vous total/terminés, **Taux de no-show** (accent), Taux d'annulation, **KYC en attente** (accent, → KYC), Salons vérifiés/actifs/suspendus, **Litiges ouverts** (accent, → Litiges), Avis signalés (→ Avis), Clients actifs/bannis. Below: a compact **"À traiter"** panel linking the open queues with counts. (North-Star chart is a later add.)
3. **KYC** (`/admin/kyc`) — `AdminDataTable`: Salon · Type · Soumis le · Documents · (row →). Empty: "Aucune vérification en attente." Row → **detail** (`/admin/kyc/:id`): a two-column layout — left: business info + status chip; right: **document thumbnails** (signed view URLs, click → lightbox). Sticky action bar: **Approuver** (primary) · **Rejeter** (secondary → `ReasonDialog`, reason required). Success → toast + back to the (refreshed) queue.
4. **Avis (modération)** (`/admin/reviews`) — a **segmented** screen with two tabs (`AdminDataTable` each):
   - **Signalés** — reported reviews from `GET /admin/reviews/reports`: rating · review (truncated, + reporter + last reason) · report-count chip (amber 1 / red 2+) · inline **Masquer** (→ `showReasonDialog`, reason optional → `hide`) / **Ignorer** (→ `dismiss`). Empty: "Aucun avis signalé."
   - **Masqués** — hidden reviews from **`GET /admin/reviews/hidden`** (new backend read): rating · review · the salon · inline **Restaurer** (→ `restore`, back to feed + rating). Empty: "Aucun avis masqué."
   Acted rows drop out optimistically + snackbar. Signed off (mockup) incl. the hidden/restore view (UI-2b).
5. **Salons** (`/admin/providers`) — table: Salon · Commune · Statut (chip) · Note · actions; filter (Tous/Actifs/Suspendus) + search. Row → detail: profile + recent bookings + **Suspendre/Réactiver** (reason) + **Mettre en avant** toggle. *(later UI slice)*
6. **Clients** (`/admin/users`) — table: Nom · Téléphone · Statut · actions **Bannir/Réactiver** (reason); filter + search. Row → detail + recent bookings. *(later UI slice)*
7. **Litiges** (`/admin/disputes`) — table: Réservation · Statut · Ouvert le · Motif; row → detail (booking + signed deposit screenshot evidence) + **Résoudre** (resolution). *(later UI slice)*
8. **Audit** (`/admin/audit`) — read-only table of admin actions: Date · Admin · Action · Cible · Motif; filter by admin/action. *(later UI slice)*

## 4. UI-1 rework (what changes vs. what shipped)
UI-1 stays functionally correct but is **reworked to this system**:
- `NavigationRail` → the **sidebar** (`AdminScaffold`) with groups + admin identity + logout in the frame (not a rail trailing icon).
- KYC queue: mobile **ListTile cards → `AdminDataTable`** (columns + states + pagination footer).
- KYC detail: ad-hoc column → the **two-column + sticky action bar** layout; reject dialog → `ReasonDialog`.
- Dashboard: loose `Wrap` of cards → `StatCard` grid + the **"À traiter"** panel; accent only on attention metrics.
- Introduce the shared `AdminScaffold`/`StatCard`/`AdminDataTable`/`StatusChip` widgets (UI-1 screens refactor onto them).

## 5. Build sequencing (after sign-off)
- **UI-2a — design system + UI-1 rework:** `AdminScaffold`, `StatCard`, `AdminDataTable`, `StatusChip`, `PageHeader`, dialogs; refactor login/dashboard/KYC onto them. *(no new backend surface)*
- **UI-2b — moderation** (Avis) on the new system.
- **UI-3 — Salons + Clients management.**
- **UI-4 — Litiges + Audit.**

## 6. Security / a11y (carried)
Admin session isolated (`myweli_admin_session`), tokens in secure storage, all calls bearer-authed (backend enforces `role=admin` + audits). a11y: focus order, dialog focus trap, ≥4.5:1 contrast (the monochrome palette passes), tooltips on icon-only controls.

## 7. Decisions
1. **Flutter Web**, `main_admin.dart`, reuse app tokens (§6.1 updated). ✓
2. Desktop **data-table-centric** design system reusing the monochrome identity (not a blown-up mobile layout). **← needs sign-off**
3. **Rework UI-1** (dashboard + KYC) onto the new system. **← needs sign-off**
4. Sequencing UI-2a (system + rework) → moderation → mgmt → disputes/audit. **← needs sign-off**

## 8. Open questions
1. Sidebar grouping/labels (above) OK, or flat list?
2. Density: comfortable (rows ~52px) vs compact (~40px) — recommend **comfortable**.
3. North-Star chart on the dashboard now or a later "Analytics" page — recommend **later**.
