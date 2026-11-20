# MyWeli Pro on Google Play — the first Android release

| | |
|---|---|
| **Module** | release (mobile, Pro flavour `com.myweli.pro`; Play Console) |
| **Status** | **Approved 2026-11-11** — the owner's « Valider tel quel » on the plan and on decisions 110–115 ([BACKLOG](../BACKLOG.md)). Decision 115's cost was understated when asked; told the corrected facts, the owner confirmed « Rester professionnel » the same day (§3.6). Nothing built, nothing typed in the console yet. **Amended 2026-11-13** for decisions 134 and 135 and for the findings of a read-only audit of the path to Play: the order inside step 3, a step 3a, preconditions and reads at steps 5–8, step 11's iOS neighbour, §2, §5 row 3 and a row 17, §6, §9, O5 and O7. Two of the audit's proposals are **not** decisions: the owner has not answered them yet (O8 « Publication gérée » at step 8, O9 the `/client-version` read at step 5). *(2026-11-18: O9 answered, « Yes, as recommended »; O8 still open.)* *(2026-11-19: step 7's forms are typed and read back, the trader declaration included (decisions 149 and 150); the location declaration has no form in the console yet.)* *(2026-11-20: step 8 is done. The closed test is live with build 788, sent to review and published on 2026-11-19; step 9, the 14 days, runs.)* *(2026-11-20: build 794, which declares the portrait feature optional, built from `c4bf8c63`, read, and published to the internal track; Play counts 27 more devices than 788 and none fewer; rows 1 and 2 passed on it. O7 is answered. The closed track still serves 788.)* |
| **Last updated** | 2026-11-20 (step 10: decision 152's description is typed before production, #819). Also 2026-11-20 (build 794, O10's new AAB: steps 5 and 6, rows 1 and 2, O7 answered, an emulator's event on 788; §6, §8, O7, O10 and §11's outcome log). Also 2026-11-20 (step 8: the closed track set up, 788 promoted, sent to review and published; decision 151; §11's outcome log). Also 2026-11-19 (step 7: the console forms typed and read back, the trader declaration for the account and both apps, decisions 149 and 150; §3.6, §7.1, §7.2, §10, O4, §11's outcome log). Also 2026-11-19 (step 3a: PR C merged in #812, so step 3a is done; §11's outcome log). Also 2026-11-19 (PR C of step 3a: §1, step 7's help pages, step 9, §5's rows 11–16 and the iPhone side). Also 2026-11-19 (steps 5 and 6 recorded for builds 785 and 788: the AAB, the internal track, the device pass on 788; step 3a's PR B merged; O7 and O9; §11's outcome log). Before that, 2026-11-18 (step 6: the device pass stopped at sign-in on Orange fibre, see [android-http3-transport.md](android-http3-transport.md)); also 2026-11-18 (step 3 (e): the R8 PR built, §6, §11; step 3a: PR A built, then merged in #806, and PR B built). Before that, 2026-11-17 (step 3: (b) merged, the hold (c) over, (d) built), and before that, 2026-11-14 (step 3: (a) merged, (b) built), and 2026-11-13 (decisions 134–135 and the audit's findings: §2, §4, §5, §6, §9, §11, the outcome log) |
| **BACKLOG items** | B0.10 (the Play forms and the closed test), B13.1 (#758), B13.3 (firebase), B13.10 (#759) |
| **PRD ref / phase** | V1 · NFR-PERF-002 (APK < 30 MB) · ROADMAP Part 6 (the reference low-end Android) |
| **ROADMAP entry** | added when the production release ships (`docs/roadmap/entries/`) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [play-store-forms.md](play-store-forms.md) (every answer typed in the console) · [LAUNCH.md](../LAUNCH.md) §6.3 · [mobile-flutter-3.47-upgrade.md](mobile-flutter-3.47-upgrade.md) · `android-tls-artifact-gate.md` (arrives with #759) · [mobile-store-submission.md](mobile-store-submission.md) §2 · [mobile-external-testing.md](mobile-external-testing.md) · [client-version-gate.md](client-version-gate.md) |

How to read it: **observed** means read or run here on 2026-11-11, with where
(in a note dated 2026-11-13, read or run by that day's audit).
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
  (§6). Each is its own PR. *(2026-11-19: no longer true. Step 3a added one
  feature to this release, the Android sign-up (B0.17,
  [pro-android-signup.md](pro-android-signup.md)), merged in #806 and #807;
  its rows are 11–16 of §5.)*

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
    Dart user agent). *Corrected 2026-11-13:* `/auth/google` is the **client**
    app's endpoint (`api_auth_service.dart:271`); the Pro app calls
    `/auth/provider/google` (`api_auth_service.dart:526`). The 2026-08-26
    oracle covered both apps: `/auth/google` 200 **and**
    `/auth/provider/google` 404 (`provider_not_found`, the Pro app being
    sign-in only), both with the Dart user agent
    ([roadmap entry](../roadmap/entries/2026-08-26-true-play-delivery-shas.md)).
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
  step 5 reads it on the real artifact. *(2026-11-18: the comment replaced, and
  both settings written in release, by the R8 PR, step 3 (e).)*
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

*2026-11-19, declared (play-store-forms §0.4).* The console's phone screen
showed what the profile publishes: the trader status, the developer email,
the phone, the legal name and the address. The email was not part of the
cost put to the owner on 2026-11-11, and it was their personal address.
Asked that day, the owner switched it to `support@myweli.com` before
declaring (decision 149). The phone and the address are published as decided.
The account is « Professionnel », and both apps confirm it (decision 150).

## 4. The order

Each step names who acts and what it leaves behind as evidence. « Yes » means
the owner's explicit word at that moment: green CI or a ready artifact is
never a go-ahead for a console action.

| # | Step | Who | Gate | Evidence it leaves |
|---|---|---|---|---|
| 0 | This spec, and the docs PR that corrects what is out of date | Claude | the owner's review | this PR |
| 1 | Merge #758 (Flutter 3.47.9); then #759 (the TLS artifact gate), rebased | the owner merges; #759 belongs to its own session | yes | squash tree == PR tree |
| 2 | B13.3: firebase_messaging 16.7.x, its own PR from `main`, lockfile regenerated on 3.47.9 | Claude | merge | the Android 13+ « never asked = denied » branch tested |
| 3 | `version: 0.0.2+1` in `pubspec.yaml` (decision 111); the R8 PR (§6). **2026-11-13 (decisions 134, 135), the order inside this step:** (a) B0.18's Pro-app PR ([salon-go-live-approval.md](salon-go-live-approval.md) §9.1 item 3), so the iOS 0.0.2 IPA knows publish's 202 and the 409 `validation_refused_final`; (b) the bump, alone; (c) **a merge hold** from the bump's merge until the iOS 0.0.2 IPA is built: `release_build.sh` builds `origin/main`'s head only (`tool/release_build.sh:56-67`), so anything merged in between ships in iOS 0.0.2 (no PR was open on 2026-11-13); (d) the iOS 0.0.2 IPA, `./tool/release_build.sh ios pro` in the main checkout after `git pull --ff-only` (as step 5), decision 119 unchanged; its upload waits for the owner's yes and for Apple's two new age-rating answers (BACKLOG, decision 108); (e) the R8 (shrinker) PR (§6, decision 135), after the IPA so that its Dart change stays out of iOS 0.0.2, and before step 3a's PR A, whose P9 reuses the `flutter` stub's argument log it adds. **Fallback the owner accepted:** if (a) stalls, (b) ships alone first and (a) follows, still before step 5. *(2026-11-14:)* (a) merged in #792 (`a3f90348`), so the fallback is not needed; (b) built on `chore/version-0.0.2`, not merged: `pubspec.yaml`'s `0.0.1+1` → `0.0.2+1` and nothing else, the `+1` kept for `release_build.sh` and its test. The merge hold (c) starts at its merge. *(2026-11-14, evening:)* (b) merged in #797 (`29daa5ed`, 19:07 UTC); (d) built from that commit as build 781, validated and read at app-store-forms §11.3 (recorded in §11.5), so the hold (c) ended about 19:15 UTC with nothing merged in between. Not uploaded: that waits for the owner's yes. (e) is next. *(2026-11-18:)* (e) built on `chore/r8-proguard-uuid`, then merged in #805 (`a866bf08`, 2026-11-18); its real-artifact checks are step 5's (§6, O7). | Claude; the owner merges | merge; the IPA built on the owner's go | the guards of §9; the IPA's app-store-forms §11.3 read |
| 3a | *Added 2026-11-13.* B0.17, the Android sign-up ([pro-android-signup.md](pro-android-signup.md) §9.1), in **three PRs**: **A** the fence (null extensions, no behaviour change), after the R8 PR; **B** the service, provider and mock methods, the screens, the copy and the goldens; **C** the documents and the Play texts, after B0.18's button rename and B0.19's URL. A and B merge before step 5; C before step 7 *(2026-11-18:)* **A merged** in #806 (`d0b2c85a`); **B built** on `feat/pro-android-signup`, then **merged** in #807 (`1854bfc5`, the same day); C is left, before step 7 (pro-android-signup §12) *(2026-11-19:)* **C merged** in #812 (`b275edcd`); step 3a is done | Claude; the owner merges | merge | pro-android-signup §8's guards; the iOS strings read at the first iOS build that carries A (decision 119) |
| 4 | The upload key's backup: none was known (§11, O1), so the owner made one on 2026-11-11. **The file:** `~/myweli-upload.jks` is on the owner's Google Drive. It was downloaded back to this Mac and compared with the original: equal SHA-256 (`3aee730f…0be0e3`) and `cmp` 0. The download then went to the Trash. Because the copy is byte-identical, it opens wherever the original does, so `keytool -list` on it would prove nothing more. **The passwords:** in Apple Passwords, which iCloud Keychain syncs off this Mac (sync observed on). The owner compared the saved passwords with the ones `key.properties` holds, using a `getpass` comparison in their own terminal that prints only « matches » or « is DIFFERENT ». They reported **both « matches »** (that terminal's output is not visible here). Then, on this Mac: `key.properties`' store password opens the keystore, and it unlocks the private key under alias `upload`. `keytool -list` and `-certreq` both exit 0, with the passwords passed through the environment and nothing printed; as a control, a wrong password exits 1. The key password equals the store password, which PKCS12 requires. `chmod 600 key.properties`: dropped by the owner, because this Mac has one account (§10) | the owner, with Claude | — | **done 2026-11-11:** two equal hashes; both passwords « matches »; `keytool` opens the key with them |
| 5 | The AAB from `main`, in the main checkout: `./tool/release_build.sh android pro`. Then on the artifact: the TLS gate (#759), the R8 marker, `BUNDLE-METADATA/…/proguard.map` present or not, permissions with `aapt2`/`bundletool`, size; Sentry: Dart symbols + the mapping (§6). **Added 2026-11-13:** (a) first, on the owner's go, `git pull --ff-only` in the main checkout: on 2026-11-13 it was 14 commits behind `origin/main` (`f36963a9` against `d19655bd`), a state the script refuses (`tool/release_build.sh:62-66`); (b) the 16 KB page size, Google's rule for apps targeting Android 15 and up (its page not re-read here: UNVERIFIED): `bundletool build-apks`, then `zipalign -c -P 16 -v 4` on the arm64 split, or an ELF read of `libapp.so`'s LOAD alignment. The audit read the engine's `libflutter.so` at 65536 and sentry-native's libraries at 16384 in local caches; `libapp.so` was not read; (c) the mapping **inside** the AAB, at `BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map`: AGP 8.11.1 adds it whenever a mapping exists (OBSERVED in AGP's bytecode; no AAB read yet); (d) *an audit proposal (Q-L) the owner has not answered yet (O9):* before the upload, a read of `GET /client-version?app=com.myweli.pro&platform=android&build=<N>`, `<N>` the AAB's build number, so that a floor set earlier does not block it. It must answer `ok` (or `update_available`), never `update_required`. `app` is the package name, as the app sends it (`client_version_gate.dart:125`): an unknown value such as `pro` finds no floor row and answers `ok` whatever the floor (`client_version_service.dart:55-56`), so it would prove nothing. A production read, on the owner's go. Play may warn that native code has no debug symbols: expected, not a failure (INFERRED). *2026-11-18: done twice, each on the owner's yes: build 785 from `1854bfc5`, then build 788 from `e8ec333c`, which carries the « Pas de connexion » fix. Every read above passed both times, and (d) answered `ok` (§11, O9 and the outcome log). Play gave no warning about native symbols.* *Added 2026-11-19:* (e) Play's device filter, on an APK from the AAB (`bundletool build-apks --mode=universal`): `tool/verify_android_portrait_optional.sh <apk>` prints `OK`, meaning the badging names `android.hardware.screen.portrait` once, as `uses-feature-not-required`. CI runs the same script on every PR, on the consumer release APK (§9). After the upload, Play's device counts (phones, tablets, Chromebook, XR) are read against 788's (§11, 2026-11-19). *2026-11-20: done a third time, for build 794 from `c4bf8c63`, on the owner's « build the next AAB with the tablet fix »: every read passed, (d) answered `ok`, and (e) printed `OK`, while the same script refuses 788's APK (§11).* | Claude, on the owner's yes | yes | the script's lines, the reads |
| 6 | Upload to the **internal** track, roll out to the owner; the device pass of §5 on the owner's phone and on the reference device | Claude in the browser pane (the owner signed in); the owner holds the phones. *Corrected 2026-11-13:* the built-in pane cannot attach files (play-store-forms §0.1: « le volet navigateur ne peut pas joindre de fichier »), so the AAB upload is done in the owner's Chrome (Claude in Chrome) on their yes, or by the owner | yes for the upload | §5's table filled in. *2026-11-18: build 785 was published to the internal track and installed from Play; the pass stopped at sign-in, « Pas de connexion. Réessayez. » over the owner's Orange CI fibre Wi-Fi. Cause and fix: [android-http3-transport.md](android-http3-transport.md), approved and built the same day. The pass resumes on the first AAB that carries that fix.* *2026-11-18, evening: build 788 carries it. Published to the internal track and installed from Play on the Galaxy; over the same Wi-Fi, rows 1, 2, 5 to 9, 18 and 19 passed, on 2026-11-18 and 19. Rows 3, 10, 11–16, 21 and 22 are not run yet, nor row 4's push; rows 17 and 20 wait for a first Sentry event (§11's outcome log).* *2026-11-20: build 794 (O10). The owner put the AAB into the release in the built-in pane, from Finder, so the pane takes a file the owner gives it; Claude's tools still cannot attach one. Saved and published on the owner's yes; Play counts 27 more devices than 788 and none fewer; rows 1 and 2 passed on the Galaxy. Row 20 is observed on 788, on an event from Google's test emulator (§11).* |
| 7 | Re-read the Play dashboard (last read 2026-10-28). Type the listing text (decision 113). Fill in the location declaration (§7.1) and the trader declaration (§3.6, « trader », confirmed 2026-11-11). *Precondition added 2026-11-13:* B0.19's Pro deletion page live, and its URL typed in Data safety as the deletion URL; step 3a's PR C merged, so play-store-forms holds the texts to type. *Added 2026-11-13 (decision 137, [web-pro-account-deletion.md](web-pro-account-deletion.md) §11):* before that page merges, B0.22 (the map pin and replaced KYC documents erased) deployed and read back, with O2 settled, and B0.23 (the privacy policy's correction) merged and read live (that merge's other conditions are in its §11); the Data safety preview read beside the corrected policy and the page. *(2026-11-13, decisions 141–143:)* also B0.25's server half ([admin-pro-account-erase.md](admin-pro-account-erase.md)) deployed and read back, and its procedure approved, before B0.23; and B0.22's O1 settled beside O2. *(2026-11-14, met:)* ✅ B0.22 merged (#791) and deployed with B0.25's server half (#793), revision `myweli-api-00052-94d`, both read back; ✅ O1 = 0 and O2 = 0; ✅ the procedure approved (decision 148); ✅ B0.23 merged (#794) and read live; ✅ B0.19's page merged (#795) and read live at `https://myweli.com/pro/suppression-compte`. **Still open for this step:** step 3a's PR C, the URL typed in Data safety, and the preview read beside the policy and the page. *Added 2026-11-19 (pro-android-signup §6.2, §9.4):* before the texts are typed, the owner re-reads in a browser the two Play help pages the sign-up leans on, the Payments policy (9858738, §4) and help 10281818; they were read here through a summarizing fetch on 2026-11-12. *(2026-11-19: PR C built, on `docs/pro-android-signup-pr-c`.)* *(2026-11-19, done except the location declaration, which has no form in the console yet: the description, the sign-in text, Data safety's four changes and the trader declaration, each on the owner's yes and read back after a reload; nothing sent for review. play-store-forms §0.4, §11's outcome log.)* | Claude in the pane; the owner signed in | yes for each form | each form read back after saving |
| 8 | The Google Group; the closed track (countries, decision 114; testers = the group); **promote the same release** from internal to closed; send it to Google's review. *Added 2026-11-13:* precondition, B0.18's admin console and backend deployed, with a 202 read back: **done 2026-11-13** (salon-go-live-approval's status line; its §9.2 item 5 sets the precondition); the group is Testers Community's and the countries every available one (decision 117). *An audit proposal (Q-I) the owner has not answered yet (O8):* after Google approves the closed release, and before step 10, « Publication gérée » turned **on** (off when last read, 2026-10-28, play-store-forms §0.1), on the owner's yes, so that production goes out on their click. *Added 2026-11-13 (decision 140):* from the release sent to Google's review until Google's decision, `/pro/suppression-compte` is frozen, as the five pages are during Apple's reviews. *(2026-11-19 and 20, done, each action on the owner's yes: 178 countries and regions; testers = Testers Community's group; feedback to `support@myweli.com`; 788 promoted; Play's portrait check dismissed (decision 151); 16 changes sent; published the same evening, read back 2026-11-20. O8 still open. play-store-forms §0.5, §11's outcome log.)* | the owner and Claude | yes | the track's state read back |
| 9 | The test salon, the invitations, play-store-forms §6.3–§6.5; 12 testers opted in for 14 days in a row. *Corrected 2026-11-19 (decisions 116, 117):* testers create their salon in the app themselves (play-store-forms §6.5, in French and in English); the test salon for friends and family is optional, and paid testers' salons are refused at validation, never published | the owner | — | the console's tester count, day by day |
| 10 | Apply for production access (Google usually answers in 7 days or less), then production at a staged rollout (§8). *Added 2026-11-13 (decision 138):* before applying, B0.24 decides a purge of a deleted owner's salon history (BACKLOG); once one is built, the deletion page, the policy and Data safety change in text PRs. *2026-11-20: decided, decisions 153–158 ([deleted-owner-salon-purge.md](deleted-owner-salon-purge.md)); this condition is met. The purge is built and switched on later, each step on the owner's yes, and the three texts change only once it runs.* *Added 2026-11-19:* precondition, the AAB that goes to production declares `android.hardware.screen.portrait` optional (§11, 2026-11-19), read at step 5 (e). Build 788, on the closed track, does not, so production is a new AAB from a `main` that holds the fix, not 788 promoted (§8, O10). *2026-11-20: build 794 meets it, read at step 5 (e) and in Play's device counts (§11); it is on the internal track.* *Added 2026-11-20 (decision 152, #819):* before production, type [play-store-forms.md](play-store-forms.md) §1's description, with its « POUR VOTRE MÉTIER » block (1,289 characters), in the console on the owner's yes, and read it back after a reload. The console still holds step 7's text (1,100 characters). | the owner and Claude | yes | the rollout's state |
| 11 | The Pro **Android** `updateUrl` in the admin console, once the store page is public (as B0.5 did for iOS). *Its iOS neighbour (decision 134, 2026-11-13):* once an iOS 0.0.2 that carries B0.18's app is live on the App Store, the owner raises the iOS floor (the admin console's client-version minimum for iOS), which ends decision 131's residual (salon-go-live-approval §9.2, item 6). No slot is set for it yet | the owner | — | `GET /client-version?…platform=android&build=-1` read back |

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
| 2 | E-mail code sign-in on a real salon account | the server log: the code-verify request answered 200 with the **app's** user agent, `MyWeli/0.0.2+N (com.myweli.pro; Android)`. *Corrected 2026-11-18:* this said the Dart user agent, which the Android app no longer sends since it talks through Cronet ([android-http3-transport.md](android-http3-transport.md) §4.1); with the fallback of that spec it is still Dart's |
| 3 | « Continuer avec Google », on an existing salon account | `/auth/provider/google` 200 with the app's user agent (row 2); a web sign-in gives `node`. *Corrected 2026-11-13:* this row said `/auth/google`, the client app's endpoint, which the Pro app never calls (`api_auth_service.dart:526`; §2) |
| 4 | Notifications: the system prompt appears once (Android 13+, after B13.3), the token is registered, a push arrives in the background and in the foreground, a tap opens its screen | the screen, plus the device-token row or its request in the server log |
| 5 | The map tiles show streets, not « API KEY REQUIRED » | screen |
| 6 | « Utiliser ma position » in « Profil du salon »: the permission prompt; the « approximate only » choice; denial | screen |
| 7 | A gallery photo upload; a KYC PDF (`file_picker`) | the object in R2, read by size |
| 8 | Kill and reopen: still signed in; « Se déconnecter » really signs out | screen |
| 9 | External links (support, privacy) open in the browser | screen |
| 10 | The reference device: Android 9, 2–3 GB of RAM (ROADMAP Part 6). Cold start over 5 runs (`adb shell am start -W`, budget p95 < 3.5 s), the journal scroll (`adb shell dumpsys gfxinfo`, janky frames), no crash after 10 minutes of use | the commands' output |
| 17 | *Added 2026-11-13.* The R8 (shrinker) mapping reaches Sentry at run time: one Java/Kotlin event of this build whose `debug_meta` carries `{type: proguard, uuid: <U>}`, `<U>` the UUID `release_build.sh` printed for this AAB (§6, decision 135). It is the only runtime proof of the carrier; §6's chain is read from the code. Which event serves (an ANR, a plugin's Java exception) is chosen at step 6: none may happen on its own (UNVERIFIED) | the event's JSON in Sentry |

*Rows 18–22 added 2026-11-18* by [android-http3-transport.md](android-http3-transport.md) §7, the « Pas de connexion » fix. Its trust list for our domains is §5.2 there.

| # | Check | Observed by |
|---|---|---|
| 18 | On the owner's Orange CI fibre Wi-Fi, the network of « Pas de connexion »: the first screen loads; sign-in with `revue@myweli.test`; the dashboard and its photos; the map's tiles | screen; the server log shows the app's user agent (row 2) |
| 19 | On the same Wi-Fi, one gallery photo upload on the review salon: a production write, asked first | the object in R2, read by size |
| 20 | A Sentry test event carries `net.transport=cronet` | the event's tags in Sentry |
| 21 | Row 18 again on mobile data, where a phone has a data SIM, and on the old Samsung, whose Android version decides how much the trust list matters there | screen |
| 22 | An iPhone smoke pass: only Sentry moved on iOS | screen; one Sentry event from the iPhone |

*2026-11-19: the first pass, on build 788, is in §11's outcome log, row by row.*

**Rows 11–16** are the Android sign-up's ([pro-android-signup.md](pro-android-signup.md)
§8.4): a Google sign-up, an e-mail sign-up, an address that already has an
account, no Apple button, the fresh account's checklist and « Mon abonnement »,
and its deletion. They join this table with step 3a's PR C; row 17 is numbered
after them so that none moves. *Joined 2026-11-19.* They create real production
rows, so the owner names the test addresses before the pass. The user agent is
the app's own since the « Pas de connexion » fix (row 2): the sign-up spec said
Dart's.

| # | Check | Observed by |
|---|---|---|
| 11 | Google sign-up, fresh account | the server log: `/auth/provider/google` 404, then `/auth/provider/register` 201, with the app's user agent (row 2); « Accueil » |
| 12 | E-mail sign-up from the code already received at sign-in, then one from « Créer le compte de mon salon » | verify 404, register 201, the app's user agent |
| 13 | Sign-up with an address that already has an account | it signs in; no new salon |
| 14 | No Apple button anywhere in the sign-up | screen |
| 15 | The fresh account: « Configurer mon profil » opens the checklist; « Mon abonnement » says « Pas encore d’offre active » | screen |
| 16 | Delete that fresh account end to end | Profil → « Supprimer mon compte »; the next sign-in answers `provider_not_found` |

**The iPhone side of the sign-up** (pro-android-signup §8.4), on TestFlight,
for the first iOS build that carries #806 and #807 (build 781 predates them):
a cold start; Google, Apple and e-mail sign-in; the `provider_not_found` dead
end unchanged, with no sign-up offered; an invitation accepted from the
sign-in; a notification tap from a cold start; sign-out. Row 22 runs on the
same build.

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
  - *Approved 2026-11-11, superseded 2026-11-13 by decision 135 (below), kept
    as the record:*
    - ~~**Recommended: the manual route.** `release_build.sh` makes one UUID
      per build and passes it to Gradle as a manifest placeholder. It then
      prints the upload command, as it already does for the symbols. The
      script never holds the Sentry token, and the Gradle plugin would need it
      at build time.~~
    - ~~**UNVERIFIED:** whether `sentry_flutter`'s Android side reads that
      manifest key without the Gradle plugin. Sentry's pages do not say.
      Checked at step 6 by reading one event's `debug_meta` in Sentry. If it
      is absent, the Gradle plugin is the fallback, in its own PR.~~ Answered
      2026-11-13 from the code (O5): read, then erased.
  - **The manifest route does not work here** (O5, answered 2026-11-13 from
    the code; the runtime proof is §5 row 17). sentry-android 8.51.0 does read
    the manifest key (`ManifestMetadataReader.applyMetadata`). Then
    sentry_flutter 9.26.0's native init runs its options callback, which
    calls, unconditionally,
    `androidOptions.setProguardUuid(options.proguardUuid?…)`
    (`sentry_native_java_init.dart:218-219`). This app never sets
    `proguardUuid`, so the value becomes `null` and the manifest's UUID is
    erased. Only the asset `sentry-debug-meta.properties`, which the Sentry
    Gradle plugin writes, fills a `null` back afterwards, and this app has no
    such plugin. So Java and Kotlin events would carry no proguard image.
  - **Decided 2026-11-13 (decision 135, « Build setting »): the Dart option
    carries the UUID.** It is the very value line 219 copies. *Re-read
    2026-11-18 for sentry_flutter 10.5.0
    ([android-http3-transport.md](android-http3-transport.md) §4.6): the same
    unconditional call is now line 237, so the decision holds.*
    - `tool/release_build.sh`, **Android branch only**: one UUID per build;
      `--dart-define=SENTRY_PROGUARD_UUID=<uuid>` on the
      `flutter build appbundle` line, never in `COMMON`, which iOS shares; any
      earlier `mapping.txt` deleted before the build; a build that leaves no
      `mapping.txt` refused (the one in-script sign that R8 ran); then an
      Android-only printed block:
      `sentry-cli upload-proguard -o myweli -p myweli-app --uuid <uuid> mobile/build/app/outputs/mapping/proRelease/mapping.txt`,
      and a check that Sentry lists that UUID. The mapping's path is AGP's
      layout (INFERRED: no local build output to look at).
    - `mobile/lib/core/observability/error_reporting.dart`: `options.proguardUuid`
      set only when the define is not empty; otherwise it stays `null`, never
      `""`.
    - `app/build.gradle.kts`: `isMinifyEnabled = true` **and**
      `isShrinkResources = true` written in the release block. Flutter
      3.47.9's Gradle plugin sets both today (`FlutterPlugin.kt` 216–219).
      The app's `android { … }` block is evaluated after the plugin applies,
      so what is written there wins (INFERRED from Gradle's order): hence the
      guard also forbids `false`. The false comment is replaced.
    - What stays true: the script never holds the Sentry token; it prints the
      commands, as it already does for the symbols. The Gradle plugin would
      need the token at build time.
  - **A named risk.** In sentry-cli 3.8.0, the operator's CLI,
    `upload-proguard --help` lists no `--uuid`. The flag still parses (exit 0,
    against 2 for an unknown flag), but the binary calls it deprecated and
    asks for a UUID derived from the mapping's content. Two builds with no
    plugin change may give byte-identical mappings under two random UUIDs; if
    Sentry deduplicates by content, the second UUID may never be registered
    (UNVERIFIED, O7). The per-build check catches it. **The fallback** is the
    Sentry Gradle plugin, with a content-derived UUID, in its own PR.
    *(2026-11-20, answered by build 794: its `mapping.txt` is byte-identical
    to 788's, and sentry-cli printed « Nothing to upload, all files are on
    the server ». Sentry's debug-file list still shows 794's UUID as a
    ProGuard mapping, created at that upload, beside 788's. So Sentry does
    register it, and the fallback is not needed (O7).)*
- **Play** deobfuscates crashes and ANRs in Android vitals with the same file.
  Step 5 checks whether the AAB carries it under `BUNDLE-METADATA`. If it does
  not, the file is uploaded in the console on the release page. *(2026-11-13:
  AGP 8.11.1 adds it as
  `BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map` whenever
  a mapping exists, OBSERVED in its bytecode; step 5 reads the real AAB.)*
- ~~**The R8 PR** (step 3) writes `isMinifyEnabled = true` explicitly,
  replaces the false comment, adds the UUID placeholder, and prints the
  mapping upload from `release_build.sh`. Its guard is in §9.~~ *(Approved
  2026-11-11; the placeholder superseded 2026-11-13 by decision 135.)*
- **The R8 PR** (step 3) carries decision 135's design above, and the `flutter`
  stub's argument log in `release_build_test.dart`, which B0.17's PR A (P9)
  reuses. It merges **after** the iOS 0.0.2 IPA, so that iOS 0.0.2 carries
  none of it, and before step 3a's PR A. Its guard is in §9.
  *(2026-11-18: built on `chore/r8-proguard-uuid` as designed, with two
  choices the design left open: a build with no mapping has its AAB renamed
  `.refused`, like the TLS gate's; and `configureSentry` takes the UUID as an
  optional parameter defaulting to the define, so a test can see the wiring,
  which a run without the define cannot (absent and unwired both read
  `null`). O7 stays open until step 5's per-build check.)*

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
  *2026-11-19, read at step 7: no such form yet in MyWeli Pro's « Contenu de
  l'application », with build 788 on the internal track (play-store-forms
  §0.4). So it is not open there yet; where it will sit, what it will ask
  and whether it gates the closed test stay UNVERIFIED.*
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
- **Done 2026-11-19** (play-store-forms §0.4):
  - **the account:** « Professionnel », read back after a reload. No document
    was asked for;
  - **each app:** « Oui » and the terms `https://myweli.com/cgu`, for MyWeli
    Pro and MyWeli (decision 150). Each app's answer waits in its publishing
    overview, so it reaches Google with that app's first review request
    (step 8, for MyWeli Pro). Since it is done before step 8, the gating
    question above no longer matters.

## 8. The closed test and production

- **The closed test** is play-store-forms §6, as corrected by this PR.
  The Play SHA-1 step there is done since 2026-08-26 and becomes a check:
  `release_build.sh` already runs `96-verify-google-identity.mjs`.
- **Promoting rather than rebuilding:** the build on the closed track is the
  same release that passed §5 on the internal track. Play offers « promote
  release »; a new upload would be a new, unchecked artifact.
  *2026-11-19:* build 788 cannot go to production as it is. It lacks the
  portrait declaration, and the owner chose to fix that before production
  (§11). So production is a new AAB; how it is checked first is O10.
  *2026-11-20:* that AAB is build 794, published to the internal track and
  checked as O10 proposes (§11). The closed track still serves 788.
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
- ~~**The R8 PR** (step 3): a test reads `app/build.gradle.kts`, comments
  stripped, and requires `isMinifyEnabled = true` in the release block and the
  proguard UUID placeholder. It also reads `release_build.sh`, prose and
  `echo` lines stripped, and requires the mapping path in the printed upload
  command. Each assertion is watched red by deleting its line.~~ *(Approved
  2026-11-11; superseded 2026-11-13 by decision 135, below.)*
- **The R8 PR** (step 3; *rewritten 2026-11-13 for decision 135*, the
  manifest placeholder dropped):
  - **`build.gradle.kts`**, comments stripped, the `release { … }` block found
    inside `buildTypes`: `isMinifyEnabled = true` and `isShrinkResources = true`
    in **release**; no `isMinifyEnabled = false` anywhere; a commented line
    does not count. One assertion reads the **raw** file instead, since the
    stripped text never holds a comment: the old « deliberately NOT enabled »
    comment is gone.
  - **`release_build.sh`, run for real** in `release_build_test.dart`'s
    throwaway repo, the `flutter` stub now logging its arguments: `android pro`
    prints `upload-proguard`, `--uuid <U>` and the mapping path, and `<U>` is
    the `SENTRY_PROGUARD_UUID` the stub's `build appbundle` received; two runs
    give two UUIDs; no mapping → exit 1 and no upload printed; a mapping left
    by an earlier run is not accepted; `ios pro` prints no `upload-proguard`
    and passes no define; a TLS-refused AAB prints no `upload-proguard`; the
    define the script passes is the name `error_reporting.dart` reads.
  - **`error_reporting_test.dart`:** no define → `proguardUuid` is `null`, not
    `""`; a UUID given → that UUID.
  - Each assertion is watched red by its own mutation: deleting its line,
    writing `false`, moving the line to `debug`, commenting it out,
    hard-coding the UUID, removing the mapping check or its `rm`, putting the
    define into `COMMON`, moving the printed block above the TLS gate,
    renaming either side of the define.
- **On the artifact** (step 5, not a test): the TLS gate (#759), the R8
  marker, the permission list. A unit test cannot see a build that has not
  happened.
- **Play's device filter** (*2026-11-19*, the portrait declaration, §11):
  - **`android_orientation_test.dart`** reads the source manifest, with its
    comments stripped. It requires one `uses-feature` named
    `android.hardware.screen.portrait`, with `android:required="false"`,
    outside `<application>`; the lock and the single activity stay pinned.
  - **`tool/verify_android_portrait_optional.sh`** reads the **merged**
    manifest of a built APK with `aapt2 dump badging`. It passes only when
    the feature appears once, as `uses-feature-not-required`. CI's
    `apk-size` job runs it after the release build, so a plugin's manifest
    that brought the requirement back would fail the PR. The source pin
    cannot see that.
  - **`backend/test/infra/android_portrait_optional_test.dart`** runs the
    script on badging lines copied from real APKs (before and after the
    declaration), so its refusals run on every PR. It also pins CI's step:
    after the build, on the APK, no `if`, no `continue-on-error`, no
    `|| true`.
  - **Watched red:** 14 mutations, each confirmed to change its file:
    - the declaration deleted, `required="true"`, `required` dropped, moved
      inside `<application>`, commented out, and the lock removed;
    - in the script: the comparison always passing, the indent not stripped,
      the package-line check removed;
    - in CI: the step deleted, moved before the build, given `|| true` or
      `continue-on-error`, its `run` commented out.

    The script itself refused the before APK (exit 1) and accepted the after
    APK (exit 0).

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
  right facts on 2026-11-11. The email it publishes is `support@myweli.com`,
  not the owner's own (decision 149, 2026-11-19).

## 11. Open questions and outcome

| # | Question | Who | State |
|---|---|---|---|
| O1 | Where is the upload key's backup? | the owner | **answered 2026-11-11: « I don't remember ».** Observed that day: Spotlight finds one copy, `~/myweli-upload.jks` (2,761 bytes, created 2026-08-26 01:25, mode `644`), the file `key.properties` points to; Time Machine has no destination. A USB drive, a password manager or an e-mail would not show here, so it is **treated as no backup** and step 4 makes one. Losing it would **not** end the listing: Google holds the app signing key, and a lost upload key is replaced by an « upload key reset » ([answer 9842756](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en), read 2026-11-11: « you are not locked out of your app »). Google states no delay. Until the reset, no update ships, for either app: one key signs both apps' uploads (signing-manifest.json). **The backup was made the same day** (§4, step 4): the file is on the owner's Google Drive, and its download proved byte-identical; the passwords are in Apple Passwords, and the owner's check found they match `key.properties`. **Closed.** |
| O2 | Is there an Android 9 phone with 2–3 GB of RAM? Otherwise, which is the oldest? | the owner | **answered 2026-11-11: « an old Samsung ».** Model, Android version and RAM not known yet: read at step 6 with `adb` (`ro.product.model`, `ro.build.version.release`, `/proc/meminfo`) or by the owner in Settings › About phone. It must run Android 7.0 (API 24, the app's `minSdk`) or later, or Play will not offer the app on it |
| O3 | Trader, with phone and address shown everywhere (§3.6): still « trader »? | the owner | **answered 2026-11-11: « Rester professionnel »** |
| O4 | The location form: where it is, what it asks, whether it gates testing | read at step 7 | open. *2026-11-19: no form in the console yet (§7.1).* |
| O5 | Does `sentry_flutter` read `io.sentry.proguard-uuid` without the Gradle plugin? | step 6 | **answered 2026-11-13, from the code: read, then erased.** sentry-android 8.51.0's `ManifestMetadataReader.applyMetadata` sets it; sentry_flutter 9.26.0's options callback, which runs after, sets it back to `options.proguardUuid`, `null` in this app (`sentry_native_java_init.dart:218-219`); only the Gradle plugin's asset refills a `null`, and there is none. So the carrier is the Dart option (decision 135, §6). The runtime proof stays at step 6 (§5 row 17) |
| O6 | The rollout: 20 % for 48 h, then 100 %? | the owner, at step 10 | proposed |
| O7 | *Added 2026-11-13.* Does Sentry register a second upload of a byte-identical `mapping.txt` under a new `--uuid`? | step 5, the per-build check (§6) | ~~open (UNVERIFIED)~~ **answered 2026-11-20: yes.** Build 794's mapping is byte-identical to 788's; sentry-cli printed « Nothing to upload, all files are on the server », yet Sentry's debug-file list shows 794's UUID `96f1ab8a…` as a ProGuard mapping created at that upload, beside 788's `18030865…`. A Java event of 794 would show the lookup end to end (§5 row 17). *Before:* If it does not, the Gradle plugin is the fallback. *2026-11-18: not exercised yet. Build 785 uploaded the first mapping, and 788's differs from it (25,726,708 bytes against 21,880,516: Cronet's classes). Sentry lists each build's UUID.* |
| O8 | *Added 2026-11-13, the audit's Q-I.* Turn « Publication gérée » on after Google approves the closed release, before step 10, so that production goes out on the owner's click (step 8)? | the owner, before step 10 | **proposed, not answered** (the audit recommends yes). Off when last read, 2026-10-28 (play-store-forms §0.1) |
| O9 | *Added 2026-11-13, the audit's Q-L.* A production read of `GET /client-version?app=com.myweli.pro&platform=android&build=<N>` before the upload, to see that no floor blocks the AAB's build number (step 5 (d))? | the owner, at step 5 | ~~proposed, not answered~~ **answered 2026-11-18, « Yes, as recommended ».** Read in production before each AAB: `ok` for build 785, for build 788 and for build 1, so no floor is set for the Pro app on Android; iOS build 781 also answered `ok` |
| O10 | *Added 2026-11-19.* Production needs a new AAB, since 788 lacks the portrait declaration (§8, §11's log). The proposal: the internal track first, with the step-5 reads, then §5's rows 1 and 2 on the Galaxy and Play's device counts read; then the same release promoted through the closed track to production. Does a new build on the closed track touch the 14-day count? | the owner, before step 10 | proposed. The effect on the 14 days is UNVERIFIED: Google's page was not read here. *2026-11-20: the first half is done, the owner choosing « internal first »: build 794 on the internal track, its step-5 reads, Play's device counts (+27, none lost) and rows 1 and 2 on the Galaxy (§11). Left: the promotion through the closed track to production, and the 14-day question, still UNVERIFIED.* |

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
- **2026-11-13, a read-only audit of steps 3–11 (no step done).** Five
  readers and a critic, on `main` at `d19655bd`; nothing edited, built,
  installed or sent, no cloud or console read. Observed: `pubspec.yaml:4`
  still `0.0.1+1`; `build.gradle.kts:101` still says R8 « is deliberately NOT
  enabled »; no B0.17 code, B0.18's Pro app and B0.19 not built; no Android
  device attached (`adb devices`); the main checkout at `f36963a9`, 14 commits
  behind `origin/main` (`d19655bd`); `gh pr list` returned no open PR;
  sentry_flutter erases the manifest's proguard UUID (O5); sentry-cli 3.8.0
  hides `--uuid`; the Pro app's Google endpoint is `/auth/provider/google`;
  the pane cannot attach files. The owner answered decisions 134–136 the same
  day (BACKLOG), and this spec was amended for them and for the audit's
  findings; two of its proposals wait for the owner (O8, O9).
- **2026-11-18, step 3 (e), the R8 PR. Built, not merged** (`chore/r8-proguard-uuid`).
  `app/build.gradle.kts` writes `isMinifyEnabled = true` and
  `isShrinkResources = true` in release, and the « deliberately NOT enabled »
  comment is gone. `release_build.sh`, Android only: a UUID per build from
  python3 (`uuidgen` is not on every Linux runner), passed as
  `SENTRY_PROGUARD_UUID` on the `appbundle` line; the earlier `mapping.txt`
  removed first; no mapping after the build → refused, AAB renamed
  `.refused`; the `upload-proguard` block printed last, after the TLS gate.
  `error_reporting.dart` sets `proguardUuid`, `null` without the define.
  Tests, each new case watched red on the old code first:
  `android_release_r8_test.dart` (new: 4 cases and 3 premises),
  `release_build_test.dart` (7 cases that run the real script; the `flutter`
  stub logs its arguments, which B0.17's PR A reuses),
  `error_reporting_test.dart` (3 cases). Mutations on the committed code: 18 mutations, all red (the Gradle settings deleted, false, moved to debug, commented out, the old comment back; the UUID hard-coded, the mapping check or its removal dropped, the define in COMMON, the upload printed before the TLS gate or for iOS, the define renamed on either side or dropped; the app's wiring removed, hard-coded, its parameter ignored, an empty define kept).
  Not observable here: a real AAB (step 5), Sentry registering the UUID
  (O7, step 5) and a Java event carrying it (§5 row 17).
- **2026-11-18, steps 3 (e) and 3a. Merged.** #805 (the R8 PR, `a866bf08`,
  00:24 UTC), #806 (PR A, `d0b2c85a`, 08:37) and #807 (PR B, `1854bfc5`,
  11:10; one CI job re-run after the runner failed to download Kotlin's
  Gradle plugin). Each merge's `main` tree equals the PR head CI tested.
  PR C is left, before step 7.
- **2026-11-18, step 5: build 785.** On the owner's « Yes, as recommended »:
  no Dependabot PR rides in the bundle, O9 is read, Sentry is filled with the
  build. From `1854bfc5` in the main checkout: `app-pro-release.aab`,
  66,238,627 bytes, SHA-256 `d6bedfbe…3e76d904`.
  - **The bundle:** the TLS gate passed on the three ABIs (Dart 3.13.7,
    blocklist 8/8); 0.0.2 (785), minSdk 24, targetSdk 36; the R8 marker;
    `BUNDLE-METADATA/…/proguard.map` equal to `mapping.txt` (21,880,516
    bytes); the delivered `libapp.so` has no debug section.
  - **16 KB:** every arm64 library is aligned to 0x4000 or more.
  - **The signature:** the upload key (SHA-1 `4F:27…65:D1`).
  - **The sign-up:** pro-android-signup §8.3 (2), the positive control: the
    26 sign-up phrases present in the arm64 `libapp.so`.
  - **Sentry:** the Dart symbols, the mapping under its UUID and the release
    `com.myweli.pro@0.0.2+785` with its commits, all found on the server.
  - **O9:** `ok` for 785 and for build 1.
- **2026-11-18, step 6: build 785. Published, then stopped.** The owner
  dragged the AAB into the console in their Chrome; Claude in Chrome cannot
  attach a 66 MB file.
  - **Play:** one warning, 27 devices dropped (tablets 7, TV 3, car 17;
    phones unchanged at 12,542). The portrait lock (#682) implies
    `android.hardware.screen.portrait`, so this is expected.
    *(2026-11-19: no longer accepted. The feature is declared optional;
    see the line of that date below.)*
  - **Published** to the internal track on the owner's « Yes, publish it »,
    for the testers' list « OG TESTER » (one user).
  - **On the owner's Galaxy A73** (Android 14), installed from Play: « Pas de
    connexion. Réessayez. » at sign-in, over their Orange CI fibre Wi-Fi.
    Cause and fix: [android-http3-transport.md](android-http3-transport.md),
    then #808 (the spec), #809 and #810, all merged the same day.
- **2026-11-18, step 5: build 788.** On the owner's « Yes, build it », from
  `e8ec333c`, which holds the fix: 66,900,365 bytes, SHA-256
  `23437698…dacfbeb9`.
  - **The bundle:** the TLS gate's « carries the eMudhra blocklist » line;
    R8 UUID `18030865-b161-4556-a230-6759cdeb8073`; `proguard.map` equal to
    `mapping.txt` (25,726,708 bytes); the same permissions as 785, read the
    same way on both; the R8 marker; `libapp.so` with no debug section;
    16 KB aligned; the upload key.
  - **The fix in the bundle:** the manifest names the network security
    config, the 14 roots of the trust list are in `res/raw`, and Cronet's
    classes are in the dex.
  - **Sentry:** the three ABIs' Dart symbols, the mapping and the release
    `com.myweli.pro@0.0.2+788` with its commits, all found on the server.
  - **O9:** `ok` for 788 and for build 1.
- **2026-11-18, step 6: build 788. Published.** The owner uploaded it.
  - **Play:** « La release est prête », no warning. No device lost or gained
    (phones 12,542, tablets 6,844, TV 4, car 13, Chromebook 77, XR 2). A new
    install downloads 12.4 MB (+92.6 KB on 785), an update 3.5 MB.
  - **Published** on the owner's « Yes, publish it »; 785 is no longer in the
    release.
  - **The Galaxy:** the two test apps sideloaded during the diagnosis were
    removed first, on the owner's yes.
- **2026-11-18 and 19, the device pass on build 788** (§5). On the Galaxy A73,
  Android 14, installed from Play, over the owner's Orange CI fibre Wi-Fi, the
  network of « Pas de connexion ». Times are UTC.
  - **The transport:** the phone's log shows Cronet 158.0.8127.22, from Play
    services, loaded in the app. The server's log shows every request of the
    pass with the app's user agent, `MyWeli/0.0.2+788 (com.myweli.pro;
    Android)`, which only the Cronet client sends, and none with Dart's.
  - **Passed:**
    - **Row 1:** a cold start reaches « Espace Pro » with no crash. Sentry
      lists no issue for the release (read on Sentry's page, 22:52).
    - **Row 2:** e-mail code sign-in with `revue@myweli.test`, the review
      account in production: `otp/request` 202, then `verify` 200 (22:41:07 and 22:41:11).
    - **Rows 5 and 18:** the dashboard, the salon's photos and the map with
      streets (the owner).
    - **Row 19, and row 7's photo:** one gallery photo on the review salon,
      asked first. `/uploads/sign` 200, then the gallery `PUT` 200 in 679 ms
      (22:44). The server reads the object's size in R2 when the photo is
      claimed and refuses a missing one, so that 200 is the size read; R2 was
      not read from here.
    - **Row 7's PDF:** a one-page dummy PDF (961 bytes, « pas une vraie pièce
      »), asked first, on the three required KYC rows of the review account.
      Three `/uploads/sign` 200, then `POST /me/kyc` 200 in 1.5 s (00:17), the
      same size read. The weekly demo reset erases these files.
    - **Row 6:** « Utiliser ma position »: the prompt, « approximate », then a
      denial; the profile was not saved (the owner; the position never
      reaches the server).
    - **Row 8:** an expired access token renewed (one 401, the refresh 200,
      the retry 200, 00:07). Two reopenings still signed in (00:09, 00:10).
      « Se déconnecter » removed the push registration (`DELETE /me/devices`
      200), and signing back in restored it.
    - **Row 9:** « Support » and « Politique de confidentialité » open in the
      browser (the owner).
  - **Partly, row 4:** the prompt appeared once (the owner), and Android shows
    the permission as granted by the user. The token was registered (`POST
    /me/devices` 200, 22:41). No push has reached the phone yet: there is no
    way to send one without a real event, such as a booking.
  - **Not run yet:**
    - row 3 (Google sign-in);
    - rows 10 and 21: the old Samsung (O2), and mobile data, since the Galaxy
      has no data SIM;
    - rows 11–16, the sign-up, which join with PR C;
    - row 22, the iPhone.
  - **UNVERIFIED, rows 17 and 20:** no Android event has reached Sentry for
    785 or 788 (Sentry's issues page, 22:52), because nothing failed and
    handled errors are not sent. Both wait for a first event. The transport
    is observed all the same: only Cronet sends the app's user agent.
- **2026-11-19, step 3a. Merged.** #812 (PR C, `b275edcd`, 08:41 UTC), on
  the owner's word; `main`'s tree equals the PR head CI tested (`720562c6`),
  and CI and the iOS build passed again on `main`. Step 3a is done: §5 now
  holds rows 11–16, still to run on a phone, with test addresses the owner
  names first. Step 7 is next, on the owner's yes.
- **2026-11-19, step 7. Done, except the location declaration.** On the
  owner's yes for each form, in the browser pane, each form read back after a
  reload (play-store-forms §0.4):
  - **the listing's description** (1,100 characters) and **the sign-in text**
    (478 of 500), each equal by SHA-256 to play-store-forms §1 and §2 on
    `main` (`f17270ea`);
  - **Data safety**, four changes: the URL `https://myweli.com/pro/suppression-compte`;
    « Adresse » and « Numéro de téléphone » required, the phone with
    « Gestion des comptes »; « Prévention des fraudes, sécurité et
    conformité » on « Historique des recherches ». Play's preview was read
    row by row against §4's 15 rows, then beside the live policy and the
    live Pro deletion page (both 200);
  - **the public developer email:** `support@myweli.com` (decision 149),
    validated by a code the owner typed. After that, a fresh load in a
    second tab still showed the old address: the change was not saved yet.
    Claude saved it, and the next fresh load read it back. The browser pane
    closed twice between turns, losing unsaved forms both times, so each
    form was then finished within one turn;
  - **the trader declaration:** the account « Professionnel », with the
    phone the owner validated by SMS and the two boxes they ticked, read back
    after a reload; then « Oui » and `https://myweli.com/cgu` for MyWeli Pro
    and MyWeli (decision 150). No document was asked for;
  - **still no location form** (§7.1, O4);
  - **nothing sent for review:** MyWeli Pro reads « Envoyer 9 modifications
    pour examen », not clicked; MyWeli's « Envoyer l'appli pour examen » stays
    locked by its dashboard.
  - **The same day, #810's chain check ran on schedule for the first time**
    (`production-checks.yml` run 44549038281, 14:55 UTC, on `f17270ea`):
    `api.myweli.com` and `cdn.myweli.com` end in GTS Root R4, one of the 14
    bundled roots ([android-http3-transport.md](android-http3-transport.md)
    §5.2).
- **2026-11-19, between steps 8 and 10: Play's device filter.**
  - **Reported by the session that ran step 8, not read here:** build 788,
    promoted to « Tests fermés - Alpha », met Play's pre-review check
    « Les déclarations de fonctionnalités matérielles requises limitent la
    disponibilité de votre appli ». It named
    `android.hardware.screen.portrait`, for phones, tablets, desktop and
    Android XR.
    - The owner accepted it for the closed test (phones), to be fixed in the
      next build, before production.
    - The check was dismissed with « La résolution de ce problème est déjà
      prévue ».
  - **The cause, observed:** `aapt2 dump badging` (build-tools 36.0.0) on a
    release APK of the Pro app built from `d7e40407` prints
    `uses-implied-feature: name='android.hardware.screen.portrait'
    reason='one or more activities have specified a portrait orientation'`.
    That is the portrait lock of #682. Build 788 has the same lock, so it
    carries the same line (INFERRED; Play's check says so).
  - **The fix** (`fix/android-portrait-optional`):
    - a manifest-level `<uses-feature
      android:name="android.hardware.screen.portrait"
      android:required="false" />`; the lock stays;
    - the guards of §9;
    - step 5 (e) and step 10's precondition.
  - **Read on the artifact:** the same APK built with the fix.
    - Its badging names the feature once, as
      `uses-feature-not-required`. No other line of the badging changes.
    - `dump xmltree` still shows `screenOrientation=1` (portrait) on
      `MainActivity`.
    - The script refuses the first APK (exit 1) and accepts the second
      (exit 0).
    - These APKs are unsigned and were never uploaded.
  - **On a tablet emulator** (Pixel Tablet, 2560 × 1600 at 320 dpi,
    800 dp smallest width, Android 16, debug, mocks):
    - Android reports `ignoreOrientationRequest=true`, and the app opens in
      landscape.
    - Pro: sign-in, the invitation card, « Accueil », « Ma journée » and
      « Profil » are usable in landscape, in a centred column. Turned to
      portrait (`ROTATION_90`), they re-lay out without a restart.
    - The consumer app's home is usable both ways.
    - Neither run logged an overflow or an exception.
    - The PR describes each screen.
  - **Not covered:**
    - A tablet or Chromebook on Android 15 or earlier, where the lock
      applies. Only an API 36 image is installed here.
    - Android XR.
    - **Play's device counts after the next upload are the observation that
      closes this** (step 5 (e)).
- **2026-11-19 and 20, step 8. Done: the closed test is live.** Each action
  on the owner's yes, in the browser pane (play-store-forms §0.5):
  - **the track « Tests fermés - Alpha »:** 178 countries and regions
    (decision 117); testers = Testers Community's Google Group
    `testers-community@googlegroups.com`, confirmed by their setup page,
    which the owner pasted; feedback to `support@myweli.com`. Mailing lists
    and Google Groups exclude each other, and a tester change is itself a
    change sent to Google;
  - **Testers Community:** ordered by the owner (the Pro plan), and their form
    sent by the owner before the send (owner-reported; the link in it is not
    read here). The Web opt-in link is
    `https://play.google.com/apps/testing/com.myweli.pro`;
  - **build 788 promoted** from the internal track, the same bundle, no
    release notes, no error on the release's review screen;
  - **Play's portrait check** blocked the send. The owner chose to send 788
    to the closed test (phones) and fix it before production (decision 151).
    It was dismissed with « La résolution de ce problème est déjà prévue »;
    #815 is the fix (above);
  - **sent:** « Envoyer 16 modifications pour examen », confirmed. Play's
    quick checks passed, then « Vos modifications sont en cours d'examen ».
    Before sending: `/health` 200; `/client-version` for build 788 `ok`
    (control, build −1: `update_required`); `/pro/suppression-compte` 200;
    no open PR touched the site (decision 140's freeze);
  - **read 2026-11-20 at 00:14 UTC: published.** « Dernière publication le
    19 novembre 2026 », nothing pending. The track is « Actif », 178
    countries/regions; 788 « Disponible pour certains testeurs », released
    « 19 nov. 23:16 ». The temporary-name banner is gone. « Publication
    gérée » is off, so the approval published at once;
  - **next, step 9:** 12 testers opted in for 14 days in a row. Google's
    help 14151465, re-read on 2026-11-20, applies the rule to **personal**
    accounts created after 2023-11-13. The trader status changes nothing:
    the account type still reads « Personnel » (read the same day).
- **2026-11-20, step 5: build 794, O10's new AAB.** On the owner's « build
  the next AAB with the tablet fix », from `c4bf8c63` in the main checkout,
  fast-forwarded from `e8ec333c`. Six commits; the only change that ships is
  #815's manifest line, the rest is documents, tests and a Gradle comment.
  `app-pro-release.aab`, 66,900,539 bytes, SHA-256 `192b9978…c39c9fae`.
  - **The bundle:**
    - the TLS gate on the three ABIs (Dart 3.13.7, blocklist 8/8);
    - 0.0.2 (794), minSdk 24, targetSdk 36;
    - the R8 marker (R8 8.11.18, full mode) and R8 UUID
      `96f1ab8a-024f-411a-91fc-24581e1a8caf`;
    - `proguard.map` equal to `mapping.txt`: 25,726,708 bytes,
      byte-identical to 788's;
    - `libapp.so` with no debug section, on the three ABIs. The reader's
      control: the build's own `.symbols` file shows `.debug_info`;
    - every arm64 library aligned to 0x4000 or more;
    - the upload key (SHA-1 `4F:27…65:D1`, as 788).
  - **The sign-up:** all 26 phrases in the arm64 `libapp.so`; a made-up
    phrase counts 0.
  - **The transport fix, still in:** the manifest names the network
    security config, the 14 roots are in `res/raw` (the same files as 788),
    and Cronet's classes are in the dex.
  - **The portrait, (e):** `bundletool build-apks --mode=universal`, then
    `tool/verify_android_portrait_optional.sh` prints `OK` on 794.
    - **The control:** the same on 788's AAB is refused, exit 1, on its
      `uses-feature` and `uses-implied-feature` lines.
    - `aapt2 dump badging` of the two universal APKs differs in exactly two
      places: the version code, and the portrait lines. The permissions and
      the other features are the same.
    - bundletool 1.18.3 ran from Gradle's cache with its dependencies;
      nothing was downloaded.
  - **Sentry,** each read back from the server:
    - the three ABIs' Dart symbols, each with its sources;
    - the mapping under 794's UUID, which answers O7 (§6);
    - the release `com.myweli.pro@0.0.2+794`, with its 6 commits, the last
      `c4bf8c63`.
  - **O9:** `ok` for 794 and for build 1. A wrong verb answers 405, so the
    route read is the real one.
  - Flutter warns that Gradle 8.14, AGP 8.11.1 and Kotlin 2.2.20 will soon
    be unsupported, and Play's bundle page suggests AGP 9: both are B13.6.
- **2026-11-20, step 6: build 794. Published to the internal track.**
  - **The upload:** the owner put the AAB into a new internal release, in
    the built-in browser pane, from Finder (asked to drag it there; « It's
    in », owner-reported, then read on the page).
  - **Play's bundle pages,** read the same minute: 794 is supported on
    19,524 Android devices, 788 on 19,497. Everything else is equal: 12
    permissions, 3 features, 16 KB compatible, 12.4 MB to install, R8 full
    mode, 86 % obfuscated.
  - **The release:** « 794 (0.0.2) », no release notes, 788 not included.
    Saved on the owner's « Yes, save it », then read back from a second tab:
    794 « Brouillon », 788 still live.
  - **The review screen:** « La release est prête », no warning. Against
    788:
    - phones 12,532, none lost or gained;
    - tablets +7 (6,871), TV +2 (6), car +18 (30);
    - Chromebook 77 and Android XR 2, unchanged;
    - nothing lost. The 27 gained are as many as build 785 lost (2026-11-18,
      above).
    - A new install is 12.4 MB (+177 bytes); an update from 788, 275 KB.
  - **Published** on the owner's « Yes, publish it », through Play's
    confirmation dialog. Read back on a fresh load: 794 « Accessible aux
    testeurs internes », released « 20 nov. 10:46 ». The closed track is
    unchanged: 788, « Disponible pour certains testeurs », 178 countries.
  - **Not covered:** no tablet has installed 794. Play's counts gain nothing
    for Chromebook or Android XR, although its check on 788 named desktop and
    XR (2026-11-19, above).
- **2026-11-20, the device pass on build 794: rows 1 and 2.** The owner
  updated the Galaxy A73 from Play and ran both rows. The server's log shows
  them, every request with the user agent `MyWeli/0.0.2+794`, which only the
  app's Cronet client sends. The phone was not on adb. Times are UTC.
  - **Row 1:** the first start after the update, at 10:49:53.
    - `/client-version` 200; `/me/provider` 401, then
      `/auth/provider/refresh` 200, so 788's session survived the update;
      `/me/salons` 200; the dashboard 200 at 10:49:59.
    - Sentry, read on its page in the owner's Chrome: no issue for release
      794. The release page shows no activity at all from 794. 788's page
      lists the one event below, so the search does find this app's events.
  - **Row 2:** sign-out at 10:50:04; `email/otp/request` 202 at 10:50:09;
    `verify` 200 at 10:50:12; the dashboard 200. The same salon as 788's
    row 2, with `revue@myweli.test`.
  - **Push:** `POST /me/devices` 200 after each sign-in: the Galaxy
    registered its push token.
- **2026-11-20, an event on 788 that is not a user's.** Sentry's 788 release
  lists one issue, MYWELI-APP-F: « [firebase_messaging/unknown]
  java.io.IOException: FCM Registration failed! ».
  - It is handled: the app logs « Push: getToken failed ».
  - One event, at about 01:17 UTC on 2026-11-19, about three hours after 788
    reached the internal track. Row 1's read for 788 (2026-11-18, 22:52)
    came before it.
  - The device is an Android 16 emulator (`sdk_gphone64_arm64`,
    « Simulator: true »), in the US on Los Angeles time, with accessibility
    navigation on: one of Google's test devices, probably Play's pre-launch
    report (INFERRED; « Rapport pré-lancement » not read).
  - **Row 20's observation, on 788:** the event's tags carry
    `net.transport=cronet`. Row 17's `debug_meta` was not read.
  - No action: on a real phone, the token registers (row 1 above).
