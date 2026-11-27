# MyWeli (client) — release-readiness audit, App Store and Google Play

| | |
|---|---|
| **Status** | **Audit, read-only. §7's order approved by the owner on 2026-11-23, as written** (BACKLOG decision 160). §8 Q1, Q2, Q3 and Q5 are open (decisions 161–164). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **Read at** | `main` `d0a31d63` (2026-11-22). Read-only: no code changed, no test or build run, no device, no console, no production call. |
| **Scope** | The consumer app only: flavour `consumer`, entry `mobile/lib/main.dart`, `com.myweli.app`, « MyWeli ». Not MyWeli Pro. |
| **PRD ref / phase** | PRD §9 (every consumer `[V1]` requirement) · V1 · BACKLOG decision 51 · [play-store-forms.md](play-store-forms.md) §8 |
| **Module** | `online-booking` (MODULES §2), with `notifications`, `payments`, `trust` |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [android-play-release.md](android-play-release.md) (Pro's Play path, the template) · [app-store-forms.md](app-store-forms.md) (Pro's App Store packet) · [mobile-store-submission.md](mobile-store-submission.md) · [android-http3-transport.md](android-http3-transport.md) §8 step 6 · [apple-signin-keys.md](apple-signin-keys.md) §9 step 7 · [web-flow-audit-2026-11.md](web-flow-audit-2026-11.md) · [mobile-external-testing.md](mobile-external-testing.md) |

---

## 0. The answer

**Not ready.** The engineering is close, but three kinds of work are left, and
one gate sits outside the code entirely.

1. **The app says things that are not true.** On every home screen it shows
   three hard-coded « stories », among them « -15% sur une sélection de salons ·
   Offre limitée · Jusqu'à dimanche » and a « Nouveau salon » called « Beauté
   Divine · Marcory · Zone 4 ». Neither exists. The cancel dialog promises
   « Votre acompte … sera remboursé ». MyWeli refunds nothing (BACKLOG B12.11).
   Smaller untrue things are listed in §6.
2. **Some V1 requirements are not met in the app, though the ROADMAP marks them
   ✅ « verified »** (ROADMAP §1.8):
   - the search bar does not search (FR-DISC-004);
   - the categories are « Tous, Barbier, Salon, Spa », not the Ivorian taxonomy
     (FR-DISC-003);
   - the salon page has no staff section (FR-DISC-006);
   - the appointment detail shows no status, salon, services, address or
     directions (FR-APPT-002, FR-APPT-006);
   - bookings the salon entered never reach a new account (FR-APPT-008), because
     only phone OTP verifies a phone, and phone OTP is off.

   Most of the rest is built, wired to the real API, and tested (§2).
3. **Nothing store-side exists for this app.** There is no App Store packet, no
   up-to-date Play packet, no screenshots, and no consumer build of today's
   code. No consumer build has been run on a phone either. Three things can only
   be proven on such a build:
   - Sign in with Apple for `com.myweli.app`;
   - iOS push through this app's APNs key;
   - the Cronet transport on Android.

   On Play, Google probably requires a second 12-tester, 14-day closed test for
   this app (§3.3, INFERRED).
4. **The gate outside the code: production has no public salon.** The last
   recorded read is `GET /providers` → 0, on 2026-11-12
   ([salon-go-live-approval.md](salon-go-live-approval.md):31). Decision 51
   holds this app until salons are public. A reviewer would open an empty
   marketplace, which is the 2.1 / 4.2 risk on Apple's side.

**How big is the work.**
- **Code:** about six PRs, all S or M, none of them L (§7).
- **Store packets:** one L of documents and guards, plus the screenshots.
- **Builds and device passes:** the owner's time, on each « yes ».
- **The salons:** outside the code, and on the critical path.

Everything before the submissions can run in parallel with signing the first
salons up.

---

## 1. How this was read

- **Sources:** the specs named above, the PRD, the ROADMAP, MODULES, the
  BACKLOG and LAUNCH, then the code at `d0a31d63`.
- **Two research passes** read the code wide: the consumer features, and the
  backend and web dependencies. **Every finding ranked in §6 was then re-read in
  the code by the author of this file.** Two smaller findings come from the
  research passes alone and are marked †.
- **Evidence:** every line cites a file and line, a test, or a document. Paths
  under `lib/`, `test/`, `android/` and `ios/` are under `mobile/`. Anything
  that depends on a console, a device or production is marked **UNVERIFIED**,
  and §9 says how it would be checked.
- **Not done:** no `flutter test`, no build, no device, no console, no
  production read. A claim about « what a reviewer sees » is reasoned from the
  code, not observed.

---

## 2. Features against the V1 scope

Legend: ✅ built and wired to the real API · 🟡 built, with a gap · ❌ not met.
« Real API » means the `Api*Service` the release build injects
(`lib/core/di/dependency_injection.dart:103-297`, `USE_API_BACKEND=true` in
`tool/release_build.sh:211`). The one service that stays a mock in release,
`MockMessagingService` (`dependency_injection.dart:263`), is inert: it only fills
an in-memory outbox nobody reads (`booking_confirmation_screen.dart:113-127`).

### 2.1 Discovery, search and the map

| Req. | State | Evidence |
|---|---|---|
| FR-DISC-001 home hub | 🟡 | `screens/home/home_screen.dart`. Featured, « Près de vous », favourites strip, recent bookings, all on `GET /providers` (`services/api/api_provider_service.dart:34-62`). **The three stories are hard-coded** (`widgets/home/announcement_stories.dart:48-71`; the texts are in `assets/images/stories/*.svg`), shown at `home_screen.dart:173`. |
| FR-DISC-002 commune filter | ✅ | `provider_list_screen.dart:105-113`, saved on the device (`providers/provider_provider.dart:160-182`) |
| FR-DISC-003 CI taxonomy | ❌ | `widgets/home/category_chips.dart:12-17`: Tous, Barbier, Salon, Spa. No tresses, onglerie or massage (BACKLOG B12.8, audit A2) |
| FR-DISC-004 search | ❌ | « Rechercher un salon… » only opens the list (`home_screen.dart:121-123`, `widgets/home/search_bar.dart`). The list has no text field, and no screen passes `searchQuery` (only `provider_provider.dart:124,135`). The server takes `q` (`backend/routes/providers/index.dart:21-28`). BACKLOG B12.8, audit A1 |
| FR-DISC-005 map | 🟡 | `screens/map/map_screen.dart`, CARTO key (`core/map/carto_basemap.dart`), attribution :447. Location is asked as soon as the map opens, with no explanation first (:139-142). After a permanent refusal, « Activer » re-runs the same check and never offers the Settings (:144-151) †. The map shows only page 1 of the current commune, with no sign of the filter (:364-371) |
| FR-DISC-006 salon page | 🟡 | §2.2 |
| FR-DISC-007 sort and filter | 🟡 | Sort: Pertinence, Mieux notés, Prix croissant (`services/interfaces/provider_service_interface.dart:7-11`); « Disponible aujourd'hui » (`provider_list_screen.dart:143-157`). No home-service filter (V2 by PRD §7.4, so not a gap) |
| Pagination | 🟡 | the app never asks for page 2 (`provider_provider.dart`: no `page:` argument; `api_provider_service.dart:31-32` defaults to page 1, 20 salons). Home, list and map show at most 20 salons |

**States.** The list has all four (`provider_list_screen.dart:235-257`). Home
« Près de vous » has all four (`home_screen.dart:436-460`), and its empty state
is a bare « Aucun salon trouvé » with no action. The map has no loading, empty
or error state for its salons.

**With zero public salons** (production today), a visitor sees:
- **home:** the search bar, the three invented stories, the chips, and « Aucun
  salon trouvé »;
- **the list:** « Essayez de modifier vos critères de recherche », though there
  is no search;
- **the map:** an empty Abidjan, with no message.

**Accessibility.**
- At 200 %, `test/a11y/layout_test.dart` checks the home, the list's filter row
  and its grid, and `text_scale_test.dart` checks the chips and cards.
- The home profile button is an `InkWell` around an icon, with no label
  (`home_screen.dart:126-147`).
- No consumer screen is run through `labeledTapTargetGuideline`.

**Tests.**
- The home has `home_review_figures_test.dart` and `account_switch_test.dart`.
- **The list has no widget test**, and the map's location path is untested.
- Goldens cover the home and the home at 360 × 200 %. The list and the map have
  none.

### 2.2 The salon page — `screens/providers/provider_detail_screen.dart`

**Built** (`GET /providers/{id}`, `api_provider_service.dart:77-99`):
- the cover and gallery, with pinch-zoom (`InteractiveViewer` :1369);
- services with duration, short/medium/long variants and a price range;
- hours (:900), the map with « Itinéraire » (:702, :765), « Appeler » (:791) and
  WhatsApp through `wa.me` (:824-845);
- the verified badge (:1796), before/after (:1000) and five reviews with
  « Signaler » (:1006-1035, :202-235);
- the favourite heart (:285);
- the sticky « Réserver » bar (:1219-1242);
- « Vos rendez-vous ici », with rebook (:536-620).

**Missing:**
- **No staff section.** The file never reads the salon's artists; its only
  « artist » mentions are the rebook's `artistId` (:608) and the review's
  `artistName` (:1089). FR-DISC-006 lists staff, and the web shows them
  (`web/components/provider/ProviderView.tsx:197-201`).
- Reviews stop at five, with no full list.
- A guest who taps « Signaler » gets a snack, with no way to sign in (:204-206) †.

**States:** a skeleton, `SalonUnavailableView`, the data; an empty line each
for photos, services and reviews.

**Tests and goldens:**
- six widget tests: `salon_landing_states`, `photo_lightbox`, `salon_cover`,
  `salon_location_map`, `salon_visits_card` and `…_none`;
- `a11y/salon_header_test.dart`, and `layout_test` with and without photos;
- three goldens.

### 2.3 Booking and the deposit (no custody)

| Req. | State | Evidence |
|---|---|---|
| FR-BOOK-001…006 hub | ✅ | `screens/booking/booking_hub_screen.dart`; `GET /availability` (`api_appointment_service.dart:281-310`). `lengthVariant` is shown but not sent to the server (a PRD follow-up) |
| FR-BOOK-007 confirm + deposit | ✅ | `booking_confirmation_screen.dart`; `POST /appointments` with an idempotency key (`api_appointment_service.dart:80-95`) |
| FR-PAY-001…004 no custody | ✅ | `widgets/booking/deposit_payment_sheet.dart`. Wave: `https://pay.wave.com/?recipient=…&amount=…` (`core/utils/mobile_money.dart:7-13`). Other operators: « Copier ». Proof: `POST /uploads/sign {purpose: deposit}`, then a `PUT` to R2 (`api_appointment_service.dart:121-154`). Paying later: `POST /appointments/{id}/deposit` |
| FR-PAY-005 refunds are salon↔client | ❌ in the copy | §2.4: the cancel dialog promises a refund |
| FR-BOOK-008 auth gate + `returnTo` | 🟡 | `booking_confirmation_screen.dart:71-97`. **Every way into sign-in uses `context.go`** (:93; and `provider_card.dart:220`, `provider_detail_screen.dart:300`, `map_screen.dart:281`, `profile_screen.dart:74,178`, `my_bookings_screen.dart:52`), which replaces the stack. The sign-in screen has no back or close button (`login_screen.dart:219`). A guest who taps a heart cannot get back to the salon without signing in; on iOS there is no system back |
| FR-BOOK-009 / FR-REBOOK-001 rebook | 🟡 | from history (`my_bookings_screen.dart:244,280-291`) and the salon page; `test/unit/rebook_test.dart`. Not on home or on the detail, which FR-REBOOK-001 asks for |
| Policy shown before booking | 🟡 | the cancellation policy appears only on the appointment detail, never before booking |

**Note on the deposit flow.** The booking is created only when the client taps
« J'ai payé l'acompte » (`deposit_payment_sheet.dart:247-256`). If that call
fails after a Wave payment (the slot was taken meanwhile), the money is already
with the salon, and nothing on screen says what to do. No-custody makes that the
salon's matter, but the screen should say so.

**Tests:**
- widget: `deposit_payment_sheet_test`, `slot_picker_test`, `push_permission_sheet_test`;
- unit: `deposit_test`, `deposit_handle_test`, `api_appointment_service_test`;
- `layout_test` for the hub and the confirmation;
- a golden for the hub only. The confirmation and the deposit sheet have none.

**UNVERIFIED:** whether Wave honours the pre-filled recipient and amount. The
repo only tests the URL string (`web/tests/mobile-money.test.ts:45`).

### 2.4 My bookings, detail, cancel and reschedule

| Req. | State | Evidence |
|---|---|---|
| FR-APPT-001 tabs | 🟡 | « À venir / Passés / Annulés » (`screens/appointments/my_bookings_screen.dart:95-135`). Three gaps: **a no-show appears in no tab** (`providers/appointment_provider.dart:80-103`: not upcoming, not cancelled; « Passés » lists `visitHistory`, which keeps only `completed`, `core/utils/visit_history.dart:9-32`); **a past booking the salon never confirmed reads « Terminé »** (`visit_history.dart:15-17` turns every past non-cancelled booking into `completed`. Its comment calls this « a placeholder until the backend sends real completion / no-show events », which it now does); and **cards show « Salon »** whenever the salon is not on the discovery page in memory (`widgets/booking/appointment_card.dart:39-48,119` reads `providerProvider.providers`, not `appointment.providerName`, which the server sends, `models/appointment.dart:79`; the home tiles do the same, `home_screen.dart:321-339`) |
| FR-APPT-002 detail | ❌ | `appointment_detail_screen.dart:408-525`: « Informations du rendez-vous » shows date, time, specialist, total, deposit and balance, notes. **No status, no salon name, no services, no address.** The salon's name reaches only the deposit sheet (:237) and the calendar event (:360) |
| FR-APPT-003 / 005 cancel | ❌ in the copy | `appointment_detail_screen.dart:147-157`: « Votre acompte de X sera remboursé » outside the window, even when no proof was sent. The web already uses the salon's rule (`web/lib/account/appointments.ts`, web-true-sentences.md §3). B12.11 |
| FR-APPT-004 reschedule | ✅ | `reschedule_screen.dart`, pushed from « Reporter » (`appointment_detail_screen.dart:201`), hidden when the salon is not live; `POST …/reschedule`; `reschedule_screen_test.dart` |
| FR-APPT-006 calendar + directions | 🟡 | « Ajouter au calendrier » (:356). **No directions on this screen.** PRD §9.5 says they are built, and the research pass's `git log -S` finds no « Itinéraire » ever in `screens/appointments` |
| FR-APPT-008 auto-sync | ❌ in production | The server matches only a **verified** phone (`backend/routes/appointments/index.dart:101-115`). A phone saved in the app is set unverified (`backend/lib/src/db/postgres_auth_repository.dart:358`, « A changed email/phone is unverified until proven again »). Only the phone-OTP path verifies one (`backend/lib/src/db/postgres_auth_repository.dart:396-404`), and production disables it (`AUTH_METHODS=google,apple,email`, `infra/gcp/service.yaml:127-128`). The badge exists (`appointment_card.dart:246-247`) but cannot fire for any account made today |
| FR-APPT-009 visit history | 🟡 | grouped history with rebook; shares the « Terminé » defect above |

**Tests:**
- widget: `appointment_detail_states`, `…_artist`, `…_stopped`, `reschedule_screen`;
- unit: `cancellation_policy_test`, `appointment_provider_test`;
- a golden for « my bookings » at 200 % only;
- **no test pins the cancel sentence.**

### 2.5 Reviews and favourites

- **Reviews** ✅ (FR-REV-001…005):
  - `widgets/review/submit_review_sheet.dart`, offered only after a booking that is really `completed` (`appointment_provider.dart:118-130`);
  - up to three photos (`POST /uploads/sign {purpose: review}`);
  - `POST /appointments/{id}/review`, and « Signaler » → `POST /reviews/{id}/report`;
  - the specialist comes from the booking (FR-REV-003);
  - tests: `submit_review_sheet_test`, `review_submit_test`, `api_review_service_test`, and the tap target in `a11y/tap_target_test.dart`.
- **Favourites** ✅ (FR-FAV-001):
  - the heart on the card, the salon page and the map sheet; `GET/POST/DELETE /me/favorites`;
  - listed in the home strip and on the map. The list screen was deleted on purpose (PRD FR-FAV-001);
  - the map shows only favourites on page 1 of the current commune.

### 2.6 Notifications and push

- **The centre** ✅ (FR-NOTIF-002):
  - `screens/notifications/notifications_screen.dart` over the shared `NotificationsList`, with all four states;
  - signed out, the « Actu » tab shows an error, « Non connecté », and only « Réessayer » (`api_notification_service.dart:46-48`) †;
  - the tab has no unread badge.
- **Preferences** ✅ (FR-NOTIF-004): `notification_preferences_screen.dart`, `GET/PUT /me/notification-preferences`.
- **Push** 🟡 (FR-NOTIF-001):
  - `core/push/push_registration.dart:41-64` asks once, after a first booking;
  - **« Plus tard » marks the device as asked for good** (:55-57), and nothing else calls `requestPermission()` (grep);
  - on iOS the system prompt was then never shown, so Settings has no switch to turn on: that iPhone never gets push (iOS's behaviour for an app that never asked; not observed on a device);
  - taps route through the allowlist `/appointment/`, `/bookings`, `/notifications` (`core/push/push_message_handler.dart:27-31`).
  - **SMS and WhatsApp** are off in production until the company is registered. Reminders reach clients as push and in-app notifications (PRD §7.1, [promise-honesty-sweep.md](promise-honesty-sweep.md)). That is a decision, not a gap.
- **Tests:** `notifications_read_revert`, `notification_tile`, `push_blocked_banner`, `push_registration`, `push_message_handler`, `di_push_wiring`. **No goldens.**

### 2.7 Profile, data export, account deletion

- **Profile** 🟡 (`screens/profile/profile_screen.dart`):
  - **« Langue » answers « Fonctionnalité à venir »** in release (:101-107);
  - support opens `myweli.com/support`; « À propos » lists the three legal documents and the deletion page (`about_screen.dart:81-119`, its accessibility still unasserted, SYSTEM §21 row 49).
- **Edit** ✅ (FR-AUTH-004):
  - name, optional e-mail, phone marked « Non vérifié »; avatar through `purpose=avatar`, then `PATCH /me`;
  - there is no « remove photo »;
  - the app never re-reads `GET /me`, so an edit made on the web shows only at the next sign-in †.
- **Export** ✅ (FR-AUTH-005): built on the device and copied to the clipboard (`core/utils/data_export.dart:15-45`). There is no server route, by design. It leaves out reviews and preferences.
- **Deletion** ✅ (FR-AUTH-005, App Store 5.1.1(v), Play):
  - Profil → « Supprimer mon compte », with the typed word « SUPPRIMER » (`profile_screen.dart:138-145,215-237`);
  - `DELETE /me` (`api_auth_service.dart:441-455`); a future booking blocks it with a 409 `future_bookings`, explained in French;
  - every account store is reset (`AccountScope`, [consumer-account-scope.md](consumer-account-scope.md));
  - tests: `account_delete_test`, `account_scope_test`, `profile_screen_test`. **No test drives the consumer « SUPPRIMER » dialog end to end.**
- **No goldens and no 200 % layout test** for profile, edit, export or about.

### 2.8 Sign-in

- **Google, e-mail code, Apple** ✅:
  - `screens/auth/login_screen.dart`; `/auth/google`, `/auth/email/otp/*`, `/auth/apple`;
  - Apple shows on iOS only (`login_screen.dart:61-62`, `FeatureFlags.appleSignIn` on by default) — App Store 4.8 is met;
  - tests: `login_screen_test`, including Apple shown on iOS and hidden on Android, and `apple_error_1000_test`.
- **Phone OTP was replaced by decision, not left unbuilt**: [app-auth-social.md](app-auth-social.md) (phone becomes contact data). PRD FR-AUTH-001/002 still say phone OTP (§10).
- **« Votre numéro de téléphone »** is required after a sign-in with no phone (`login_screen.dart:75-83,373-419`; tested). The session is already saved by then, so closing the app skips the step †.
- **Session:** restored from secure storage, renewed on a 401; a refused renewal ends it with a notice (`widgets/common/session_ended_notice.dart`). Signing out is local: no server route revokes the refresh token †.
- **Dormant:** `phone_login_screen.dart` and `otp_verify_screen.dart` are imported by nothing in `lib/`, so they are not compiled in (SYSTEM §21 row 53).

### 2.9 Design-system register and goldens

- **Open rows of SYSTEM §21 that touch consumer code:**
  - 30: no undo for cancel or delete;
  - 36: text not externalised, deferred by decision;
  - 47: raw link calls;
  - 49: the about screen;
  - 53: the dormant phone screens;
  - 98: `SectionHeading` is not a heading.
- **Goldens** (`test/golden/consumer_screens_golden_test.dart`): home (+200 %), salon page (+ no photo, +200 %), booking hub, my bookings at 200 %, login.
- **No golden** for the list, the map, the confirmation, the deposit sheet, the appointment detail, reschedule, the notification centre and preferences, the four profile screens, the splash, the stories or the review sheet.
- **Copy:** no hard-coded English and no `TODO`/`FIXME` in `lib/` (grep).

### 2.10 Against the consumer web

- **The web has, the app lacks:**
  - text search (`web/app/recherche`);
  - the nail and massage categories;
  - the staff section;
  - the true cancel sentence;
  - no-shows shown;
  - landing pages by service and commune.
- **The app has, the web lacks:**
  - push;
  - « Me localiser »;
  - avatar and e-mail editing (C10);
  - grouped visit history with inline rebook (C7);
  - the deposit's balance and « Copier » (C9);
  - the returning client's home (C5).

  These are tracked in BACKLOG B12.5–B12.7.
- **Both are wrong about past unconfirmed bookings, in opposite directions:** the
  web keeps them in « À venir » (audit C4), the app calls them « Terminé ». One
  rule should fix both.

---

## 3. Release plumbing, store by store

Legend: ✅ in place and evidenced · 🟡 in place, never observed on a consumer
artifact · ❌ missing · ❓ UNVERIFIED (a console or a device).

### 3.1 Shared with Pro — what Pro's release already exercised

| Item | Consumer | Evidence |
|---|---|---|
| Identity | ✅ `com.myweli.app`, « MyWeli » | `android/app/build.gradle.kts` flavour `consumer`; `ios/tool/setup_flavours.rb:69-78` |
| Entry point | ✅ `lib/main.dart` on both platforms | `tool/release_build.sh:170-173`; `release_build_test.dart` « consumer → lib/main.dart, on both » |
| Release script | ✅ `./tool/release_build.sh <ios\|android> consumer` | the same script as Pro: DSN and CARTO key from Secret Manager, the TLS gate on the AAB, the R8 UUID |
| Version / build | 🟡 `0.0.2+1`, shared `pubspec.yaml:4`; build = `main`'s commit count | no consumer version decision (§8 Q3) |
| Android signing | ✅ one upload key; Play App Signing enrolled for both apps | `build.gradle.kts` `signingConfigs`; `infra/mobile/signing-manifest.json` |
| Google sign-in on a Play-signed build | ✅ registered; last seen working 2026-08-26 | `playSha1 b73647c6…` (`signing-manifest.json`) is in `android/app/src/consumer/google-services.json` (read 2026-11-22); [roadmap 2026-08-26](../roadmap/entries/2026-08-26-true-play-delivery-shas.md): `/auth/google` 200 with the Dart user agent, on a build three months older than today's code |
| R8 | 🟡 on for both flavours | `build.gradle.kts` release block; `android_release_r8_test.dart` |
| TLS gate (GHSA-frr6-h895-5pxp) | ✅ every PR, **on the consumer APK** | `ci.yml` `apk-size` builds `--flavor consumer` and runs `verify_android_tls.py` on it |
| Play portrait filter | ✅ on the consumer APK | `ci.yml`, « portrait is optional in the APK » |
| 30 MB budget | ✅ on the consumer APK, every PR | `ci.yml` `apk-size` |
| 16 KB pages | 🟡 read by hand on Pro's AAB (785, 788); no CI check | android-play-release §11 log |
| target SDK 36 | ✅ | android-play-release §2 |
| HTTP/3 (Cronet) | 🟡 wired in `main.dart` since #810 | `http.runWithClient(…, () => AppHttpTransport.client)`; `android_http_transport_guard_test.dart` pins both entries. Never run on a consumer build on a phone (http3 spec §8 step 6) |
| Sentry | 🟡 same DSN and project as Pro | `release_build.sh`; no consumer release event yet ❓ |
| Map key | ✅ restricted to both apps and their Play certs | [map-basemap-key.md](map-basemap-key.md) §3.3; `test/unit/carto_basemap_test.dart` (cert table = `signing-manifest.json`) |
| Privacy manifest, export compliance | ✅ shared | `ios/Runner/PrivacyInfo.xcprivacy`; `ITSAppUsesNonExemptEncryption = false` in `Info.plist` |
| Entitlements | ✅ push (production in Release), Sign in with Apple | both `.entitlements`; `ios_entitlements_test.dart` |
| Icon, splash, French | ✅ | `AppIcon.appiconset`, `mipmap-*` (#161), `ios_app_icon_test.dart`; `flutter_native_splash` in `pubspec.yaml`; `CFBundleLocalizations = [fr]` |
| Firebase files | ✅ bundle ids match | `ios/config/consumer/GoogleService-Info.plist`, `android/app/src/consumer/google-services.json` |
| Version gate | ✅ wired (`isPro: false`) | `main.dart`; the server rows in §4 |
| A release build without the backend refuses to start | ✅ | `build_config_guard.dart`, `AppConfig.backendMisconfiguration` |

### 3.2 iOS — what the consumer still lacks

| Item | State | Evidence |
|---|---|---|
| A signed consumer IPA | ❌ never built | every signed IPA on record is Pro's (app-store-forms §11; mobile-store-submission §6) |
| App Store Connect record | ❓ | one sentence in app-store-forms §3: « iOS 1.0, Prepare for Submission » on 2026-10-05. Version « 1.0 » against a 0.0.x binary is the mismatch Pro had to rename. Its Apple ID (adamId) is recorded nowhere |
| Submission packet | ❌ | app-store-forms.md is Pro's alone (« Le consommateur aura son propre dossier », line 6): listing, keywords, category, age rating, review notes, URLs |
| Privacy label | ❌ | the only table, mobile-store-submission §4, misses Search History (`?q=` kept 30 days, decision 144), Device ID (the push token), User Content (reviews, booking notes) and the avatar. Its Photos row names the salon gallery, which is Pro |
| Purpose strings | ❌ **wrong for this app** | `setup_flavours.rb:76-77`: camera and photos end « …et, côté salon, la galerie de votre établissement », a feature this app does not have. This is the 5.1.1(ii) shape that app-store-forms §1 item 3 fixed for Pro |
| iPad | ❌ decision | `TARGETED_DEVICE_FAMILY = "1,2"` (`setup_flavours.rb:74`, pinned by `ios_store_readiness_test.dart`), four iPad orientations (`Info.plist`). 13-inch iPad screenshots become mandatory, and review may run it on an iPad. It has never been laid out or tested there. A device family, once shipped, cannot be withdrawn (§8 Q2) |
| Screenshots | ❌ | none (Pro's: [pro-app-store-screenshots.md](pro-app-store-screenshots.md)) |
| Sign in with Apple, `com.myweli.app` | ❓ the key is deployed, never exercised | apple-signin-keys §9 step 7, §10: « only `com.myweli.app` waits, for that app's first build ». `APPLE_APP_KEY_CLIENTS` includes it (`service.yaml:292-293`) |
| Push on an iPhone | ❓ | the APNs key for the consumer Firebase iOS app is unrecorded (DEPLOYMENT.md Phase B, step 7: « Still owed: confirming the APNs key is in Firebase »; mobile-ios-flavours.md:129). A production push was seen on the owner's iPhone on 2026-11-11, but [that entry](../roadmap/entries/2026-11-11-iam-push-key-compute-editor.md) does not say which app received it |
| Review sign-in | ✅ by design | [backend-demo-review-account.md](backend-demo-review-account.md) §1: the app is browsable signed out; a reviewer uses Apple or Google as themselves. The review notes must say so |
| Something to review | ❌ | §5 |
| DSA trader status | ❓ | declared for the account under Pro (app-store-forms §9.1); not read for this app |

### 3.3 Android — what the consumer still lacks

| Item | State | Evidence |
|---|---|---|
| An AAB of today's code | ❌ | the last consumer build on Play is August's, used for the certificate read; every 0.0.2 AAB is Pro's |
| The artifact reads | ❌ | Pro's step 5: TLS line, R8 marker, `proguard.map`, permissions, 16 KB, `libapp.so` without debug section, Sentry symbols and mapping |
| A device pass | ❌ | Pro's rows 1–22 (android-play-release §5) have no consumer counterpart: Cronet on Orange fibre, Google sign-in on the Play build, push, tiles, a deposit-proof upload, R8 at run time |
| `ACCESS_FINE_LOCATION` | ❌ shared manifest | `android/app/src/main/AndroidManifest.xml` asks FINE for both flavours. The consumer only picks a commune (`commune_picker_sheet.dart`, `map_screen.dart`). Play's declaration is mandatory from **2027-01-27**; android-play-release §7.1 already proposes moving FINE to the Pro flavour |
| Listing text | 🟡 from 2026-08-28, stale | play-store-forms §8.1. Its own correction is now stale too: since decision 116, Android Pro signs salons up again, so « Téléchargez MyWeli Pro » is true on Play and false on the App Store |
| Data safety | 🟡 from 2026-08-28, four known fixes | play-store-forms §8.2, plus the avatar |
| Sign-in details | ❌ | play-store-forms §8: in English, with the mandatory phone step |
| Content rating, ads, app access, audience… | ❌ for this app | play-store-forms §3, §5 hold Pro's answers |
| Closed test, 12 testers × 14 days | ❓ **probably again** | play-store-forms §6: Google's page speaks of a test « for their app » (INFERRED). The longest pole on Android |
| Trader declaration | 🟡 answered, waits for the first review | LAUNCH §6.3 (decision 150) |
| Screenshots, feature graphic | ❌ | none |

### 3.4 Pro's guards with no consumer counterpart

| Pro | Consumer |
|---|---|
| `play_store_forms_test.dart` (listing = approved text) | none |
| `app_review_notes_test.dart` | none |
| `pro_site_links_test.dart` (the only site pages the app opens) | none in `mobile/` (the test says « The consumer app's own links are … not in scope », :32). The web half, `web/tests/store-linked-pages.test.tsx`, reads `AppConfig` for either app |
| the screenshot shoot and its fixes | none |
| android-play-release §5, the device pass | none |

---

## 4. Backend and web dependencies

- **API: nothing missing.**
  - Every call the consumer services make has a backend route with the right
    verb and principal: auth, `/me`, providers, localities, availability,
    appointments (create, list, detail, cancel, reschedule, deposit), reviews,
    favourites, notifications, devices, `/uploads/sign` for deposit, review and
    avatar, and `/client-version`.
  - All are in `docs/api/openapi.yaml`.
  - `/me/export` has no route by design: the export is built on the device.
  - The phone-OTP routes answer 404 `auth_method_disabled`
    (`backend/routes/auth/otp/request.dart:17-18`).
- **Auth configuration:**
  - `com.myweli.app` is in `APPLE_CLIENT_IDS` and `APPLE_APP_KEY_CLIENTS`
    (`service.yaml:276-277,292-293`).
  - `GOOGLE_CLIENT_IDS` holds the server audience, the only one the apps
    present (`signing-manifest.json` `audience`).
- **CORS:** native calls are not affected (`backend/lib/src/cors.dart`);
  every call goes through the `api.myweli.com` front door.
- **Version floors:** `client_version_floors`, migration 0032
  (`backend/lib/src/db/migrations.dart:857-899`).
  - `com.myweli.app/android` points to Play.
  - **`com.myweli.app/ios` has `update_url` NULL**, so iOS can never be blocked
    or nudged until it is set.
  - The admin console sets it (`admin_client_version_screen.dart`), as B0.5 did
    for Pro, once the listing is live.
- **Legal pages:** the five pages the app opens exist (`web/app/{politique-confidentialite,cgu,mentions-legales,suppression-compte,support}`).
  - `/suppression-compte` describes a consumer deletion: the in-app path, what
    is erased, anonymised and kept, and a web route.
  - **Gaps:**
    - **the privacy policy names only « la photo de profil transmise par
      Google »** (`politique-confidentialite/page.tsx:118-121`), while the app
      uploads the client's own photo;
    - the deletion page does not name the profile photo among what is erased;
    - it states what is kept but **not how long**. Google's deletion-URL
      requirement asks for that (Google's text not re-read here, INFERRED);
    - the policy's sentence on SMS and WhatsApp « que nous envoyons » (line
      157) reads as current, while line 232 says none are sent today †.
- **Store links on the web: none today.**
  - `NEXT_PUBLIC_IOS_APP_URL` and `NEXT_PUBLIC_ANDROID_APP_URL` are blank
    (`web/.env.example:50-51`; DEPLOYMENT Phase F step 6).
  - **`appStoreUrl()` returns the Android URL first, to every visitor**
    (`web/lib/appStore.ts:21-26`), so once both are set an iPhone would be sent
    to Play.
  - There is no `apple-itunes-app` banner, no `.well-known` file, and no
    universal or app links. None of these is needed for the release.
- **Decision 43** (« Prendre rendez-vous » for clients who installed MyWeli Pro
  by mistake) is not built anywhere: it is a later Pro build.
- **E-mail codes:** `EMAIL_BUDGET_COLD = 60` per hour, shared by clients and
  salons (`service.yaml:334-335`). A launch surge can exhaust it, and the
  screen would look normal ([backend-email-send-budget.md](backend-email-send-budget.md)).
- **Admin:**
  - moderation and user support exist;
  - **the consumer erase** (`DELETE /admin/users/{id}/erase`) has no console
    screen: it was run once, with curl
    ([admin-pro-account-erase.md](admin-pro-account-erase.md)).

---

## 5. The gate outside the code — salons in production

- **Decision 51:** MyWeli Pro only for now, because « Production has no public
  salon (`GET /providers` → `total: 0`) ».
- **The latest recorded count is 0**, read 2026-11-12
  ([salon-go-live-approval.md](salon-go-live-approval.md):31).
  - The owner's test salon reached the validation queue on 2026-11-13 and is to
    be refused as a test (LAUNCH §6.4).
  - The three ownerless salons of B0.24 are hidden.
- **Publishing now needs an admin's approval** (B0.18). So
  [mobile-external-testing.md](mobile-external-testing.md) §5.3 (« a salon …
  is live to consumers the moment it publishes ») is out of date.
- **The first public salon has its own checklist:** LAUNCH §6.4.
- **Why it gates the app and not only the marketing:**
  - a reviewer, Apple's or Google's, opens a marketplace with nothing in it,
    beside three stories advertising a promotion and a salon that do not exist;
  - consumer testers would test an empty state (mobile-external-testing §5.3).
- **No date and no named first salon are recorded.** This is the owner's track,
  and it is on the critical path.

---

## 6. Gaps, ranked by risk to a store release

Each line was re-read in the code. **Size:** S = a day or less, M = a few days,
L = a week or more. **Risk** is to the submission or to a user's trust.

| # | Gap | Size | Risk | Evidence |
|---|---|---|---|---|
| 1 | No public salon in production | L (operations) | **Blocking** (decision 51; App Review 2.1 / 4.2) | §5 |
| 2 | An invented promotion and an invented salon on every home | S | **High**: a false offer (App Store 2.3.1, Play's deceptive-behaviour policy, consumer law) | `announcement_stories.dart:48-71`, `assets/images/stories/*.svg` |
| 3 | The cancel dialog promises a refund MyWeli never makes | S | **High** (trust; PRD FR-PAY-005; the web already fixed it) | `appointment_detail_screen.dart:147-157`; B12.11 |
| 4 | No store packet for either store (listing, privacy label, Data safety, review notes, age rating, screenshots) | L | **Blocking** | §3.2, §3.3 |
| 5 | Privacy label and policy behind the binary: avatar, Search History, Device ID, User Content | S | **High**: a label that contradicts the binary is a rejection and a legal exposure | §3.2; `politique-confidentialite/page.tsx:118-121` |
| 6 | iOS purpose strings describe a salon gallery the app does not have | S | **High** (5.1.1(ii)) | `setup_flavours.rb:76-77` |
| 7 | No consumer build of today's code, and no device pass (Apple sign-in for `com.myweli.app`, APNs, Cronet, R8, Google on the Play build) | M (owner's time) | **High**: a wrong Google certificate and a missing APNs key both fail without a word on screen | §3.2, §3.3 |
| 8 | A second 12 × 14 closed test on Play, probably | L (calendar) | Blocking on Android if it applies | §3.3 |
| 9 | The appointment detail shows no status, salon, services, address or directions; cards and home tiles show « Salon » | M | **Medium-high**: the screen a client opens on the day | §2.4 |
| 10 | A guest cannot leave the sign-in screen | S | Medium (a reviewer who taps a heart is stuck) | §2.3 |
| 11 | No text search; four generic categories | M | Medium (V1 FR-DISC-003/004; the store text promises search) | §2.1 |
| 12 | « Langue » answers « Fonctionnalité à venir » | S | Medium (App Review 2.1, placeholder content) | `profile_screen.dart:101-107` |
| 13 | `ACCESS_FINE_LOCATION` in the consumer manifest | S | Medium (Play declaration due 2027-01-27) | §3.3 |
| 14 | iPad declared, never laid out or tested | S (to drop) / M (to keep) | Medium | §3.2 |
| 15 | Past unconfirmed bookings read « Terminé »; no-shows in no tab | S | Medium (truth) | §2.4 |
| 16 | Photo-less salon cards fetch `via.placeholder.com` | S | Low-medium: a third-party request the label does not declare. Whether the host still serves is UNVERIFIED | `widgets/provider/provider_card.dart:195,380` |
| 17 | « Plus tard » on the push sheet ends push for good on that iPhone | S | Medium (reminders arrive by push only) | `push_registration.dart:55-57` |
| 18 | No staff section on the salon page; reviews capped at 5 | S-M | Low-medium (V1 FR-DISC-006) | §2.2 |
| 19 | Auto-sync cannot fire for any account made today | L (needs phone verification, so SMS, after registration) | Low for the stores; **the copy must not promise it** | §2.4 |
| 20 | No pagination (20 salons) | M | Low at launch (three communes) | §2.1 |
| 21 | iOS `update_url` NULL; the web store links unset and Android-first | S | Low at launch; required before any floor is raised | §4 |
| 22 | Map: location asked without explanation, « Activer » dead after a refusal, the commune filter invisible | S | Low | §2.1 |
| 23 | Missing goldens and widget tests (the list, the map, the detail, the confirmation, the deposit sheet, profile) | M | Low (regressions) | §2.9 |
| 24 | E-mail code budget 60 per hour, shared | S (config) | Medium on launch day | §4 |

**2026-11-23 — A1 built** ([consumer-app-truth.md](consumer-app-truth.md)): in the app, gaps 2 (the stories hidden behind a flag, decision 170; real stories are their own spec), 3, 6, 12, 15 and 16, and the name half of 9. The web half of 15 is A1w.

**2026-11-23 — A1w built** (#838; [web-account-bookings-truth.md](web-account-bookings-truth.md), decisions 182–186): the web half of gap 15. The website files a client's bookings by the app's table, and « Passés » is the app's history. The app's months now follow the salon's zone, like its cards (decision 186). That reaches clients with the next consumer build; the website changes when the PR is merged, which is a production deploy.

**2026-11-24 — A3 built** ([consumer-signin-push.md](consumer-signin-push.md), decisions 204–213): gap 10 and gap 17 in the app. The sign-in opens over the screen the person is on, with « Fermer », and returns there; « Rendez-vous » and « Actu » draw a signed-out page; Préférences offers « Activer les notifications » to a phone never asked, and « Plus tard » brings the sheet back after a later booking (3 offers, 7 days apart). MyWeli Pro gets the same card. It reaches clients with the next consumer build; the website's two hearts follow in A3w.

**2026-11-24 — A3 merged (#854); A3w built** ([consumer-signin-push.md](consumer-signin-push.md) §14, decision 205): on the website, a guest's heart on the salon page or a search card is applied once they are back from the sign-in it opened, and `/connexion` says why it opened. The website changes when the PR is merged, which is a production deploy.

**2026-11-24 — A3w merged and deployed** (#856, `51d439f2`): live on `myweli.com` at 20:40 UTC, read back there, and the production monitor passed 11 of 11 after it. A3 (#854) reaches clients with the next consumer build.

**2026-11-24 — A4's spec written** ([consumer-search.md](consumer-search.md), decisions 228–236 open): gaps 11, 20 and the map's commune half of 22. It also found that the home, the salon list and the map share one salon list (§2.7 there).

**2026-11-25 — A4's nine questions answered** (decisions 228–236, « Approve as recommended »). Decision 229 replaces row A4's « PRD Appendix A chips » with the five categories the server, MyWeli Pro and the website share. Next: A4-api, then A4, then A4w.

**2026-11-25 — A4-api merged and deployed** (#864, `351568e3`; `myweli-api-00059-w28`): the server's `q` finds services and communes and ignores accents. Gaps 11, 20 and 22's commune half stay open until A4, the app, ships.

**2026-11-25 — A4 built** (the app, [consumer-search.md](consumer-search.md) §3.2): the search field, the five categories, « Afficher plus de salons », every empty state, and the map's commune pill and states. The home, the list and the map now read their own salons. Gaps 11, 20 and 22's commune half are closed in the code; they reach people with the next consumer build, on the owner's word.

**2026-11-26 — A4 merged** (#878, `f49de03d`): gaps 11, 20 and 22's commune half are closed on `main`. They reach people with the next consumer build, on the owner's word. Next: A4w, the website's half.

**2026-11-26 — A4w built** (the website, [consumer-search.md](consumer-search.md) §3.3): `/recherche` counts from the server's `total`, has « Afficher plus de salons », and keeps the pages read in its address. **Merged** (#883, `dedda5d4`) and **live on `myweli.com`** since 2026-11-26, read back. The read found **one public salon** in production, « test » (`test-3`, Adjamé), where §0's gate (point 4) last read none, on 2026-11-12; whether a salon named « test » meets that gate is the owner's to say.

**2026-11-27 — A6's spec approved and merged** ([consumer-location.md](consumer-location.md), decisions 272–276 as recommended; #890, `3a2cb1d7`).

**2026-11-27 — A6 built** (#896, [consumer-location.md](consumer-location.md) §15): gap 13 and the location half of 22 in the code. Read on APKs built that day: the client APK from `main` declared `ACCESS_FINE_LOCATION`; with A6 it declares `ACCESS_COARSE_LOCATION` alone, and MyWeli Pro's declares both. The map asks before any dialog, once, and every refusal has its way out, as « Près de moi » and Pro's « Utiliser ma position » do. They reach people with the next client build and Pro's next; the device rows (§8.4) wait for them.

**2026-11-27 — A6 merged** (#896, `43be35ea`): gap 13 and the location half of 22 are closed on `main`. They reach people with the next client build and MyWeli Pro's next; the device rows ([consumer-location.md](consumer-location.md) §8.4) wait for them. `myweli.com` deployed with it (the web's token mirror; no visible change) and was read back. **Track C's condition is met:** A1, A2, A3 and A6 are merged. Each of its steps waits for the owner's « yes ».

---

## 7. Proposed order of work

Each PR comes from `main`, with its own French roadmap entry, merged only on
the owner's word. **No build, upload, console step or production deploy
happens without the owner's « yes » at that moment.** Where a PR touches what
users see, its spec comes first ([design spec per part](README.md)), with every
state and the French copy, and the owner approves it.

**Track A — code. It runs now, and in parallel with the salons.**

| PR | What | Size | Spec |
|---|---|---|---|
| A1 | **What the app says is true:** the stories go (gap 2); the cancel sentence takes the salon's rule, as the web does (3); « Langue » goes (12); purpose strings (6); a local placeholder (16); cards and home tiles read the booking's own salon name (part of 9); past unconfirmed bookings and no-shows get honest labels and a tab, one rule shared with the web (15, web C4) | S each, one M PR | [consumer-app-truth.md](consumer-app-truth.md): one spec, every changed sentence in French (approved 2026-11-23; A1 merged as #834 and its web half A1w as #838, the same day) |
| A2 | **The appointment detail, complete:** status, salon (name, photo, address), services, « Itinéraire », « Appeler »; rebook from the detail (FR-REBOOK-001) | M | yes (UX): [appointment-detail-complete.md](appointment-detail-complete.md) (approved 2026-11-23; A2-api #841, A2 #845 and A2w #847, merged 2026-11-23 and 24) |
| A3 | **Sign-in you can leave, and push you can turn on later:** sign-in pushed rather than replaced, with a close button; `returnTo` kept; a way to ask for push again from Préférences (17) | S | [consumer-signin-push.md](consumer-signin-push.md) (approved 2026-11-24, decisions 204–213; A3 #854 and A3w #856, merged 2026-11-24) |
| A4 | **Search that searches, and the Ivorian categories:** a search field on `GET /providers?q=`, debounced, with every state; the PRD Appendix A chips; « Charger plus »; the map says its commune (11, 20, 22) | M | yes (UX), parity with web `/recherche`: [consumer-search.md](consumer-search.md) (written 2026-11-24; decisions 228–236 answered 2026-11-25, as recommended: the five shared categories, not Appendix A's, decision 229; A4-api #864 merged and deployed 2026-11-25, A4 #878 merged 2026-11-26, A4w #883 merged and deployed 2026-11-26) |
| A5 | **The salon page's team and every review:** staff section, « Voir tous les avis » (18) | S-M | yes (UX): [salon-team-and-reviews.md](salon-team-and-reviews.md) (written 2026-11-27 on the owner's « Yes, start A5 »; approved the same day, decisions 277–283 as recommended; three PRs: A5-api, A5, A5w) |
| A6 | **Android: precise location for Pro only** (13); the map asks after an explanation, and « Activer » opens the Settings after a refusal (22) | S | [consumer-location.md](consumer-location.md) (written 2026-11-27, a file rather than a section of android-play-release §7.1, since most of it is the map's UX); approved 2026-11-27, decisions 272–276 as recommended, Pro's half included; merged as `3a2cb1d7` (#890); built and **merged 2026-11-27** (#896, `43be35ea`) |
| A7 | **Tests the release leans on:** goldens and widget tests of §2.9 for the screens A1–A5 change, and a test that pins the cancel sentence | M | none (part of each PR's Definition of Done) |

**Track B — documents and the web. It also runs now.**

| PR | What | Size |
|---|---|---|
| B1 | **Docs made true:** PRD FR-AUTH-001/002 (phone OTP → decision), FR-APPT-006 (directions), FR-APPT-008 (cannot fire today); ROADMAP §1.8's « ✅ verified » for DISC-003/004/006 and APPT-002/006/008; mobile-external-testing §5.3; play-store-forms §8's stale note; mobile-store-submission §4 | S |
| B2 | **Privacy policy and deletion page** (web): the client's own photo; what is kept and for how long; the SMS/WhatsApp tense. Each merge is a production web deploy, on the owner's word | S |
| B3 | **The consumer store packet:** a new `app-store-forms-client.md` (record, version, listing, keywords, category, age rating, privacy label derived from the binary, review notes in English, iPad answer, the IPA reads of §11.3 adapted); play-store-forms §8 rewritten (listing per decision 113's rule, Data safety, sign-in details, IARC, location declaration if FINE stays); guards like Pro's (`play_store_forms_test`, `app_review_notes_test`, a consumer `site_links` pin) | L |
| B4 | **Screenshots:** a spec like pro-app-store-screenshots.md. They need real salons, or a decision on what to photograph | M |

**Track C — builds and consoles, each step on the owner's « yes ».** It starts
when A1, A2, A3 and A6 are merged.

1. **iOS:**
   - the IPA (`./tool/release_build.sh ios consumer`, from `main`, in the main
     checkout), read as Pro's §11.3;
   - TestFlight internal;
   - a consumer device pass: Apple sign-in, with the `apple_tokens` row for
     `com.myweli.app` (apple-signin-keys §9 step 7); a push received (APNs); the
     tiles; a booking with a deposit proof; a cancel; a review with a photo;
     the deletion, and the app leaving the Apple ID list.
2. **Android:**
   - the AAB (`android consumer`), with Pro's step-5 reads;
   - the internal track;
   - a consumer device pass: Pro's rows 1–9 and 17–22 adapted, Cronet on Orange
     fibre, and Google sign-in on the Play build.
3. **Play's closed test** for MyWeli, if Google requires it (§8 Q1 decides
   when).
4. **The submissions:** App Store review, and Play's production access. Both
   wait for public salons (§5) and the owner's word.
5. **After release:** the iOS `update_url` in the console; the web's store URLs
   (fixing `appStoreUrl()` per platform first); decision 43 in a later Pro
   build; then LAUNCH's « live and stable a week » rule before the next step.

**Not proposed for V1, each with its reason:**
- **auto-sync for accounts made today** needs phone verification, so SMS, so
  company registration;
- a **console screen for the consumer erase** waits until support volume asks
  for it;
- **universal links** are not needed to ship.

---

## 8. Questions for the owner

1. **Store order, and Play's 14 days.** iOS first, as for Pro (LAUNCH §3), with
   Android following? And should MyWeli's Play closed test start as soon as an
   AAB passes its device pass, even with few or no public salons, so that its
   14 days run while the salons are signed up? Or after the first salons?
2. **iPad.** Ship the client app on iPhone only for its first release, like
   Pro? A device family cannot be withdrawn once shipped, and iPhone-only can be
   widened later. Or keep iPad, with 13-inch screenshots and an iPad layout
   pass?
3. **Version.** The pubspec is shared, so the client's first release would be
   0.0.x, like Pro, and its App Store record renamed from « 1.0 ». Keep that?
4. **The home stories.** Remove them for V1 (recommended), or replace them with
   real announcements that someone keeps up to date (a V2 feature)?
5. **What counts as « salons are public »** for decision 51's gate: how many
   salons, in which communes, before the client app is submitted?
6. **This order (§7).** Approve it as written, or change it?

**Answers (2026-11-23).** Q6: « Approve the plan », as written (BACKLOG decision 160). Q4 followed from it (A1 removed the stories); **decision 170 changed that the same day: the stories stay, behind a flag, until someone manages real ones.** Q1, Q2, Q3 and Q5 are open, as decisions 161–164, each needed before the step it names.

---

## 9. Not verified — and how each would be checked

| Item | How |
|---|---|
| The consumer App Store record, its version and adamId | App Store Connect, read-only |
| The APNs key for `com.myweli.app` in Firebase | Firebase → Cloud Messaging → the iOS app; then a push received on a TestFlight install |
| Apple sign-in for `com.myweli.app` | a real sign-in: one `apple_tokens` row `user \| com.myweli.app` (counted, never read), no `apple_token FAILED` |
| Google sign-in on today's Play-signed consumer build | `/auth/google` 200 with the app's user agent, from a Play install |
| Whether Play requires a second closed test | the MyWeli dashboard in the Play Console, before anything is typed |
| Whether Wave honours the pre-filled link | a device, with the owner's own Wave |
| Whether `via.placeholder.com` still serves | moot once A1 lands |
| The production `client_version_floors` rows (assumed to be the seeds) | the admin console's version screen |
| The public salon count today | `GET /providers` on production, read-only, on the owner's word |
| The DSA trader status for the second app | App Store Connect → Business |

---

## 10. Documents this audit found out of date (fixed in B1, not here)

| Document | Says | Is |
|---|---|---|
| ROADMAP §1.8 | DISC-001…007, APPT-001…005/009 « ✅ Built (verified) » | DISC-003/004 not met in the app; DISC-006 has no staff; APPT-002 incomplete; APPT-008 cannot fire |
| PRD FR-AUTH-001/002 | phone OTP | replaced by Google, e-mail and Apple ([app-auth-social.md](app-auth-social.md)) |
| PRD FR-APPT-006 | « directions … from the appointment detail » built | no directions on that screen |
| play-store-forms §8 | « l'app Pro ne crée plus de compte » | true on iOS only since decision 116 |
| mobile-store-submission §4 | « the starting point for the consumer label » | misses four data types (§3.2) |
| mobile-external-testing §5.3 | « live … the moment it publishes » | admin approval since B0.18 |
| MODULES §2 | `docs/modules/online-booking.md` « to write » | still not written |
