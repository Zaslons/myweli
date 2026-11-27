# MyWeli (client) — location: approximate on Android, asked after an explanation, a way back after a refusal (A6)

| | |
|---|---|
| **Module** | discovery (mobile, both flavours: the client map, the shared commune picker, MyWeli Pro's « Utiliser ma position »; the Android manifests) |
| **Status** | **Approved 2026-11-27.** Written on the owner's « Yes, start A6 »; the owner answered the five questions of §11 at once, « Approve as recommended »: decisions 272–276 in BACKLOG, Pro's half included (#890). Read once by an independent reviewer told to refute it: 12 findings, checked, then taken in (§14). The spec merged as `3a2cb1d7` (#890). **Built 2026-11-27** on the owner's « Yes, build A6 », branch `feat/a6-location`, one app PR (#896, §15): not merged. It reaches people with the next client build and MyWeli Pro's next build; the device rows of §8.4 wait for them. |
| **Last updated** | 2026-11-27 |
| **Audit** | [consumer-app-release-audit.md](consumer-app-release-audit.md) row **A6** (Track A, §7): gap **13** (`ACCESS_FINE_LOCATION` in the client manifest) and the first half of gap **22** (the map asks with no explanation; « Activer » is dead after a refusal). Gap 22's other half, the commune, was A4's ([consumer-search.md](consumer-search.md) §2.8). Not to be confused with the earlier « A6 » of [mobile-a6-feedback.md](mobile-a6-feedback.md), whose comments in `commune_picker_sheet.dart` say « A6 ». |
| **BACKLOG** | B0.10 (the audit's Track A). Track C, the consumer builds, waits for A1, A2, A3 and this. |
| **PRD ref / phase** | V1 · FR-DISC-005 (the map) · FR-DISC-002 (the commune). FR-BOOK-010 (à domicile, a client pin) is **V2** and would change §1's answer: see §9 |
| **Related** | [android-play-release.md](android-play-release.md) §7.1 (Play's precise-location declaration, due **2027-01-27**) · [play-store-forms.md](play-store-forms.md) §8 (the client app on Play, B3) · [consumer-search.md](consumer-search.md) §2.8 (the map's other banners) · [push-notifications-app.md](push-notifications-app.md) (`PushBlockedBanner`, the same « Ouvrir les réglages » exit) · [SYSTEM.md](SYSTEM.md) §12 (permission-denied is a state), §13, §15, §17 |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

The audit planned A6 as « a section added » to android-play-release §7.1. It is
a file instead: most of A6 is the client map's UX, and that document is MyWeli
Pro's Android release. §7.1 gets a pointer here (§10).

**How to read it.** *Observed* means read in the code at `main` `343a1f4d` on
2026-11-27, with the file and line. *UNVERIFIED* means nobody has seen it, and
says who can.

## 0. Today (observed)

**The manifest.** Both apps share `android/app/src/main/AndroidManifest.xml`,
which asks for precise and approximate location (`:14`, `:15`). The `consumer`
and `pro` flavour folders hold no manifest (only `google-services.json`, and
Pro's icons). A Pro release build's merged manifest left in the main checkout
(`build/app/intermediates/merged_manifests/proRelease/`, dated 2026-11-20
10:28, probably build 794's) declares `ACCESS_FINE_LOCATION` once, from ours:
no plugin adds it. The client's was not read; its plugins are the same, and
§8.3's CI read is what will know.

**Who uses the position.** Three places, each with its own copy of the same
flow (`isLocationServiceEnabled` → `checkPermission` → `requestPermission` →
`getCurrentPosition` at the default « best » accuracy, no time limit):

| Where | App | When it asks | After a refusal |
|---|---|---|---|
| The map, `map_screen.dart:160-212` | client | **as soon as the map opens** (`:102`), with no word first: the system dialog is the first thing a visitor of « Carte » sees | the banner « Autorisez la localisation pour vous centrer » and « Activer » (`:579-589`), which calls the same flow again (`:586`). After a permanent refusal it shows nothing new and opens nothing: the button looks alive and does nothing. Location turned off: « Localisation désactivée », same dead button |
| « Près de moi », `commune_picker_sheet.dart:80-112` | both | on the tap | an inline sentence (« Autorisez la localisation pour utiliser « Près de moi » », `:94`), no way to the Settings |
| « Utiliser ma position », `pro_salon_profile_screen.dart:143-182` | Pro | on the tap | a snackbar (« Autorisez la localisation pour vous placer », `:165`), no way to the Settings |

**Where the position goes.** The client's never leaves the phone: no request in
`lib/services/api/` carries a latitude or a longitude (searched for `lat`,
`lng`, `latitude`, `longitude`, `near`); « Près de moi » picks the nearest
commune on the phone (`locality_provider.dart:101-115`, the nearest centre, no
distance limit) and only the commune's name is sent. The privacy policy says the
same (`web/app/politique-confidentialite/page.tsx:181-188`). Pro's pin is sent,
and published, by design.

**How the plugin behaves** (geolocator_android 5.1.1+1, geolocator_apple
2.3.14, read in the pub cache):
- Android asks for whatever the merged manifest declares: precise and
  approximate if both, approximate alone if only that (`PermissionManager.java:209-232`).
- Android's `checkPermission` never says « refused for good »: it answers
  `denied` for « never asked », « refused once » and « refused for good » alike.
  Only `requestPermission` tells them apart, by returning `deniedForever` at
  once, with no dialog (`:180-188`).
- iOS answers `deniedForever` from the first refusal (`AuthorizationStatusMapper.m:16-17`):
  iOS never shows its dialog twice.
- `openAppSettings` opens the app's own page (Android
  `ACTION_APPLICATION_DETAILS_SETTINGS`, iOS the app's Settings page);
  `openLocationSettings` opens the phone's location page on Android and, on
  iOS, the app's page again (`Utils.java:11`, `:29`; `GeolocatorPlugin.m:101-104`).
- iOS requests « while using » because `NSLocationWhenInUseUsageDescription`
  is present (`PermissionHandler.m:72-73`). The « Always » string in
  `Info.plist` is there only because Apple's delivery scan flagged build 551
  without it (ITMS-90683, `setup_flavours.rb:100-107`); no code asks for
  « Always ». A6 leaves iOS's strings alone.

**Tests.** The map's location path has none (audit §2.1). `map_commune_test`
and `salon_location_map_test` answer the plugin's channel with « location off »
only so the map does not wait; `carto_basemap_layer_test` answers nothing; a map
golden in `consumer_search_golden_test` shows today's « Localisation
désactivée » banner (§8.1).

## 1. Goal & scope

**Goal.** The client app asks for no more location than it uses, asks only
after saying why, and never leaves a person who refused with a button that does
nothing.

**In scope:**
1. **Android: precise location for MyWeli Pro only.** `ACCESS_FINE_LOCATION`
   moves from the shared manifest to a new `android/app/src/pro/AndroidManifest.xml`.
   The shared manifest keeps `ACCESS_COARSE_LOCATION`. The client app then
   needs no Play declaration (§9); Pro's stays as android-play-release §7.1
   writes it.
2. **The map** no longer opens the system dialog by itself. It explains first,
   once, in its banner slot; the dialog follows a tap (§2.1).
3. **After a refusal**, the map, « Près de moi » and « Utiliser ma position »
   each say what happened and offer the way that works: ask again where the
   phone still can, the app's Settings where only they can, the phone's location
   page when location is off (§2.1–§2.3).
4. **One shared flow** for the three, so the three copies of today become one,
   tested once (§5).
5. **The position the client reads** is « medium » accuracy, every read is
   bounded to 30 seconds, and the map draws how approximate it is (§2.1,
   decision 275).
6. **Pro says when the phone gave an approximate position** for the salon's pin
   (decision 276).
7. **Guards:** the manifests in source, the client APK's permissions in CI, the
   flow's every outcome in widget tests (§8).

**Out of scope:**
- **iOS's dialog and strings.** iOS already lets the person choose « Position
  exacte » or not, and asks once. `NSLocationDefaultAccuracyReduced` (approximate
  by default) was considered and left out: `Info.plist` is shared by both
  targets, and a boolean cannot come from a build setting the way the strings do.
- **The website.** `/recherche`'s « Autour de moi » already asks only on a tap
  (`ResultsMap.tsx:170-178`); a browser offers no way to its settings.
- **Pro's pin map not following « Utiliser ma position »** (§13, seen in
  passing).
- **Play's location button** (Android 17, target SDK 37): we target 36
  (android-play-release §7.1).

## 2. UX & flows

### 2.1 The map (client)

**Opening « Carte »** never shows the system dialog. It reads what the phone
already allows, with no dialog (`status()`, §5), and:

| The phone says | The map shows on opening |
|---|---|
| allowed | the position, silently, as today: the dot, and the camera on it unless a salon was opened (`focusProviderId`, salon-location-map.md §2.3). If that silent read fails or times out: nothing; « Me localiser » stays |
| not decided, and `location_explained` unset on this phone (§4) | **the ask banner** (below) |
| not decided, flag set; or refused for good | nothing. « Me localiser » stays, bottom right |
| location turned off | nothing; « Me localiser » says it on a tap |
| the plugin fails or answers nothing | nothing |

« Not decided » is the plugin's `denied`, which also covers, on Android, a
permanent refusal from before A6, and on iOS a phone where location is
restricted (§0, §2.4). Those people see the ask banner once; « Activer » then
leads to the blocked or the restricted banner, with no dialog.

**The ask banner**, in the location banner's slot (under the commune pill and
the salons' line, consumer-search.md §2.8):
- the icon `my_location`;
- « **Voir les salons autour de vous ?** Autorisez la localisation pour centrer
  la carte sur votre position. »;
- under the sentence, at the end: « Plus tard » and « Activer ».
- A **live region**, like the map's other banners: it shows once on a phone, so
  it is announced once.

**« Plus tard »** hides it. **« Activer »** runs the flow. Either one sets
`location_explained`, and the banner never comes back by itself. So does any
tap, in any of the three places, that runs the flow (§4). « Me localiser » is
the way to ask later.

**A tap on « Activer », « Me localiser » (with no position yet), « Autoriser »
or « Réessayer »** runs the shared flow (§5). While it runs, « Me localiser »
shows its loader and every location action on the map is disabled: one read at
a time, the plugin's own rule (§2.4). Then:

| Outcome | The banner | Its actions |
|---|---|---|
| allowed | none; the dot appears and the camera moves to it, unless a salon was opened | — |
| refused, the phone may ask again (Android only) | « Localisation refusée. Choisissez une commune en haut de la carte, ou autorisez-la. » | « Fermer » · « Autoriser » (the dialog once more) |
| refused for good (Android: §2.4 says when; iOS: from the first refusal) | « Localisation bloquée. Autorisez-la dans les réglages du téléphone pour centrer la carte sur vous. » | « Fermer » · « Ouvrir les réglages » (the app's page) |
| restricted (iOS: Screen Time or an installed profile) | « La localisation est limitée sur ce téléphone, par Temps d’écran ou un profil installé. Choisissez une commune en haut de la carte. » | « Fermer » |
| location off, Android | « La localisation du téléphone est désactivée. Activez-la dans les réglages, ou choisissez une commune. » | « Fermer » · « Ouvrir les réglages » (the phone's location page) |
| location off, iOS | « Le service de localisation est désactivé. Activez-le dans Réglages › Confidentialité et sécurité › Service de localisation. » | « Fermer » (an app can open only its own page, which cannot turn the service on) |
| no position within 30 s, or the plugin failed | « Position introuvable. Réessayez, ou choisissez une commune en haut de la carte. » | « Fermer » · « Réessayer » |

- These banners are **live regions**: the outcome is what the person waits to
  hear, as the salons' line is (consumer-search.md §2.8).
- « Fermer » hides the banner until the next tap.
- **Back from the Settings:** only when the map itself opened them (« Ouvrir les
  réglages »), and once. The system dialog's own closing also brings the app
  back to the foreground, and that return must not start a second read (§2.4).
  The map reads `status()` again, with no dialog, and rebuilds the banner from
  it:
  - allowed (and location on): the banner goes, the position is read, the dot
    appears, the camera moves;
  - location off: the « location off » banner;
  - refused for good: the blocked banner stays;
  - not decided (Android's « Demander à chaque fois »): the « refused, may ask
    again » banner, with « Autoriser ».

**The dot.** As today (`AppColors.info`, a white ring), plus:
- **a circle of the position's accuracy** (`Position.accuracy`, a radius in
  metres) under it, in a translucent `info` (a new colour token, §5). On
  Android, after A6, the client's position is approximate, « accurate to within
  about 3 square kilometers » by Android's documentation (developer.android.com,
  location permissions, read 2026-11-27). The radius Android reports for such a
  position may be 2 km or more, a circle about 4 km across (PLAUSIBLE, from the
  review, §14; UNVERIFIED until §8.4). A bare dot would claim a street;
- **the camera fits the circle** when the radius is over 500 m: the whole circle
  in view, with the page's margin, instead of today's zoom 13.5, which would
  fill the screen with it;
- a label for screen readers, « Votre position », which it lacks today.

### 2.2 « Près de moi » (the commune picker, both apps)

On the tap, as today: the system dialog is the explanation's own context (the
person asked for their commune). « Près de moi » uses « medium » accuracy and the
30-second bound, and is disabled while it reads (as today). Then, inside the
sheet (it is a modal: `InlineFeedback`, never a snackbar, mobile-a6-feedback.md):

| Outcome | Inside the sheet |
|---|---|
| allowed | the nearest commune is chosen and the sheet closes, as today |
| refused, may ask again (Android) | « Localisation refusée. Choisissez votre commune dans la liste. » |
| refused for good | « Localisation bloquée. Autorisez-la dans les réglages du téléphone, ou choisissez votre commune dans la liste. » and **« Ouvrir les réglages »** |
| restricted (iOS) | « La localisation est limitée sur ce téléphone. Choisissez votre commune dans la liste. » |
| location off, Android | « La localisation du téléphone est désactivée. Activez-la dans les réglages, ou choisissez votre commune dans la liste. » and **« Ouvrir les réglages »** |
| location off, iOS | « Le service de localisation est désactivé (Réglages › Confidentialité et sécurité). Choisissez votre commune dans la liste. » |
| no position, or failed | « Position introuvable. Réessayez, ou choisissez votre commune dans la liste. » |
| a position, but no commune to compare it with | « Liste des communes indisponible. Réessayez. » (today « Commune introuvable », `:106`). `nearestArea` has no distance limit: it finds nothing only when the communes are not loaded or carry no coordinates (`locality_provider.dart:90-115`) |

The sentences do not name the app: the picker serves both, and the settings
page it opens is already the app's own.

**With an approximate position**, the nearest commune's centre can be a
neighbour's. In the locality tree (`backend/lib/src/localities/localities_repository.dart`),
the Plateau's centre is 2.3 km from Attécoubé's and 3.7 km from Treichville's;
a position a kilometre or two off can land nearer the wrong one. The person sees
the commune chosen (the pill) and can change it. This is the price of decision
272, said here so it is chosen knowingly.

### 2.3 « Utiliser ma position » (MyWeli Pro's « Profil du salon »)

Precise location stays; the button keeps « best » accuracy and the same 30-second
bound, and is disabled while it reads (as today). The screen is not a modal, so
its outcomes stay snackbars:

| Outcome | The snackbar |
|---|---|
| allowed, precise | none; the pin moves, as today |
| **allowed, approximate** (decision 276) | none; the pin moves, and the line under the map says « Position approximative : touchez la carte pour placer votre salon exactement. » in place of « Touchez la carte pour ajuster. » |
| refused, may ask again (Android) | « Localisation refusée. Touchez la carte pour placer votre salon. » |
| refused for good | « Localisation bloquée. Autorisez-la dans les réglages du téléphone. » with the action « Ouvrir les réglages » (the bar lives 10 s, `kSnackActionDuration`) |
| restricted (iOS) | « La localisation est limitée sur ce téléphone. Touchez la carte pour placer votre salon. » |
| location off, Android | « La localisation du téléphone est désactivée. » with « Ouvrir les réglages » |
| location off, iOS | « Le service de localisation est désactivé (Réglages › Confidentialité et sécurité). Touchez la carte pour placer votre salon. » |
| no position, or failed | « Position introuvable. Réessayez, ou touchez la carte pour placer votre salon. » |

« Approximate » is the plugin's `getLocationAccuracy()` answering `reduced`:
Android when the person chose « Approximative », iOS when « Position exacte » is
off.

### 2.4 Edge cases

- **When Android refuses for good** (`PermissionManager.java:168-188`: no
  rationale left after a refusal): from Android 11, after a second refusal; on
  Android 6 to 10, only when the person ticks « Ne plus demander », which the
  dialog offers from its second showing. A second plain refusal there is still
  « refused, may ask again ».
- **Android's « Seulement cette fois »:** the permission lapses after the app has
  been away a while; the phone says « not decided » again, the flag is set, so
  nothing shows by itself, and « Me localiser » asks again.
- **Android 9, the reference phone:** approximate on every version; how far off
  it is there is UNVERIFIED (§8.4).
- **Google's own « turn on location » dialog.** On a phone with Google Play
  services, the read itself can open it when the phone's location settings do
  not meet the request (`FusedLocationClient.java:236-257`), and the 30-second
  bound covers that wait too (`geolocator_android.dart:121-123`). If the person
  takes longer, « Position introuvable » appears and « Réessayer » reads again.
  Refusing Google's dialog answers « location off ».
- **One read at a time.** A second request while one runs breaks the plugin: on
  Android the second `requestPermission` replaces the first's callback, and an
  empty answer is never returned, so the first waits for ever
  (`PermissionManager.java:113-118`, `:148-153`); on iOS a second read replaces
  the first one's handler (`GeolocationHandler.m:76-77`) and a second request is
  refused (`PermissionHandler.m:53-57`). So the flow is shared and single:
  whoever calls while it runs gets the read already running (§5), and the
  buttons are disabled.
- **A phone without Google Play services** (some Huawei): the plugin falls back
  to Android's own location manager. With approximate only and « medium »,
  whether it finds a provider is **UNVERIFIED**; a failure lands on « Position
  introuvable », never on an endless loader, because of the bound.
- **No network:** location works without it; only the tiles may be missing.
- **A salon opened on the map** (`focusProviderId`): its sheet is on top; the ask
  banner waits under the scrim and is there when the sheet closes. An allowed
  position never moves the camera off that salon (as today).
- **The person allows in the Settings while the picker or the Pro screen is
  open:** nothing happens by itself there; the next tap works. Only the map
  listens for the return, and only from Settings it opened.
- **Long French at 200 %:** the banner's sentence wraps; its two actions sit under
  it, at the end, and wrap to two lines if they must (§8.2's 360 × 200 % row).

### 2.5 Accessibility

- Every action is a `TextButton` (≥ 48 × 48, SYSTEM §13.2), its label a verb.
- Every banner is a live region; a snackbar announces itself; the picker's
  sentences are live regions already (`InlineFeedback`).
- **Focus, when the focused button goes away** (SYSTEM §13.5):
  - the banner removed (« Plus tard », « Fermer », or an allowed outcome): to
    « Me localiser », which stays on the screen throughout;
  - the banner replaced by another: to the new banner's last action, the way
    out (« Autoriser », « Ouvrir les réglages », « Réessayer », or « Fermer »).
- « Votre position » labels the dot; the accuracy circle is decoration, excluded
  from semantics.

## 3. API & contract

None. No request changes; the position stays on the client's phone (§0).

## 4. Data model

One boolean on the phone, `SharedPreferences` key `location_explained`. It is
set:
- at the start of every `locate()`: every tap that runs the flow, in any of the
  three places, whatever the outcome;
- when the ask banner's « Plus tard » is tapped.

`status()` never sets it. Never sent, never synced; removing the app removes it.
(The plugin cannot say whether a dialog was actually shown, §0, so the flag
records the person's tap, which can be tested, not the dialog.)

## 5. Architecture

- **`lib/core/location/location_access.dart`** — the shared flow, on
  `GeolocatorPlatform.instance` (so a test answers the plugin's channel, as
  `map_commune_test` already does):
  - `Future<LocationStatus> status()`: `allowed`, `undecided`, `blocked`, `off`,
    `unknown`. **No dialog, never throws:** it reads the location service
    first, then the permission; an exception or an empty answer is `unknown`
    (`carto_basemap_layer_test` answers nothing at all, and the plugin's
    `checkPermission` throws on a `null`, `method_channel_geolocator.dart:40-43`);
  - `Future<LocationOutcome> locate({required LocationAccuracy accuracy})`: the
    dialog when the phone allows one, then the position, bounded to 30 s. A
    sealed result: `Located(position, approximate)`, `Refused`, `Restricted`,
    `Blocked`, `Off`, `Failed`. On iOS, a `denied` answered by
    `requestPermission` is `Restricted`: iOS answers so only for a restricted
    phone (`AuthorizationStatusMapper.m:13-15`, `PermissionHandler.m:47-50`).
    **One read at a time, app-wide:** a call while one runs returns the running
    one;
  - `openAppSettings()`, `openLocationSettings()`: never throw, log a failure
    (as `openSystemNotificationSettings` does, `core/push/system_settings.dart`).
  - It is not a `*ServiceInterface`: it reaches no server. It sits in `core/`
    beside the push settings opener.
- **The three call sites** keep their own wording (§2) and call it.
- **The map** listens to the app's lifecycle only between its own « Ouvrir les
  réglages » and the next return (§2.1).
- **`_MapBanner`** gains a second action (under the sentence, at the end), and
  the location banner leaves its inline action, the one consumer-search.md kept
  « as it was (A6 rewrites it) » (`map_screen.dart:633-636`).
- **`InlineFeedback`** gains an optional action (a label and a callback): the
  picker needs « Ouvrir les réglages » inside the sheet. A component change,
  recorded in SYSTEM §11.1.
- **A colour token** for the accuracy circle, `AppColors.locationAccuracy`
  (`info` at a fixed alpha), added to SYSTEM §3.4 first.
- **The manifests:** `main/` keeps `ACCESS_COARSE_LOCATION` and loses
  `ACCESS_FINE_LOCATION`; a new `pro/AndroidManifest.xml` declares
  `ACCESS_FINE_LOCATION` alone (Gradle merges it into Pro's). Each comment says
  why, and points here.
  - *Considered and left out:* `tools:node="remove"` in a `consumer/` manifest,
    which would strip precise location from any plugin that brings it back. A
    silent strip would also hide a dependency that needs it; §8.3's CI read
    fails loudly instead, and a person decides.

## 6. Security & privacy

- **Less is asked.** After A6 the client app cannot read a precise position on
  Android at all; on iOS it asks for « medium », 100 m
  (`kCLLocationAccuracyHundredMeters`, `LocationAccuracyMapper.m:21`).
- **Nothing new leaves the phone.** The client's position is still never sent
  (§0). The privacy policy's paragraph stays true as written; it is not edited.
- **Play's Data safety and Apple's label** for the client app are unchanged by
  this (location not collected: it never leaves the phone). B3 derives them
  from the binary anyway.
- No new dependency (`geolocator` already opens both Settings pages).

## 7. Performance

- Nothing at start-up; the map's opening does two reads (the service, the
  permission) instead of a dialog.
- « Medium » usually answers sooner than « best »: Android asks for balanced
  power accuracy rather than high (`FusedLocationClient.java:139-145`), iOS for
  100 m. And no read runs longer than 30 s, where today none is bounded.

## 8. Testing plan

### 8.1 Unit and widget (answering the plugin's channel)

- **`location_access_test`:**
  - each phone answer maps to its outcome: `whileInUse`, `always` → located;
    `denied` then `denied` → refused on Android, **restricted on iOS**
    (`debugDefaultTargetPlatformOverride`, reset in a `finally`); `denied` then
    `deniedForever` → blocked; service off → off; a timeout and a thrown error →
    failed; `reduced` → approximate;
  - `status()` never calls `requestPermission`, and answers `unknown` when the
    channel answers nothing or throws;
  - two `locate()` at once: one `requestPermission`, one `getCurrentPosition`,
    both callers get the same result;
  - the flag: set by `locate()` whatever its outcome, never by `status()`.
- **The map (`map_location_test`):**
  - opening, undecided, flag unset: the ask banner, and **no**
    `requestPermission` call (gap 22's defect itself);
  - opening, undecided, flag set: nothing; opening, allowed: the dot, no banner,
    no request; opening allowed but the read fails: nothing; opening with a
    salon: the camera stays on the salon;
  - « Activer » → allowed: the dot (« Votre position »), the circle, no banner;
    an approximate position: the camera fits the circle;
  - each outcome row of §2.1 (the iOS rows under the platform override): its
    sentence, its actions, and what each action calls (`openAppSettings`,
    `openLocationSettings`, `requestPermission`);
  - while a read runs, the actions are disabled;
  - « Plus tard »: hidden, and a new map does not show it again;
  - back from Settings the map opened, now allowed: the dot, no dialog; now
    location off: the off banner; a return the map did not cause (the dialog
    closing): no second read;
  - focus after « Plus tard » and after a replaced banner (§2.5);
  - « Me localiser » with no position runs the flow; with one, centres (as
    today).
- **The picker:** each row of §2.2, inside the sheet, with no snackbar in the
  tree; « Ouvrir les réglages » calls the right opener.
- **Pro's profile:** each row of §2.3, and the approximate line.
- **The tests that pump the map today**, five files: `map_commune_test`,
  `salon_location_map_test`, `carto_basemap_layer_test` (no channel answered:
  `status()` must say `unknown`), `consumer_bottom_nav_test` (the route) and
  `consumer_search_golden_test`. They keep passing; the map goldens of the last
  change, since today's « Localisation désactivée » banner no longer shows on
  opening.

### 8.2 Accessibility and goldens

- The map at 360 × 200 % with the ask banner and with the blocked banner: no
  overflow, both actions whole (the `layout_test` shapes).
- `labeledTapTargetGuideline` on the map with each banner.
- New goldens: the ask banner, the blocked banner, the dot with its circle;
  the changed ones of §8.1. Authored on Linux by `goldens.yml`, every PNG
  opened.

### 8.3 The manifests

- **Source (`test/infra/android_location_permission_test.dart`):** over
  `android/app/src/*/AndroidManifest.xml` only (never `build/`, which holds
  merged manifests naming the permission), with XML comments stripped first
  (this manifest's comments name it): none but `src/pro/` declares
  `ACCESS_FINE_LOCATION`; `src/main/` declares `ACCESS_COARSE_LOCATION`;
  `src/pro/` declares `ACCESS_FINE_LOCATION`.
- **The built APK (CI, the `apk-size` job, which already builds the client):**
  `tool/verify_android_location.sh` reads `aapt2 dump badging` and passes only
  when the client APK has a line for `ACCESS_COARSE_LOCATION` and **no line of
  any form** naming `ACCESS_FINE_LOCATION` (`uses-permission`,
  `uses-permission-sdk-23`, with or without `maxSdkVersion`). The source pin
  cannot see a plugin's manifest bring precise location back; this can. A
  `--badging <file>` form runs its refusal paths on every PR, one fixture per
  form (`backend/test/infra/android_location_test.dart`, the shape of
  `android_portrait_optional_test.dart`).
- **Pro's AAB:** step 5 of android-play-release §4 already reads each AAB's
  permissions; it gains « `ACCESS_FINE_LOCATION` present ».
- **What these cannot see:** whether the plugin, with approximate only, returns
  a position on a real phone, and how far off it is. That is §8.4's.

### 8.4 Device rows (with the first client build, Track C; and Pro's next)

**UNVERIFIED until run.** On the Galaxy (Android) and the iPhone:
1. First opening of « Carte »: no system dialog; the ask banner.
2. « Activer »: Android's dialog offers approximate location only; allowed, the
   dot, its circle, and the camera fitted to it. Write down the radius.
3. Refused for good (Android 11 or later: refuse twice; iOS: once): the blocked
   banner; « Ouvrir les réglages » opens MyWeli's page; allow there, come back:
   the dot, no dialog.
4. Location off: « Ouvrir les réglages » opens the phone's location page
   (Android); the iOS sentence gives the path.
5. « Près de moi » after a refusal for good: the button inside the sheet works.
6. **MyWeli Pro** (its next build): « Utiliser ma position » still offers
   « Précise » on Android 12+; choosing « Approximative » shows the approximate
   line.

### 8.5 Mutations, each watched red on the committed code

The flow calling `requestPermission` in `status()`; `status()` rethrowing; the
map calling `locate()` on opening; the flag not set by `locate()` on a refusal,
or not set by « Plus tard », or set by `status()`; iOS's `denied` mapped to
refused instead of restricted; the single read removed (two callers, two
requests); the return-from-Settings read without its guard; `openAppSettings`
swapped for `openLocationSettings`; the bound removed; the camera not fitted to
the circle; FINE put back in `main/`; FINE removed from `pro/`; the APK verifier
accepting the `uses-permission-sdk-23` form; the approximate line shown for a
precise position; the dot's label removed. A mutation that does not apply is no
result.

## 9. Rollout

- **One app PR (A6)**, after this spec is approved; its merge on the owner's
  word. No backend, no website, no console.
- It reaches people **only with builds**: the client's first build (Track C,
  which A6 unblocks with A1–A3) and MyWeli Pro's next. Pro's current builds
  (794 on Play's closed test, 781 on TestFlight) are untouched.
- **Play:** once a client AAB without `ACCESS_FINE_LOCATION` is the one
  submitted, the client app needs **no** precise-location declaration
  (2027-01-27). If the client's first AAB is built before A6 merges, it would
  need one. Pro's declaration is unchanged (android-play-release §7.1).
- **Later, FR-BOOK-010 (V2, à domicile):** a client's address pin needs a
  precise position. That slice either places the pin by touch, as Pro does, or
  brings `ACCESS_FINE_LOCATION` back to the client with its declaration. Said
  here so the coarse-only choice is not mistaken for a permanent one.

## 10. Docs the build updates

- android-play-release §7.1: its last bullet (« Later, with the client app »)
  says A6 did it, with the PR; play-store-forms §8 (B3): no location
  declaration for the client.
- consumer-search.md §2.8's last bullet: the location banner is this spec's.
- The audit: row A6, gaps 13 and 22, §3.3's `ACCESS_FINE_LOCATION` line.
- SYSTEM.md: §3.4 (the new token), §11.1 (`InlineFeedback`'s action), §12
  (the location banners beside `PushBlockedBanner` as permission-denied states).
- The roadmap entry, BACKLOG B0.10's journal.

## 11. Questions for the owner (decisions 272–276) — answered 2026-11-27, all five as recommended

1. **(272) Precise location for MyWeli Pro only; the client app asks for
   approximate location on Android?** *Recommended: yes.* The client uses its
   position to centre a map and pick a commune; approximate does both, and spares
   the client app Play's declaration, whose question is exactly « why is
   approximate not enough? ». The price: « Près de moi » may pick a neighbouring
   commune (§2.2), which the person sees and can change. *Alternative:* keep
   precise for both and declare for the client too.
   → ✅ **Decision 272, as recommended** (2026-11-27).
2. **(273) The map explains once, in its banner, and never opens the dialog by
   itself?** *Recommended: yes*, with « Plus tard » and « Activer », and nothing
   on later openings once the person has tapped either, or asked anywhere else
   (§2.1, §4). *Alternative:* the banner on every opening until the person allows
   or refuses for good (more reminders, more noise over the map).
   → ✅ **Decision 273, as recommended** (2026-11-27).
3. **(274) « Ouvrir les réglages » after a refusal in all three places, MyWeli
   Pro's « Utiliser ma position » included?** *Recommended: yes.* One shared flow
   (§5): the picker is shared, so Pro gets it there anyway, and leaving Pro's
   button on its own copy keeps a second flow. It reaches Pro only with its next
   build, and adds row 6 to that build's device pass. *Alternative:* the client's
   two places now, Pro's button in a Pro follow-up (the review's suggestion,
   §14).
   → ✅ **Decision 274, as recommended** (2026-11-27): Pro's button is in A6.
4. **(275) The client reads its position at « medium », bounded to 30 s, and the
   map draws the accuracy circle, the camera fitted to it?** *Recommended: yes.*
   Faster, never an endless loader, and an approximate position shown as one.
   *Alternative:* « best » with the bound only, no circle.
   → ✅ **Decision 275, as recommended** (2026-11-27).
5. **(276) MyWeli Pro says when the phone gave an approximate position for the
   pin?** *Recommended: yes*, the line under the map (§2.3); it is also what makes
   Pro's declaration honest: precise is asked because the pin needs it.
   *Alternative:* nothing, as today, or in the Pro follow-up of 274's alternative.
   → ✅ **Decision 276, as recommended** (2026-11-27).

## 12. Definition of done

- [x] `flutter analyze` 0 · format clean · the full app suite green (sequential) (§15).
- [x] Every outcome of §2.1–§2.3 rendered and tested; the four states and the
      permission-denied state on the map (SYSTEM §12).
- [x] Tokens only (the new colour added to SYSTEM first); 48 dp targets; 200 %
      at 360 dp; live regions and focus where §2.5 says.
- [x] The source pin and the APK read in CI, each watched red; §8.5's mutations
      listed in the commit message (§15).
- [x] Goldens authored on Linux, every changed PNG opened.
- [x] §10's docs updated in the same PR; this spec's status line.
- [ ] Feature branch, PR, CI green; merged on the owner's word.

## 13. Seen in passing (not A6)

- **Pro's pin map does not follow « Utiliser ma position ».** `_LocationField`
  gives `FlutterMap` an `initialCenter` (`pro_salon_profile_screen.dart:506-509`)
  and no controller; flutter_map 8.3.2 keeps its camera when the options change
  and reads `initialCenter` only for the first one (`map_controller_impl.dart:328-330`).
  So after the button the pin moves and the camera stays at zoom 11.5 over
  Abidjan: a salon outside that view gets its pin off screen, and adjusting it
  means zooming by hand. **UNVERIFIED on a phone**; read in the code only. A
  small Pro follow-up.

## 14. Independent review (2026-11-27)

One reader, told to refute this spec, read it against the code and the plugins'
sources: 12 findings. Each was checked here in the source before it was taken.

| # | Finding | Taken |
|---|---|---|
| 1 | iOS `restricted` reads as `denied`, and `requestPermission` answers it at once: « Autoriser » would have looped on a restricted iPhone, the very dead end A6 removes | yes: a `Restricted` outcome with no retry (§2.1–§2.3, §5), tested under the iOS override |
| 2 | Nothing stopped two reads at once; the dialog's closing also brings the app back to the foreground; the plugin breaks on a second request (Android hangs, iOS replaces) | yes: one read app-wide, buttons disabled, the return from Settings guarded (§2.1, §2.4, §5) |
| 3 | Back from the Settings, the banner kept its old reason; on iOS, « Ouvrir les réglages » cannot turn the location service on | yes: the banner rebuilt from `status()`; iOS's « off » gives the path in words, no button |
| 4 | « Set when the dialog is shown » could be neither built nor tested: the plugin never says whether a dialog was shown | yes: the flag records the tap (§4) |
| 5 | The accuracy is a radius: an approximate circle about 4 km across would fill the screen at zoom 13.5; « not rounded before Android 12 » was doubtful | yes: the camera fits the circle; the radius left for §8.4; the Android 9 claim removed |
| 6 | On Android 6–10 a second plain refusal is not final; only « Ne plus demander » is | yes (§2.4, §8.4 row 3) |
| 7 | Five test files pump the map, one answers no channel, a golden shows today's banner; the source pin would have read `build/`; the APK read missed other badging forms | yes (§5, §8.1, §8.3). Its suggestion of `tools:node="remove"`: not taken (§5) |
| 8 | Google's own « turn on location » dialog can open inside the read, under the bound | yes: the bound raised to 30 s, the case written (§2.4) |
| 9 | « Aucune commune trouvée près de vous » was false: `nearestArea` has no distance limit | yes: « Liste des communes indisponible. Réessayez. »; the line is `:106` |
| 10 | « Focus stays where it was » was impossible: the focused button disappears | yes: where focus goes is named (§2.5) |
| 11 | Pro's half is not required by gaps 13 and 22; the ask banner's « not a live region » reason was wrong; a failed silent read at opening was unspecified | the live region and the failed read: yes. Pro's half: left to the owner (kept: decisions 274 and 276, 2026-11-27), with the follow-up as 274's and 276's alternative |
| 12 | « Position introuvable. Réessayez. » offered no alternative; the picker's « off » sentence said nothing to do | yes (§2.1–§2.3) |

What it tried to refute and could not: which page each Settings opener opens;
« medium » on both platforms; Android never answering « refused for good » before
a request; iOS's first refusal being final; iOS asking « while using »; the
approximate-only dialog with COARSE alone; the merged Pro manifest; no client
coordinate sent; the distances between commune centres; the flutter_map camera;
every other line citation.

## 15. As built (2026-11-27)

Built on the owner's « Yes, build A6 », branch `feat/a6-location` from `main`
`3a2cb1d7`, one app PR (§9). The files:
- `lib/core/location/location_access.dart`, the shared flow (§5);
- `map_screen.dart`, `commune_picker_sheet.dart` and
  `pro_salon_profile_screen.dart` call it;
- `InlineFeedback` gains `action`, and `AppColors.locationAccuracy` is new
  (SYSTEM §3.4, §11.1, §12);
- `android/app/src/pro/AndroidManifest.xml` is new;
- the CI step, `tool/verify_android_location.sh`;
- on the web, the token mirror: `web/scripts/dart-tokens.mjs` now reads a
  translucent `Color(0xAARRGGBB)` as `#RRGGBBAA`, and `web/styles/tokens.ts`
  carries `locationAccuracy` (no web class uses it yet).

**Found by CI on the PR:** the web's token mirror gate refused the new token
by name: its parser read only opaque colours, and every `AppColors` token must
reach the web. Six mutations of the fix (the token removed, opaque or another
alpha, the parser opaque-only or dropping the alpha, the Dart token opaque)
each turned the gate or the contrast ledger red. **Merging this PR deploys
`myweli.com`,** with no visible change.

**Read on the built artifacts (2026-11-27, aapt2 2.20, arm64 release APKs
built on this Mac):**
- the client APK from `main` declared `ACCESS_FINE_LOCATION` and
  `ACCESS_COARSE_LOCATION`, gap 13 on the binary itself;
- the client APK with A6 declares `ACCESS_COARSE_LOCATION` alone;
- MyWeli Pro's APK with A6 declares both.

The verifier refuses the first badging and Pro's (exit 1) and accepts the
second; its fixture test uses those lines.

**Where the build departs from the text above, and why:**
- **`locate({accuracy, ask})`.** `ask: false` never opens the dialog and
  never sets the flag. It is the map's silent read on opening and after the
  Settings. §4's « every `locate()` » is every `locate()` that may ask, every
  tap. A permission withdrawn between the `status()` and the read cannot open
  the dialog by itself.
- **The outcomes' names:** `Located`, `LocationRefused`, `LocationBlocked`,
  `LocationRestricted`, `LocationOff`, `LocationFailed` (§5's short names,
  prefixed).
- **Opening « Carte » on Android shows only a recent position** (§15.1 #6):
  the phone's last position from `getLastLocation()`, if it is under 15
  minutes old (`LocationAccess.recent`), and no read. A read there can open
  Google's « turn on location » dialog. iOS keeps the silent read of §2.1.
- **Back from the Settings, « not decided » depends on the page** (§15.1 #3,
  #4):
  - from the phone's location page, it is the ask;
  - from the app's page, it is « bloquée » on Android, where nothing else can
    be read, and « refusée » with « Autoriser » on iOS (« Demander la
    prochaine fois »).
- **The permission request gives up after 2 minutes** (§15.1 #5); the 30 s
  bound is the read's.
- **The framing never zooms closer than a precise position** (13.5, or 14
  for « Me localiser »), and keeps the circle below the pill (§15.1 #7).
- **The 30 s bound is the plugin's own `timeLimit`.** A `.timeout` around the
  call would leave Android's native request running; the plugin's limit
  cancels it (`cancelGetCurrentPosition`, `geolocator_android.dart:128-136`).
- **« Me localiser » is not disabled while a read runs.** It shows the loader
  and its tap does nothing, so it keeps the focus it holds (§2.5); a disabled
  button drops it. The banner's actions are disabled, as §2.1 says.
- **« Me localiser » always moves the camera to the position,** even with a
  salon opened: the person asked for it. The banner's actions do not move it
  off an opened salon (§15.1 #2).
- **The return from the Settings counts only once the app has left**
  (`hidden` or `paused`), then a `resumed`. A resume without a departure is
  not a return.
- **Back from the Settings, `unknown`** leaves the banner as it was.
- **The picker clears its last sentence** when « Près de moi » is tapped
  again, so the new outcome is announced.
- **An unreadable accuracy status** is not called approximate: Pro's line
  says nothing rather than something wrong.

**Seen while building:**
- **Under an opened salon's sheet, the dot is hidden from screen readers.**
  Its scrim blocks the map's semantics, as for every pin.
- **flutter_map does not build off-screen markers.** The dot off the camera
  is in the layer, not in the tree.
- **A test that answers nothing on the plugin's channel never sees `status()`
  return** on the fake clock. The engine answers on the real one: the unit
  test reads it in `runAsync`. The map then shows nothing, as it should
  (`carto_basemap_layer_test`).

**Known limits** (§15.1 #8, #10, #11):
- on Android 11+, dismissing the first dialog reads as « bloquée »;
- while a banner's read runs, the keyboard focus leaves its button, and comes
  back when the read ends;
- a read that joins one already running keeps that one's accuracy;
- refusing Google's own dialog reads « La localisation du téléphone est
  désactivée », as §2.4 says, though the phone's location may be on.

**Not verified:**
- every device row of §8.4 (with the first client build, Track C, and Pro's
  next build);
- the radius a real approximate position reports, and so the circle's size;
- a phone without Google Play services.

### 15.1 The build's independent review (2026-11-27)

One reader, told to refute the build, read the code against this spec and the
plugins' source. It ran nothing. It made 11 findings. Each was checked in the
code or the plugin before anything changed.

| # | Finding | Taken? |
|---|---|---|
| 1 | The goldens were not in the commit it read | they were in the tree, from `goldens.yml`; committed |
| 2 | « Activer », « Autoriser » and « Réessayer » moved the camera off a salon the person opened, against §2.1 and this section's own claim | yes: they recentre only with no salon opened; a test |
| 3 | Android: back from the app's Settings with nothing changed, « bloquée » became « refusée », then « bloquée » again on « Autoriser ». Android's `checkPermission` never says « refused for good » (`PermissionManager.java:63-64`), so §2.1's return table could not hold there. The test's fake phone answered like iOS | yes: on Android, « not decided » after the app's page keeps « bloquée »; the fake answers like each platform. **The price:** a person who chose « Demander à chaque fois » there also sees « bloquée »; « Me localiser » still asks |
| 4 | Back from the phone's location page, a person who never refused anything read « Localisation refusée » | yes: from the location page, « not decided » is the ask |
| 5 | A permission request that never answers held every location button in the app until it restarted: Android drops the callback on an empty result (`PermissionManager.java:148-153`), and the 30 s bound covered only the read | yes: the request itself gives up after 2 minutes (`permissionBound`), and the next tap asks again |
| 6 | The silent read on opening could open Google's « turn on location » dialog (`FusedLocationClient.java:236-257`), on every opening for a phone whose settings do not meet the request. « Medium » could add phones to that list | yes, on Android: opening shows only the phone's last position, from `getLastLocation()` (no setting checked, no dialog), if it is under 15 minutes old. Otherwise nothing, and « Me localiser » reads a new one. iOS keeps its silent read: no such dialog there. **The price:** on Android, a dot on opening only when the phone located itself recently |
| 7 | Framing zoomed IN for circles of 500 m to 2.4 km (600 m gave about 15.5), and the pill covered the circle's top | yes: never closer than the zoom a precise position gets, and the circle below the pill and its lines; tests at 600 m and 3 km |
| 8 | Android 11+: dismissing the first dialog (Back, or a tap outside) answers « refused for good » (no rationale left, `PermissionManager.java:183-186`), so « bloquée » shows while the next tap would show the dialog again | **no, noted:** the plugin cannot tell them apart; a timing guess would be fragile. « Ouvrir les réglages » still works, and so does « Me localiser » |
| 9 | `setState` after leaving the map, if the opening's status read was still pending | yes: `mounted` checked after it, and at the read's start |
| 10 | A banner action disabled while its read runs drops the keyboard focus it held | **no, noted:** focus comes back to the way out, or to « Me localiser », when the read ends (§2.5) |
| 11 | A read that joins one already running keeps that one's accuracy (Pro: « Près de moi » at medium, then « Utiliser ma position ») | **no, noted:** it takes closing the picker mid-read and tapping within the same seconds; the pin can still be placed by touch |

Minor, taken: the verifier's comment claimed to catch an implied feature's
reason, which its quoted match cannot; it now says what it matches. The
source pin reads either XML quote.

What the reader tried to refute and could not:
- the single read's bookkeeping;
- iOS's mapping, restricted included;
- the Android plugin's handling of approximate-only and of « Approximative »
  in Pro;
- the return-from-Settings gate (the permission dialog makes the app inactive
  only; the Settings app makes it hidden and paused);
- the 30 s bound cancelling the native read;
- the copy of the picker and of Pro;
- the manifests' merge;
- the verifier and its CI step.
