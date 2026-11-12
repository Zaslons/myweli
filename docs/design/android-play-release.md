# MyWeli Pro on Google Play — the first Android release

| | |
|---|---|
| **Module** | release (mobile, Pro flavour `com.myweli.pro`; Play Console) |
| **Status** | **Approved 2026-11-11** — the owner's « Valider tel quel » on the plan and on decisions 110–115 ([BACKLOG](../BACKLOG.md)). Decision 115's cost was understated when asked; told the corrected facts, the owner confirmed « Rester professionnel » the same day (§3.6). Nothing built, nothing typed in the console yet. |
| **Last updated** | 2026-11-11 |
| **BACKLOG items** | B0.10 (the Play forms and the closed test), B13.1 (#758), B13.3 (firebase), B13.10 (#759) |
| **PRD ref / phase** | V1 · NFR-PERF-002 (APK < 30 MB) · ROADMAP Part 6 (the reference low-end Android) |
| **ROADMAP entry** | added when the production release ships (`docs/roadmap/entries/`) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [play-store-forms.md](play-store-forms.md) (every answer typed in the console) · [LAUNCH.md](../LAUNCH.md) §6.3 · [mobile-flutter-3.47-upgrade.md](mobile-flutter-3.47-upgrade.md) · `android-tls-artifact-gate.md` (arrives with #759) · [mobile-store-submission.md](mobile-store-submission.md) §2 · [mobile-external-testing.md](mobile-external-testing.md) · [client-version-gate.md](client-version-gate.md) |

How to read it: **observed** means read or run here on 2026-11-11, with where.
**Recorded** means a past session observed it and the repo says so; it was not
re-read today. **UNVERIFIED** means nobody here has seen it.

## 1. Goal & scope

MyWeli Pro reaches Android users through Google Play: first a closed test of
12 testers for 14 days (decision 52, a personal developer account), then
production with a staged rollout.

- **In scope:** the Pro app only (decision 51), its AAB, the Play Console
  steps, the two new Play declarations (§7), the device checks R8 and the
  reference device need (§5), and the docs that describe all of it.
- **Out of scope:** MyWeli (client) on Play (play-store-forms §8, later);
  converting the Play account to an organisation (not now; play-store-forms
  §6); AGP 9 and built-in Kotlin (B13.6, before Flutter 3.50); moving
  `ACCESS_FINE_LOCATION` out of the client flavour (§7.1, with the client app).
- **Not a feature.** No screen changes. The code that moves is the toolchain
  (#758), the firebase bump (B13.3), the version, and the R8 configuration
  (§6). Each is its own PR.

## 2. What already exists

LAUNCH §3 still says Android has « no keystore, no Play account, R8 unproven ».
All three are out of date.

- **Recorded 2026-08-26** ([signing-manifest.json](../../infra/mobile/signing-manifest.json),
  [roadmap entry](../roadmap/entries/2026-08-26-true-play-delivery-shas.md)):
  - the upload keystore exists, and the owner holds its passwords. Its
    **backup** was never checked (§4, step 4). On 2026-11-11 the owner did
    not remember one and none was found, so they made one that day: §11, O1;
  - both apps exist in the Play Console, enrolled in Play App Signing
    (`"enrolled": true`);
  - the Pro app's Play signing certificate, `94be494a…`, was read from the
    bytes of the APK Play installed (the device showed versionCode **526**),
    and registered on its Android OAuth client;
  - Google sign-in worked on that installed build (`/auth/google` 200 with the
    Dart user agent).
- **Recorded 2026-10-28** (play-store-forms §0.1): the listing, its images
  and the 10 « Contenu de l'application » declarations are saved. Nothing was
  sent for review.
- **Observed: `mobile/android/key.properties` exists** in the main checkout
  (`/Users/…/beauty app`), not in worktrees, with mode `644` (readable by
  every account on the Mac). Its contents were not read.
- **Observed: R8 is on.** Flutter's Gradle plugin sets
  `releaseBuildType.isMinifyEnabled = true` unless the `shrink` property is
  false (`FlutterPlugin.kt` 216–218 on 3.47.9, 215–217 on 3.44.9). Nothing in
  this repo sets that property. A consumer release APK built on this Mac on
  2026-11-11 01:09 carries the dex marker
  `~~R8{"compilation-mode":"release",…,"r8-mode":"full","version":"8.11.18"}`,
  and next to it a 21.8 MB `mapping.txt`. So release builds go through R8;
  build 526's own bytes were not read, but nothing has ever set `shrink`
  either. The comment in
  `app/build.gradle.kts` (« R8 … is deliberately NOT enabled ») and
  mobile-store-submission.md §2 are wrong. Not yet observed on a **Pro AAB**;
  step 5 reads it on the real artifact.
- **Observed: the SDK levels**: `compileSdk` 36, `targetSdk` 36, `minSdk` 24 on
  both Flutter versions (`FlutterExtension.kt`), with the app's floor
  `maxOf(24, flutter.minSdkVersion)`. Play has required target 36 since
  2026-08-31.
- **Observed: the build number.** `release_build.sh` uses `main`'s commit
  count, 742 on 2026-11-11, above Play's 526.

## 3. Decisions (2026-11-11, « Valider tel quel »)

### 3.1 Decision 110 — the plan and the order in §4

The eleven steps below, in that order, each console action on the owner's word at that moment.

### 3.2 Decision 111 — the first AAB is 0.0.2

The same version as iOS's next build. One `pubspec.yaml` bump, after #758
(spec O4 there), serves both stores. The build number stays the commit count,
so one commit built for both stores carries the same number on both.

### 3.3 Decision 112 — keep R8, verify it on a device

R8 is on in release builds (§2). The decision is to keep it and
make it explicit, not to switch it on:

- `isMinifyEnabled = true` written in `app/build.gradle.kts`, with the false
  comment replaced;
- the device pass of §5 on a Play-installed build;
- the mapping file sent to Sentry and to Play (§6).

The other choice, `isMinifyEnabled = false` stated explicitly, gives up the
shrinking release builds have had. No size difference was measured for
the owner.

### 3.4 Decision 113 — Play's description is the App Store's

The text published on the App Store (app-store-forms §4) is copied to
play-store-forms §1, word for word. It carries four edits that Play does not
have yet (decisions 74 and 79). Two of them correct facts: there is no week
view, and « à domicile » is not in the Pro app. The guard becomes strict
(§9). The console keeps the old text until step 7 types the new one.

### 3.5 Decision 114 — countries

- **The closed test:** Côte d'Ivoire, plus the country of each tester
  (play-store-forms §6.2).
- **Production:** every country possible, like decision 108 on the App Store.
  The trader declaration (§3.6) comes first.

### 3.6 Decision 115 — trader on Play — confirmed with the corrected cost

The owner chose « trader », as on Apple. **What they were told is wrong:** that
their details would be published « in the EU, as at Apple ».

Google's page ([answer 17594752](https://support.google.com/googleplay/android-developer/answer/17594752?hl=en),
read 2026-11-11) says otherwise:

- **From 2027-03-01, everywhere:** contact details and a link to the app's
  terms are shown. For a **personal** account that declares trader, that means
  **« a phone number and address »**.
- **In the EEA and the UK only:** the developer's name replaces « Google » in
  « Offered by », and the self-certification is shown.

So the owner's phone number and address would be on the listing worldwide.

**Put back to the owner the same day, in those words, with the alternative
below. Their answer, 2026-11-11: « Rester professionnel ».** So step 7
declares trader for the account and then for MyWeli Pro.

- **Google's criteria:** it determines nothing for you. A trader receives or
  intends to receive « remuneration for your apps » on a regular or commercial
  basis, and manages publishing « as a business ».
- **The alternative Google allows:** declare **non-trader** only if no app is
  distributed in the EEA or the UK. That contradicts decision 114.
- **Misdeclaring as non-trader** « may result in account suspension or
  termination globally ».

## 4. The order

Each step names who acts and what it leaves behind as evidence. « Yes » means
the owner's explicit word at that moment: green CI or a ready artifact is
never a go-ahead for a console action.

| # | Step | Who | Gate | Evidence it leaves |
|---|---|---|---|---|
| 0 | This spec, and the docs PR that corrects what is out of date | Claude | the owner's review | this PR |
| 1 | Merge #758 (Flutter 3.47.9); then #759 (the TLS artifact gate), rebased | the owner merges; #759 belongs to its own session | yes | squash tree == PR tree |
| 2 | B13.3: firebase_messaging 16.7.x, its own PR from `main`, lockfile regenerated on 3.47.9 | Claude | merge | the Android 13+ « never asked = denied » branch tested |
| 3 | `version: 0.0.2+1` in `pubspec.yaml` (decision 111); the R8 PR (§6) | Claude | merge | the guards of §9 |
| 4 | The upload key's backup: none was known (§11, O1), so the owner made one on 2026-11-11. **The file:** `~/myweli-upload.jks` is on the owner's Google Drive. It was downloaded back to this Mac and compared with the original: equal SHA-256 (`3aee730f…0be0e3`) and `cmp` 0. The download then went to the Trash. Because the copy is byte-identical, it opens wherever the original does, so `keytool -list` on it would prove nothing more. **The passwords:** in Apple Passwords, which iCloud Keychain syncs off this Mac (sync observed on). The owner compared the saved passwords with the ones `key.properties` holds, using a `getpass` comparison in their own terminal that prints only « matches » or « is DIFFERENT ». They reported **both « matches »** (that terminal's output is not visible here). Then, on this Mac: `key.properties`' store password opens the keystore, and it unlocks the private key under alias `upload`. `keytool -list` and `-certreq` both exit 0, with the passwords passed through the environment and nothing printed; as a control, a wrong password exits 1. The key password equals the store password, which PKCS12 requires. `chmod 600 key.properties`: dropped by the owner, because this Mac has one account (§10) | the owner, with Claude | — | **done 2026-11-11:** two equal hashes; both passwords « matches »; `keytool` opens the key with them |
| 5 | The AAB from `main`, in the main checkout: `./tool/release_build.sh android pro`. Then on the artifact: the TLS gate (#759), the R8 marker, `BUNDLE-METADATA/…/proguard.map` present or not, permissions with `aapt2`/`bundletool`, size; Sentry: Dart symbols + the mapping (§6) | Claude, on the owner's yes | yes | the script's lines, the reads |
| 6 | Upload to the **internal** track, roll out to the owner; the device pass of §5 on the owner's phone and on the reference device | Claude in the browser pane (the owner signed in); the owner holds the phones | yes for the upload | §5's table filled in |
| 7 | Re-read the Play dashboard (last read 2026-10-28). Type the listing text (decision 113). Fill in the location declaration (§7.1) and the trader declaration (§3.6, « trader », confirmed 2026-11-11) | Claude in the pane; the owner signed in | yes for each form | each form read back after saving |
| 8 | The Google Group; the closed track (countries, decision 114; testers = the group); **promote the same release** from internal to closed; send it to Google's review | the owner and Claude | yes | the track's state read back |
| 9 | The test salon, the invitations, play-store-forms §6.3–§6.5; 12 testers opted in for 14 days in a row | the owner | — | the console's tester count, day by day |
| 10 | Apply for production access (Google usually answers in 7 days or less), then production at a staged rollout (§8) | the owner and Claude | yes | the rollout's state |
| 11 | The Pro **Android** `updateUrl` in the admin console, once the store page is public (as B0.5 did for iOS) | the owner | — | `GET /client-version?…platform=android&build=-1` read back |

**Earliest production:** about three weeks after step 8, which is 14 days of
testing plus Google's two reviews. LAUNCH §3 also asks that iOS be live and
stable for a week first. iOS was released on 2026-11-10, so that condition is
met before the test can end.

## 5. The device pass (step 6)

The build that testers get is signed by **Play**, not by the upload key, and
is minified by R8. So the pass runs on a build installed **from Play** (the
internal track), never on a sideloaded APK. Each line says how it is
observed. A line nobody could observe stays UNVERIFIED in the outcome (§11).

| # | Check | Observed by |
|---|---|---|
| 1 | Cold start reaches « Espace Pro » with no crash | screen; no new Sentry issue for `com.myweli.pro@0.0.2+N` |
| 2 | E-mail code sign-in on a real salon account | the server log: the code-verify request answered 200 with the **Dart** user agent |
| 3 | « Continuer avec Google » | `/auth/google` 200 with the Dart user agent (the 2026-08-26 oracle; a web sign-in gives `node`) |
| 4 | Notifications: the system prompt appears once (Android 13+, after B13.3), the token is registered, a push arrives in the background and in the foreground, a tap opens its screen | the screen, plus the device-token row or its request in the server log |
| 5 | The map tiles show streets, not « API KEY REQUIRED » | screen |
| 6 | « Utiliser ma position » in « Profil du salon »: the permission prompt; the « approximate only » choice; denial | screen |
| 7 | A gallery photo upload; a KYC PDF (`file_picker`) | the object in R2, read by size |
| 8 | Kill and reopen: still signed in; « Se déconnecter » really signs out | screen |
| 9 | External links (support, privacy) open in the browser | screen |
| 10 | The reference device: Android 9, 2–3 GB of RAM (ROADMAP Part 6). Cold start over 5 runs (`adb shell am start -W`, budget p95 < 3.5 s), the journal scroll (`adb shell dumpsys gfxinfo`, janky frames), no crash after 10 minutes of use | the commands' output |

**UNVERIFIED today:** whether the owner has an Android 9 device with 2–3 GB of
RAM (open question O2). If they have none, line 10 runs on the oldest device
they have, and LAUNCH §6.3's box stays open with the gap named.

## 6. R8, Sentry and Play — the mapping file

- **Dart frames** are already covered: `--obfuscate --split-debug-info`, and
  `release_build.sh` prints the `sentry-cli debug-files upload` command.
- **Java and Kotlin frames** (a plugin, the engine's Java side) are minified
  by R8. Sentry reads them only with the mapping file, and only if the app
  tells Sentry which mapping it was built with.
  - **Sentry's own pages** (read 2026-11-11): the Flutter page sends R8 users
    to the Sentry Android Gradle Plugin, « Alternatively, you can use the
    Sentry CLI ». The manual route puts a UUID in the manifest as
    `<meta-data android:name="io.sentry.proguard-uuid" …/>` and uploads with
    `sentry-cli upload-proguard --uuid <uuid> <mapping.txt>`.
  - **Recommended: the manual route.** `release_build.sh` makes one UUID per
    build and passes it to Gradle as a manifest placeholder. It then prints
    the upload command, as it already does for the symbols. The script never
    holds the Sentry token, and the Gradle plugin would need it at build time.
  - **UNVERIFIED:** whether `sentry_flutter`'s Android side reads that
    manifest key without the Gradle plugin. Sentry's pages do not say.
    Checked at step 6 by reading one event's `debug_meta` in Sentry. If it is
    absent, the Gradle plugin is the fallback, in its own PR.
- **Play** deobfuscates crashes and ANRs in Android vitals with the same file.
  Step 5 checks whether the AAB carries it under `BUNDLE-METADATA`. If it does
  not, the file is uploaded in the console on the release page.
- **The R8 PR** (step 3) writes `isMinifyEnabled = true` explicitly, replaces
  the false comment, adds the UUID placeholder, and prints the mapping upload
  from `release_build.sh`. Its guard is in §9.

## 7. The two Play declarations

### 7.1 Precise location — due 2027-01-27

- **Google's text** ([policy announcement of 2026-10-29](https://support.google.com/googleplay/android-developer/answer/18100766?hl=en),
  read 2026-11-11): the policy « will become mandatory on January 27, 2027 ».
  Apps using `ACCESS_FINE_LOCATION` « must complete a Play Console
  declaration to justify why coarse location or the location button is
  insufficient ». From target SDK 37, a one-time, user-initiated need must use
  the Android location button.
- **Us:** target 36, so the button rule does not apply yet; the declaration
  does.
  - The Pro app asks for location in one place: « Utiliser ma position » in
    « Profil du salon » (`pro_salon_profile_screen.dart`, `Geolocator`). It is
    a one-time action the user starts.
  - The point it gets is published as the salon's position on its public page
    and map (play-store-forms §4).
- **The justification to type:** a coarse position is off by kilometres, and
  would put a business on the wrong street of its public map. The location
  button exists only from Android 17.
- **UNVERIFIED:** where the form sits in the console, what it asks, whether
  it is open yet, and whether it gates the closed test. Step 7 reads it before
  anything is typed. The answer is then written into play-store-forms §5.
- **Later, with the client app:** both flavours share `main/AndroidManifest.xml`.
  The client app's « Près de moi » chooses a commune on the device, so it
  needs only a coarse position. Moving `ACCESS_FINE_LOCATION` to the Pro
  flavour would spare the client app this declaration.

### 7.2 Trader status — due 2027-02-01

- **Google's text** (answer 17594752): « all active developer accounts must
  declare ». It applies regardless of where apps are distributed. Without it:
  « app update blocks and removal from the Play Store globally ».
- **Where:**
  - the account: « Manage account » → « Account details » → « About you »;
  - then each app: « Monitor and improve » → « Policy and programs » →
    « App content ».
- **What is published:** §3.6. The owner confirmed « trader » with those
  facts on 2026-11-11.
- **UNVERIFIED:** whether it gates the closed test.

## 8. The closed test and production

- **The closed test** is play-store-forms §6, as corrected by this PR.
  The Play SHA-1 step there is done since 2026-08-26 and becomes a check:
  `release_build.sh` already runs `96-verify-google-identity.mjs`.
- **Promoting rather than rebuilding:** the build on the closed track is the
  same release that passed §5 on the internal track. Play offers « promote
  release »; a new upload would be a new, unchecked artifact.
- **Production access:** after 14 days with 12 testers. Google asks how the
  app was tested and what changed; the answers come from the feedback
  (support@myweli.com and Play's private feedback) and §11 of this spec.
- **Staged rollout (proposed, confirmed at step 10):**
  - 20 % for 48 hours, then 100 % if both hold: no new crash issue in Sentry
    for the release, and no ANR or crash rate flagged in Android vitals;
  - otherwise « Halt rollout », and the next build fixes it;
  - with the few users a new app has, the percentages mostly protect against a
    device-specific crash; that is why the rollout is short.

## 9. Testing — the guards this work adds or changes

- **This PR:** `play_store_forms_test.dart`, « the full description is the App
  Store one ». It no longer admits the four edits of 2026-11-03, so Play must
  equal the App Store **word for word** (decision 113). Watched red: the four
  old phrasings put back one at a time, each fails. The doc comment's
  paragraph 1 says so.
- **The R8 PR** (step 3): a test reads `app/build.gradle.kts`, comments
  stripped, and requires `isMinifyEnabled = true` in the release block and the
  proguard UUID placeholder. It also reads `release_build.sh`, prose and
  `echo` lines stripped, and requires the mapping path in the printed upload
  command. Each assertion is watched red by deleting its line.
- **On the artifact** (step 5, not a test): the TLS gate (#759), the R8
  marker, the permission list. A unit test cannot see a build that has not
  happened.

## 10. Security

- **The keystore and its passwords never enter the chat or the repo.** For
  the backup the owner types a folder or a medium in plain text, never
  attaches the file with « @ », which would read it into the chat. Hashes are
  the only output.
- `key.properties` holds the passwords in clear, at mode `644`. That would let
  another account on the Mac read it, but there is none: the only account
  with a UID of 500 or more is the owner's (`dscl`, 2026-11-11). So the owner
  chose to leave it at `644`. Adding an account reopens this.
- The Drive copy of the keystore is encrypted under the store password, and
  the passwords live with a different provider, Apple Passwords. Someone who
  got into the Google account would also need the Apple account. If that
  Google account is the one that owns the Play Console, they could already
  request an upload key reset there, so the copy gives them nothing new. Two
  rules: the file is never shared, and no password is stored in Drive.
- The demo code stays in Secret Manager (play-store-forms §2). It serves both
  stores, so a rotation updates both consoles the same day.
- Testers' e-mail addresses live in the Google Group, never in the repo.
- The trader declaration publishes the owner's personal phone number and
  address (§3.6). That was their decision to make, and they made it with the
  right facts on 2026-11-11.

## 11. Open questions and outcome

| # | Question | Who | State |
|---|---|---|---|
| O1 | Where is the upload key's backup? | the owner | **answered 2026-11-11: « I don't remember ».** Observed that day: Spotlight finds one copy, `~/myweli-upload.jks` (2,761 bytes, created 2026-08-26 01:25, mode `644`), the file `key.properties` points to; Time Machine has no destination. A USB drive, a password manager or an e-mail would not show here, so it is **treated as no backup** and step 4 makes one. Losing it would **not** end the listing: Google holds the app signing key, and a lost upload key is replaced by an « upload key reset » ([answer 9842756](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en), read 2026-11-11: « you are not locked out of your app »). Google states no delay. Until the reset, no update ships, for either app: one key signs both apps' uploads (signing-manifest.json). **The backup was made the same day** (§4, step 4): the file is on the owner's Google Drive, and its download proved byte-identical; the passwords are in Apple Passwords, and the owner's check found they match `key.properties`. **Closed.** |
| O2 | Is there an Android 9 phone with 2–3 GB of RAM? Otherwise, which is the oldest? | the owner | **answered 2026-11-11: « an old Samsung ».** Model, Android version and RAM not known yet: read at step 6 with `adb` (`ro.product.model`, `ro.build.version.release`, `/proc/meminfo`) or by the owner in Settings › About phone. It must run Android 7.0 (API 24, the app's `minSdk`) or later, or Play will not offer the app on it |
| O3 | Trader, with phone and address shown everywhere (§3.6): still « trader »? | the owner | **answered 2026-11-11: « Rester professionnel »** |
| O4 | The location form: where it is, what it asks, whether it gates testing | read at step 7 | open |
| O5 | Does `sentry_flutter` read `io.sentry.proguard-uuid` without the Gradle plugin? | step 6 | open |
| O6 | The rollout: 20 % for 48 h, then 100 %? | the owner, at step 10 | proposed |

**Outcome log.** Each step adds a dated line here when it ends, with what was
observed.

- **2026-11-11, step 4 (the file).** The owner uploaded the key to Google
  Drive, and the download back reached `~/Downloads` at 21:43. Its SHA-256
  equals the original's (`3aee730f…0be0e3`) and `cmp` exited 0. As a control,
  `cmp` on two files that differ exited 1. The download was moved to the
  Trash. The original is unchanged: 2,761 bytes, modified 2026-08-26 01:25:33.
- **2026-11-11, step 4 (the passwords). Step 4 is done.** The owner's `getpass`
  check reported both passwords as « matches ». `keytool` with
  `key.properties`' passwords opened the keystore and unlocked the `upload` key
  (created 2026-08-26). As a control, a wrong password was refused.
- **2026-11-12, step 1. Done.** #758 was merged on 2026-11-11 (`0d982e4e`).
  #759 was rebased onto `main` and merged on 2026-11-12 (`f0708559`). Its
  BACKLOG item became B13.10, because #758 had given B13.9 to
  `add_2_calendar`. Each merge's `main` tree equals the PR head CI tested.
  The gate then ran on #763's APK: Dart 3.13.7, blocklist 8/8.

