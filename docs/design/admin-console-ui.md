# Admin / ops console — UI design spec (Flutter Web)

| | |
|---|---|
| **Status** | UI-1 (auth + shell + dashboard + KYC) **Built** · moderation / mgmt / disputes / audit UI next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **Backend** | [admin-console.md](admin-console.md) (Slices 1–3 built — the API this UI drives) |
| **PRD ref** | §11.4 (FR-WEB-AD-*), §6.1 (stack — **Flutter Web**, revised from React) |
| **Skills** | myweli-dev-guardrails (UX-first) |

## 1. Goal & scope
Make the admin backend usable by a human. Built as a **3rd Flutter entrypoint** `main_admin.dart` (alongside `main.dart`/`main_pro.dart`) — **Flutter Web**, internal, behind admin login. Reuses the existing models/services/theme/widgets; the admin session is isolated under its own secure key.

**UI-1 (this slice):** admin **login** → app **shell** (nav) → **dashboard** (analytics KPIs) → **KYC approval queue** (list → detail with signed doc viewing → approve / reject). This is the launch-critical workflow end-to-end.

**Later UI slices:** review moderation queue · provider/user management (suspend/ban + support views) · disputes · audit-log viewer.

## 2. UX & flows
- **Login** (`/admin`) — email + password (the seeded super-admin). Loading · invalid-credentials (401) · locked-out (429) · success → `/admin/dashboard`. No self-signup link (seeded only).
- **Shell** — `NavigationRail` (desktop-first): **Tableau de bord**, **KYC**; footer **Déconnexion**. Hosts the routed child. Unauthenticated → redirect to login; authenticated on `/admin` → redirect to dashboard.
- **Dashboard** (`/admin/dashboard`) — KPI cards from `GET /admin/analytics/overview`: users (active/banned), providers (active/suspended), verification (pending/verified/rejected), bookings by status, **no-show + cancellation rates**, open disputes, reported reviews. States: loading · error+retry · loaded.
- **KYC queue** (`/admin/kyc`) — table/list from `GET /admin/kyc` (pending): business name/type, submitted date, doc count → row tap → detail. States: loading · **empty ("Aucune vérification en attente")** · error.
- **KYC detail** (`/admin/kyc/:id`) — `GET /admin/kyc/{id}`: business info + each doc rendered from its **signed `viewUrl`** (tap to enlarge). Actions: **Approuver** (→ confirmed) · **Rejeter** (requires a reason). On success → back to the queue (refreshed) + snackbar. States: loading · per-action loading · error.

**Cross-cutting:** French copy; desktop-first layout (admin = desktop), graceful narrow width; loading/empty/error/success on every screen. Reuses `AppButton`, `AppTextField`, `LoadingIndicator`, `EmptyState`, `TimedCachedImage` (renders the signed doc URLs), theme/colors/text styles.

## 3. Architecture
- **Entrypoint** `lib/main_admin.dart` — `MultiProvider` (AdminAuthProvider, AdminDashboardProvider, AdminKycProvider) → `MaterialApp.router(adminRouter)`. Mirrors `main_pro.dart`.
- **Router** `lib/core/router/admin_router.dart` — go_router; `redirect` on `AdminAuthProvider.isAuthenticated` (refreshListenable). Routes: `/admin` (login), `/admin/dashboard`, `/admin/kyc`, `/admin/kyc/:id`, all under the shell.
- **Service** `lib/services/admin/admin_service.dart` — **one** `AdminService` (the console is small): isolated `SecureSessionStore('myweli_admin_session')` + `RefreshingHttpClient(refreshPath: '/admin/auth/refresh')`. Methods: `login(email,password)` (POST `/admin/auth/login` → save `{token, refreshToken}`), `logout()`, `hasSession()`, `overview()`, `kycQueue({page})`, `kycDetail(id)`, `approveKyc(id)`, `rejectKyc(id, reason)`. Returns `ApiResponse<…>`. Injected (default real) for testability; a process singleton `adminService` wires the screens.
- **State** `lib/providers/admin/` — `AdminAuthProvider` (isAuthenticated/isLoading/error/login/logout/restore), `AdminDashboardProvider` (overview), `AdminKycProvider` (queue/detail/approve/reject). `ChangeNotifier` + scoped `Consumer`.
- **Data shape:** admin responses are admin-specific JSON; UI-1 reads them **map-driven** (typed models add little for an internal tool and a lot of classes) — documented exception to the typed-DTO guideline; revisit if the console grows.

## 4. Security
- Admin session under its **own** secure key (`myweli_admin_session`) — never mixed with consumer/provider sessions. Tokens in `flutter_secure_storage` (never logged).
- All data calls carry the admin bearer via `RefreshingHttpClient` (silent refresh on 401 at `/admin/auth/refresh`); the backend enforces `role=admin` (deny-by-default) + audits every mutation — the client is never the authority.
- No self-signup; login is the only unauthenticated screen. Reject reasons are surfaced to the provider by the backend.

## 5. Testing
- `AdminService` (MockClient): login posts to `/admin/auth/login` + saves session; data calls send the bearer + parse; 401→refresh→retry inherited from `RefreshingHttpClient`.
- `AdminAuthProvider`: login success → authenticated; bad creds → error, not authenticated; logout clears.
- `AdminKycProvider`: queue load; approve/reject update + surface errors.
- `flutter analyze` 0; **`flutter build web`** compiles the admin target; widget smoke for login + dashboard states.

## 6. Definition of done
- [ ] `flutter analyze` 0 · `flutter test` green · `flutter build web --target lib/main_admin.dart` succeeds.
- [ ] All four states per screen; French copy; admin session isolated.
- [ ] Spec cross-linked; ROADMAP updated; PRD §6.1 reflects Flutter Web. Feature branch + PR; CI green; no Claude attribution.

## 7. Decisions (signed off)
1. **Flutter Web**, `main_admin.dart` entrypoint, reusing the existing stack (overrides PRD's React note; §6.1 updated). ✓
2. **UI-1 = auth + shell + dashboard + KYC queue**; moderation / mgmt / disputes / audit are later UI slices. ✓
3. One `AdminService` + map-driven reads for the console (documented exception). ✓

## 8. Open questions
_None._
