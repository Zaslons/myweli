# Flutter 3.44.9 → 3.47.9

| | |
|---|---|
| **Module** | toolchain (cross-cutting: `mobile/`, CI, the golden baseline, the iOS build) |
| **Status** | **Draft — awaiting the owner's sign-off** on O1–O4 (§8; O5 only if the reformat is large). Nothing is built. |
| **Last updated** | 2026-11-10 |
| **Decision** | the owner, 2026-11-10: « Flutter 3.47.9 first » ([BACKLOG](../BACKLOG.md) decision 109) |
| **BACKLOG items** | batch 13: B13.1 (this PR), B13.2 (headings), B13.3–B13.8 (what follows) |
| **PRD ref / phase** | none (toolchain); NFR-PERF-002 for the APK budget |
| **ROADMAP entry** | added when it ships (`docs/roadmap/entries/`) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Related** | [mobile-flutter-3.44-upgrade.md](mobile-flutter-3.44-upgrade.md) (the last move, same cause), [SYSTEM.md](SYSTEM.md) §13 (accessibility), §20.1 (goldens), §21 (violations) |

How to read it: every claim names where it was read. **Observed** means run or
read here on 2026-11-10. **Inferred** or **UNVERIFIED** means it was not.

## 1. Why now

**(a) Five dependabot PRs cannot merge, for the reason the 3.44 move named.**
Dependabot resolves its lockfiles on a current Flutter, 3.47 today. Flutter
3.44.9 pins about fourteen packages exactly. Every dependabot lockfile moves
five of them (observed in the five diffs and in the 3.44.9 SDK's own
`pubspec.yaml` files):

- `meta` 1.18.0 and `vector_math` 2.2.0, pinned through `flutter`;
- `intl` 0.20.2, pinned through `flutter_localizations`;
- `test_api` 0.7.11 and `matcher` 0.12.19, pinned through `flutter_test`.

So `flutter pub get --enforce-lockfile` fails before anything compiles. #749's
run 42415764210 reads « Would change 5 dependencies ». #540 and #601 hit the
same wall earlier (`ci.yml:58-62`). The backend jobs of the five PRs fail for
an unrelated reason: the branches predate main's PostgreSQL 16 runner (#752).

**Measured on 3.44.9** (observed), with a fresh `flutter pub get` in a worktree
of `main`:

| PR | Bump | On 3.44.9 |
|---|---|---|
| #745 | firebase_core 4.15.2, firebase_messaging 16.7.1 | resolves; only the 7 FlutterFire entries move |
| #749 | cupertino_icons 2.0.0 | resolves; only it moves |
| #748 | lottie 3.8.2 | **fails**: 3.8.x needs Dart 3.13 / Flutter 3.47 (3.7.0 resolves) |
| #747 | cached_network_image 4.0.6 | **fails**: needs `material_ui` ^1.3.0, and 1.3.0 is retracted while every later version needs Flutter 3.47 (4.0.3, on `material_ui` ^1.0.0, resolves) |
| #746 | flutter_slidable 5.2.0 | **fails**: every 5.x needs Dart 3.13 / Flutter 3.47 |

**(b) 3.47.9 makes most of those pins ranges.** `meta` ^1.18.3, `vector_math`
^2.4.0 and `intl` ^0.20.3 become caret constraints. `test_api` 0.7.12, `matcher`
0.12.20 and `material_color_utilities` 0.13.0 stay exact. This was read in the
3.47.9 `pubspec.yaml` files of `flutter`, `flutter_test` and
`flutter_localizations`. So the failure class shrinks. §2's upper bound keeps
it from returning when 3.50 is stable; 3.50 is in beta, at 3.50.0-0.4.pre
since 2026-11-04 (Flutter's release manifest).

**(c) A security fix that every Android build needs.** GHSA-frr6-h895-5pxp
(High, 2026-10-23, read on GitHub): eight compromised eMudhra intermediate CAs
allow a TLS man-in-the-middle against `dart:io` on Android, Windows, and Linux
where the CA bundle is static. It is fixed in Dart 3.13.7, so in Flutter 3.47.8
and later, with no 3.44 backport.

- **The app:** it calls the API through `http.Client()`, which is `dart:io` on
  a phone (`api_pro_service.dart:53`). iOS is not affected. Android has not
  shipped, so this gates **the first Android build that reaches anyone, B0.10's
  closed test included**, not the iOS app.
- **The backend:** its production image is the advisory's Linux case: `FROM
  scratch`, with the runtime and its CA bundle copied from a `dart:stable`
  build stage (`backend/Dockerfile:13`, `:30-31`). Which Dart built the image
  production serves is UNVERIFIED. That check is B13.8.

**(d) 3.50 deprecates the in-SDK Material library.** Material and Cupertino
have been frozen in the SDK since 3.44 and ship as the `material_ui` and
`cupertino_ui` packages. 3.50 formally deprecates the SDK copies (Flutter's
breaking-change page « material-ui-and-cupertino-ui », read 2026-11-10). We
build with `--fatal-infos`, and 165 `lib/` files and 149 test files import
material (observed). So staying on 3.44 means taking two minors and a
Material migration at once.

**Checked, and not a reason: an iOS push regression.** firebase_messaging
16.5.0, which we ship, can leave a UIScene app without an APNs token (flutterfire
#18555), and our iOS setup is that one. The repo's own probe,
`mobile/tool/apns_probe.dart`, was run on `main` (observed, iPhone 17
simulator, iOS 26.5, debug). It received a real APNs token in three cases:

- on first launch;
- on a relaunch;
- on the app's own launch path, `registerIfGranted`: no permission request,
  and the token read at once and again 1, 3 and 10 s later.

A physical iPhone was not tested.

**Template sections not used, and why** (template numbers, not this spec's).
Template §2 UX: no flow changes; the one effect a user can notice is §3.1's
semantics, handled in O1. Template §3 API and §4 data: none. Template §5
architecture: no code structure changes. Template §6 security: §1(c) and
B13.8. Template §7 performance: the APK row of this spec's §5. Template §8
testing: this spec's §5 and §6. Template §9 rollout: a toolchain cannot sit
behind a flag; O4 orders it against 0.0.2.

## 2. Decision — target 3.47.9

3.47.9 is the latest stable (2026-10-29, Dart 3.13.7), one patch above the
security fix's floor (3.47.8). The constraints in `mobile/pubspec.yaml`:

- **`flutter: '>=3.47.9 <3.48.0'`.**
  - **The floor** is the CI pin itself, as the 3.44 move set it: it is the only
    Flutter this tree will have been built and tested on.
  - **The ceiling is new.** Dependabot resolves on the newest stable Flutter
    that satisfies the root constraint (dependabot-core
    `infer_sdk_versions.dart`). Pub enforces a root `flutter` upper bound from
    language 3.9 (pub's `interpretFlutterSdkConstraint`). Both were read by this
    spec's review and are not observed in a run here.
  - **Its effect** is that dependabot keeps resolving on 3.47.x. It refuses a
    bump that needs a newer Flutter, instead of opening red PRs that fill its
    5-PR limit. A local SDK newer than 3.47 refuses this tree loudly. The next
    toolchain PR raises the bound.
- **`sdk: ^3.12.0` stays.** At language 3.13 the formatter adopts a new style:
  import sections, block-formatted parameter lists, call-chain splitting
  (dart_style 3.1.10's changelog). Raising it is a repo-wide reformat, B13.5.

**Not in scope: the backend's Dart.** The backend is pure Dart (`sdk: ^3.10.0`,
CI on Dart 3.10.7) and does not depend on Flutter. Two things are noted for
B13.8:

- `backend/Dockerfile` builds `FROM dart:stable`, so production is compiled on
  a newer Dart than CI tests with;
- the TLS advisory may apply to the production image (§1(c)).

## 3. What 3.47.9 costs, stated plainly

### 3.1 VoiceOver loses the headings; TalkBack lost them before this

**Where the mapping lives.** This was read in the engine's sources (observed in
the local Flutter clone), not only in the breaking-change note.

- **iOS:** 3.44.9 sets the Header trait from `isHeader`
  (`SemanticsObject.mm:842`). 3.47.9 sets it from `headingLevel > 0` only
  (`:840`, flutter #186916).
- **Android:** it made the same switch in **3.38.0** (flutter #175416). At
  3.44.9, `AccessibilityBridge.java:1200` reads
  `setHeading(semanticsNode.headingLevel > 0)`.
- `header` is not deprecated, so `analyze` is silent. Widget tests are silent
  too, because the framework flag is still set; only the phone's mapping
  changed.

**What that means:**

- **On `main` today, TalkBack** announces no app bar title, and none of our
  three explicit headings, as a heading. It still hears the screen's name: on
  Android the bar names the route. Android has not shipped, so no user has met
  this.
- **Under 3.47, VoiceOver** loses them too, on the live Pro app. On iOS the app
  bar also sets `namesRoute: null` (3.47.9 `app_bar.dart:1072-1079`). So on
  3.47, VoiceOver finds no screen title by any means. That fails WCAG 1.3.1
  (level A), against SYSTEM §13's AA target.
- **What is affected:** 60 titled `AppBar`s in 56 `lib/` files, with no shared
  title widget (observed: a balanced-parenthesis scan with comments stripped).
  The salon page's two title-less `SliverAppBar`s are also affected, through
  their flexible space (`provider_detail_screen.dart:356`, `:375`, a 57th
  file; 3.47.9 `app_bar.dart:1399-1401`). On top of
  that come our three explicit headings:
  - `pro_invitations_screen.dart:268`, « Vous êtes invité(e) »;
  - `pro_invitations_card.dart:129`, « Invitations d’équipe »;
  - `carto_basemap_layer.dart:218`, the map-credits sheet title.
- **Waiting does not fix it.** As of 2026-11-10, `material_ui`'s `AppBar`
  (1.11.0, `app_bar.dart:1081`, `:1402`) still sets only `header: true`, so the
  `material_ui` migration restores nothing. **Open question O1.**

**The three explicit headings are fixed in this PR either way**, with
`headingLevel`, following a new SYSTEM §13.4 rule:

> **Titles are headings.** A route's title (its app bar title, or a sheet's
> title) carries `headingLevel: 1`. A section title inside a screen carries
> `headingLevel: 2`. `header: true` alone makes a heading on no phone (iOS
> since Flutter 3.47, Android since 3.38).

- **Levels:** the credits sheet's title is its own modal route, so level 1.
  « Vous êtes invité(e) » and « Invitations d’équipe » sit under a bar title,
  so level 2.
- **Tests:** each asserts `headingLevel > 0` on the node that carries the
  heading's text, which is what a phone reads. iOS and Android both test `> 0`
  and send no number; only the web uses the level. A separate assertion pins
  that a body heading's level is greater than its bar's. Each test is watched
  red with `header: true` put back.

### 3.2 A second Flutter on this Mac

Other working sessions use the 3.44.9 SDK at `~/development/flutter`, and
swapping it underneath them would break their runs. So 3.47.9 would be
installed beside it, by one of two routes (**O3**):

- **(b), recommended:** `git clone --local ~/development/flutter
  ~/development/flutter-3.47.9`, then `git checkout 3.47.9`. The tag is already
  on this Mac (observed), so no framework download is needed. Whether the tool
  runs from such a clone without warnings is UNVERIFIED.
- **(a), the fallback:** Google's archive
  `flutter_macos_arm64_3.47.9-stable.zip`, 2.27 GB (observed, release manifest),
  checked against the manifest's SHA-256.

**By either route**, the Dart SDK and the engine artifacts download from
Google's storage on first run; their size is not measured. The disk has 37 GB
free (observed).

### 3.3 The local golden script stays refused

`tool/update_goldens.sh` runs in `ghcr.io/cirruslabs/flutter:<version>`, which
publishes no 3.47.x tag (the review read the registry's manifests). The script
refuses rather than substituting a near version, by design (3.44 spec §3).
`goldens.yml` is the authoritative path, and it is the one used. The guardrail
skill's line naming `./tool/update_goldens.sh` gains « or `gh workflow run
goldens.yml` ».

### 3.4 Android Gradle sits on 3.47's error floor

3.47.9's `DependencyVersionChecker.kt` fails below Gradle 8.14.0, AGP 8.11.1
and KGP 2.2.20 (read at the tag). Ours are exactly those
(`gradle-wrapper.properties:5`, `settings.gradle.kts:22-23`), and the check is
a strict `<`, so the build passes with deprecation warnings.

3.50's beta already fails below Gradle 9.3.1, AGP 9.1.1 and KGP 2.4.10. So
AGP 9 and built-in Kotlin (B13.6) are due before the 3.50 move.

### 3.5 The first App Store binary built on 3.47

3.47.4 raised the iOS native-assets target from 13 to 15 (CHANGELOG 3.47.4,
flutter #191964). Our one native asset, `objective_c`, comes through
`path_provider_foundation`. It is now compiled for and declared as iOS 15,
where 3.44.9 used 13.

The ITMS-90208 rejections on 3.47.0–3.47.3 hit only libraries compiled above
the plist's 13. `objective_c` compiles at the configured target
(`hook/build.dart:197-198`), and builds 698 and 719 shipped it at 13. **We were
not exposed.** What is unproven is that App Store Connect accepts a 3.47.9
binary as a whole.

Two constraints decide how that is proven:

- `tool/release_build.sh` builds only `origin/main` (`:56-66`), and takes its
  build number from main's commit count (`:177`). A store build therefore comes
  after the merge.
- It already runs `xcrun altool --validate-app` before printing any upload
  command (`:260-264`).

**Open question O2.**

### 3.6 Tool side effects to commit

- **`analysis_options.yaml`.** `flutter pub get`, `analyze` and `build` on 3.47
  rewrite `mobile/analysis_options.yaml` (flutter #187940). The migration runs
  first in `ensureReadyForPlatformSpecificTooling`, which `pub get` calls. It
  appends `android/**`, `ios/**`, `macos/**` and `web/**`; `build/**` is
  already there. It appears at §6 step 3, and in every CI job's `pub get`
  until it is committed. The curated rules block must survive intact.
- **`ios/Podfile.lock`.** 3.47.9's `podhelper.rb` generates `Flutter.podspec`
  at iOS 15.0, where it was 13.0. So the `Flutter:` checksum at
  `mobile/ios/Podfile.lock:18` changes on the first `pod install`.
- **`Package.resolved`.** `flutter pub get` no longer prefetches Swift
  packages, so both tracked `Package.resolved` files change only through an
  iOS build. They are committed from the same build as `Podfile.lock`.
- **The formatter.** Dart 3.13's formatter carries fixes that apply at every
  language version (dart_style 3.1.8–3.1.13), and 3.44.9 most likely bundles
  dart_style 3.1.6. So the reformat cannot land first as its own PR: CI on
  3.44.9 would format it back and fail. `main` is squash-merged, and
  `.git-blame-ignore-revs` accepts only a purely mechanical commit. The
  reformat keeps its own commit only if this PR merges with a merge commit, as
  #286 did; squashed, it mixes with the SDK move and cannot be listed. **Open
  question O5.**
- **The Podfile's hook.** Since 3.47.0, `podhelper` itself strips sub-15
  deployment targets from every pod (`podhelper.rb:49`, `:90`). The Podfile's
  `post_install` hook (`ios/Podfile:43-48`) stays, as a guard for any pod below
  15. Its comments, and app-store-forms §11.1 (`:969-976`), are rewritten to
  say that Flutter does this too. The test at `ios_store_readiness_test.dart:388-392` stays.

## 4. Scope — the toolchain PR (B13.1)

| # | Change | Where |
|---|---|---|
| 1 | Local SDK 3.47.9, beside 3.44.9 (O3) | this Mac (not versioned) |
| 2 | Every CI pin, in **one commit** | `ci.yml:53`, `:812`, `:851`; `goldens.yml:46`; `ios-build.yml:70`; `deploy-admin.yml:72`; `tool/update_goldens.sh:24` |
| 3 | The constraint and its comment | `mobile/pubspec.yaml`: `flutter: '>=3.47.9 <3.48.0'` (`:39`); the comment at `:14-34`, whose `ci.yml:36, :471` and `ci.yml:44` references are already stale (pins at `:53`, `:812`, `:851`; format check at `:67`) |
| 4 | Lockfile | `mobile/pubspec.lock`, from `flutter pub get` (never `upgrade`): only the SDK-coupled packages and the `sdks:` block may move |
| 5 | **A pin guard** | `backend/test/infra/flutter_pin_test.dart`: every `flutter-version:` under `.github/workflows/`, `FLUTTER_VERSION` in `tool/update_goldens.sh` and the floor of `environment.flutter` are one string. Watched red by changing one pin |
| 6 | Headings | the three sites, their tests, SYSTEM §13.4's rule; and, if O1 = C, the shared title widget, 57 files and its guard (§8) |
| 7 | Tool side effects | `analysis_options.yaml`; `ios/Podfile.lock`; both `Package.resolved`; the formatter commit (§3.6) |
| 8 | Golden baseline | regenerated on Linux, every changed PNG measured and looked at |
| 9 | dependabot | `.github/dependabot.yml`: ignore `flutter_slidable` >=5.0.0, pointing to §7 |
| 10 | Prose | `ci.yml:58-62` (rebase advice for branches in flight); `tool/update_goldens.sh:43`; `SYSTEM.md:1337`; `test/support/golden.dart:33` (already says 3.38.6); `pubspec.yaml:81-82` (`intl` is ^0.20.3 from 3.47.9); `ios/Podfile:43-48`; app-store-forms §11.1; `README.md:60`; `.claude/skills/myweli-dev-guardrails/SKILL.md:111` |
| 11 | The Android gate | LAUNCH §6.3 gains « [ ] The AAB is built on Flutter ≥3.47.8 (GHSA-frr6-h895-5pxp) ». It was added with this spec, so it holds even before this PR |

**Explicitly out of scope**, each its own PR (batch 13):

- **The package bumps** (§7, B13.3). Mixed into the SDK move, a regression
  could not be attributed.
- `sdk: ^3.13.0` and its reformat (B13.5).
- AGP 9 and built-in Kotlin (B13.6).
- The `material_ui` / `cupertino_ui` migration (B13.7).
- The backend image (B13.8).

## 5. Risk, and what catches it

| Risk | What catches it | Residual |
|---|---|---|
| Removed or renamed APIs | `flutter analyze --fatal-infos --fatal-warnings` = 0 | none: a compile error |
| Behaviour under test | the full `flutter test` | tests cover what they cover |
| **Rendering drift** | the 58 goldens, regenerated on Linux and measured: pixel-identical count, worst %, pixels past Δ100, any size change | likely small, not certain: the goldens load the same fonts artifact (same hash at both tags, read by the review) and render with deterministic Skia, while engine rolls (Skia, HarfBuzz, FreeType) are unquantified. A size change means reflow, and gets investigated |
| **Headings** | the new tests; **Accessibility Inspector in the simulator**, before and after (§6 step 10); VoiceOver on a device if the owner looks | widget tests cannot see the phone's mapping |
| A pin left behind, now or later | the pin guard (§4 row 5) | none once it has been watched red |
| A reformat breaking a cross-surface parser | the web and backend suites that read Dart sources (§6 step 4) | none once they have been run |
| Android build | `Mobile — APK size`, recorded against main's **21.40 MB** (run 42911559399, `a101971e`) and the 30 MB budget | Gradle warnings expected (§3.4) |
| iOS build | `ios-build.yml` (consumer flavour, simulator, debug); a local Pro release build without signing | the signed store build comes after the merge (O2) |
| App Store validation | `altool --validate-app` on the first release build from `main` (O2) | whether validation reports ITMS-90208 is UNVERIFIED |
| Push on the new engine | the APNs probe re-run on 3.47.9 (§6 step 9) | simulator only |
| Lockfile | `--enforce-lockfile` in every job | none |

## 6. Order of work

1. **Install.** Install 3.47.9 beside 3.44.9 (O3). `flutter --version` reads
   3.47.9 and Dart 3.13.7.
2. **The pins.** In a worktree of `main`, make every pin of §4 row 2 and the
   constraint of row 3, **in one commit**. Write the pin guard first, and watch
   it red with one pin off.
3. **The lockfile.** Run `flutter pub get`, read the lockfile diff, and explain
   every line. Commit the `analysis_options.yaml` rewrite with it.
4. **The formatter.** Run `dart format .` and count the files it moves; O5
   decides how they land. If it touches a file that a web or backend test
   parses, run those suites before pushing:
   - **web:** `web/scripts/dart-tokens.mjs` and its `tests/tokens.mirror.test.ts`;
     the `*parity*` tests; `pro-team.test.ts`; `unnamed-salon.test.ts`;
   - **backend:** `oauth_audience_test.dart`; `salon_state_refusal_test.dart`.
5. **Analyze.** `flutter analyze --fatal-infos --fatal-warnings` → 0; fix
   whatever it names.
6. **Headings.** Write each test first and watch it red, then add the SYSTEM
   §13.4 rule. If O1 = C, also the shared title widget and its guard (§8).
7. **Tests.** Run the full `flutter test` once, on its own (goldens skip on the
   Mac).
8. **Goldens.** Push, run `goldens.yml` on the branch, then measure and look at
   every PNG before committing. If O1 = C, no PNG may move because of the
   headings: a `Semantics` wrapper paints nothing. If `pro_splash_wordmark` or
   `pro_splash_end` moved, re-run the promo reel's `python -m promo.lottie
   check` (from `tool/promo_reel`).
9. **iOS.**
   - `ios-build.yml` runs.
   - Locally: `flutter build ios --release --flavor pro --target
     lib/main_pro.dart --no-codesign`, read with app-store-forms §11.3's
     commands. Then, for every `Runner.app/Frameworks/*.framework`, compare
     the binary's `minos` (`xcrun vtool -show-build`) with its Info.plist
     `MinimumOSVersion`. Fail only where `minos` is above the plist, the
     ITMS-90208 class. The control is `Runner-pro-719.xcarchive`, the build
     Apple approved: every pair is equal there, Sentry's 100.0/100.0 included
     (read by the review).
   - Commit `ios/Podfile.lock` and both `Package.resolved` from one build.
   - Re-run the APNs probe on 3.47.9, in the three cases of §1.
10. **Accessibility Inspector**, on the Pro flavour in the simulator, on the
    « Accueil » bar title and on « Vous êtes invité(e) »:
    - **3.44.9 (`main`) is the control:** the Header trait must be present. If
      it is absent there, the probe is reading the wrong node.
    - Then 3.47.9 without the fix: expected absent.
    - Then 3.47.9 with the fix: « Vous êtes invité(e) » present again;
      « Accueil » present again only if O1 = C (otherwise absent until B13.2).
11. **CI fully green**, including APK size and the iOS build. Record the APK MB
    against 21.40.
12. **Merge**, on the owner's word.
13. **After the merge:**
    - O2's validation, from `main`, with 3.47.9 first on `PATH`
      (`release_build.sh` runs whichever `flutter` is there).
    - Move the Mac's default SDK, once open mobile branches have rebased (O3).
    - Docs: this spec's outcome; the 3.44 references; the roadmap entry.

## 7. After it merges: the packages, one PR each (B13.3)

Four red dependabot PRs close, each pointing to its replacement; #746 closes
pointing to item 5. Each bump is our own branch from `main`, with a lockfile regenerated on 3.47.9. A general
rule applies to all of them: **a bump whose changelog says it moved to
`material_ui` changes which theme its widgets read**, so it is looked at on
screen. The order:

1. **firebase** (#745): `firebase_core` ^4.15.2, `firebase_messaging` ^16.7.1.
   - **One code line.** It adds `AuthorizationStatus.deniedPermanently`, so the
     switch at `fcm_push_notification_service.dart:98-107` stops compiling
     until it maps that value to `denied`. A test covers the new case, watched
     red.
   - **iOS dependencies.** firebase-ios-sdk moves 12.17.0 → 12.19.3, which
     regenerates both `Package.resolved` files.
   - **iOS push.** 16.7.0 moves when iOS registers for APNs (flutterfire #18650,
     #18620). The APNs probe is re-run on the bump branch, in the three cases
     of §1.
   - **Android 13+.** A never-asked user now reads « not determined » instead of
     « denied », so the one-time prompt shows. A cold-start tap no longer also
     fires `onMessageOpenedApp` (flutterfire #18663). Our bridge listens to
     both (`fcm_message_bridge.dart:60-67`), so this removes a possible double
     hand-off. Both are noted, not tested on a device: Android has not shipped.
2. **cupertino_icons** 2.0.0 (#749): the same font bytes (identical SHA-256, read
   by the review). Nothing in `lib/` uses a Cupertino widget or
   `CupertinoIcons` today. Whether to drop the dependency is a separate
   question.
3. **lottie** 3.8.2 (#748).
   - **The app's animations.** The seven animations are rendered frame by frame
     before and after, as at 3.6.1. Then a device look at the Pro opening
     animation and `BrandLoader`, like the one app-store-forms §11.6 asked of
     the first build carrying 3.6.1.
   - **The promo reel's player.** It mirrors lottie-flutter's rules
     (`tool/promo_reel/promo/lottie/player.py:3`). 3.7.0–3.8.2 change exactly
     those rules: frame rounding, a layer starting on a frame, sampling, and
     easing interpolators. So its `check` is re-run against the pro_splash
     goldens, and the version it cites is updated in
     `tool/promo_reel/promo/lottie/` (`player.py:3`, `README.md:32`,
     `__init__.py:7`).
4. **cached_network_image** 4.0.6 (#747): no API change and no theme effect at
   our call site. The package reads no `Theme`, and we supply `placeholder`,
   `errorWidget` and `imageBuilder` (`timed_cached_image.dart:163-193`).
   - It brings `material_ui` and `cupertino_ui` into the graph, and
     `material_ui` bundles a shader (`ink_sparkle.frag`). The APK MB is
     recorded.
   - The network success and error cases extend
     `test/widget/timed_cached_image_test.dart`, which covers only the asset
     branch today.
5. **flutter_slidable stays on 4.0.3** until the `material_ui` migration
   (B13.4, with B13.7).
   - **Why it waits.** 5.x's built-in actions read their theme from
     `material_ui`. Our `MaterialApp` comes from `package:flutter/material`, so
     the four actions (`pro_journal_screen.dart:353-414`) would lose AppTheme
     with no error. Its own MIGRATION.md says to stay on 4.x until then, and no
     golden pictures an open action pane.
   - **Closing it.** #746 closes, pointing here, and dependabot ignores
     >=5.0.0 (§4 row 9).
   - **Swipe tests.** They land on 4.0.3 first, so the later bump is proven
     rather than assumed.

Today the five red PRs also fill dependabot's `open-pull-requests-limit: 5`.
No other pub bump can open until they close.

## 8. Open questions for the owner

- **O1. Screen titles as headings for VoiceOver** (§3.1). On 3.47 the live iOS
  app has no screen title a VoiceOver user can find, which fails WCAG 1.3.1
  (level A). *Recommended: C.*
  - **A.** Accept it, recorded in SYSTEM §21. Waiting brings nothing back
    (§3.1). *Not recommended.*
  - **B.** Restore it in a follow-up PR right after this one (B13.2). Only with
    a mechanism: a §21 row, and B0.3 saying that no iOS store build is cut
    from `main` between B13.1's merge and B13.2's.
  - **C.** Do it inside this PR. That means one shared title widget with
    `headingLevel: 1`, the 60 titled app bars and the salon page's two slivers
    moved to it, and a guard.
    - **The cost:** 57 files of mechanical change.
    - **Why it fits:** the 3.44 move kept *packages* out, not the defects the
      SDK surfaced. It closed SYSTEM §21 row 88 in the same PR, on condition
      that the fix be pixel-inert. A `Semantics` wrapper paints nothing, so C
      meets that condition, and the goldens prove it.
    - **The guard:** it parses every `AppBar(` and `SliverAppBar(` under
      `lib/`, with comments stripped and balanced parentheses, not a line
      regex. Each must have a `title:` that is the shared widget, or no title;
      a title-less bar with a `flexibleSpace:` must carry the shared heading
      there. It asserts that it saw at least 60 titled bars, so an empty sweep
      cannot pass. It is watched red three times: on a one-line
      `AppBar(title: Text(`, on a split one like `my_bookings_screen.dart:83-84`,
      and on the salon page's sliver. A widget test on the salon page asserts
      `headingLevel > 0` on the cover's name.
- **O2. How App Store acceptance is proven** (§3.5). *Recommended: validate
  with 0.0.2's first build; no separate upload.*
  - **Validation needs an unreleased version.** `release_build.sh` sets only
    the build number, and `pubspec.yaml` says 0.0.1, which is released. A
    0.0.1 build may be refused (90062, 90186) whatever the toolchain; whether
    `altool --validate-app` checks this is UNVERIFIED. So the validation build
    carries 0.0.2, after B0.3's version bump, and runs `tool/release_build.sh
    ios pro` from `main`, which validates and uploads nothing.
  - **If O4 = Before,** 0.0.2 is a 3.44.9 build, and the first 3.47 binary
    App Store Connect sees is 0.0.3's.
  - **An upload** becomes that version's first build in App Store Connect. An
    internal group with automatic distribution would receive it (UNVERIFIED for
    this account).
  - **The revert rule:** the toolchain squash is reverted only on a 3.47-class
    error, one that names a framework's `MinimumOSVersion` (ITMS-90208), not on
    a version or train refusal.
- **O3. The local SDK** (§3.2). *Recommended: route (b) now; move the default
  after the merge, once open mobile branches have rebased, with the exact
  command from me.*
  - **The install:** route (b), a local clone with no framework download, or
    (a), the 2.27 GB archive. Either way, artifacts download on first run.
  - **The default:** at merge, move the Mac's `flutter` to 3.47.9, but only
    once open mobile branches have rebased on the merged `main`. A
    `flutter pub get` on 3.47.9 in an unrebased branch rewrites its lockfile,
    and its CI on 3.44.9 then refuses it.
- **O4. 0.0.2 and this PR.** Is 0.0.2 cut from `main` before or after the
  toolchain PR? *No recommendation: it is the release track's order.*
  - **After:** 0.0.2 is the first App Store binary built on 3.47 (O2). It
    needs O1's fix first (C, or B merged), and it waits for this PR.
  - **Before:** 0.0.2 ships on 3.44.9 with its VoiceOver headings intact, and
    this PR lands after it. But `release_build.sh` builds only `main`, and
    0.0.1 needed three builds. So this PR then waits for Apple's **approval**
    of 0.0.2, not just its cut, and B0.10's closed-test AAB waits with it.
  - **Either way:** Android needs this PR first (§1(c)). From 2026-11-16, Apple
    asks two new age-rating questions of any update, 0.0.2 included.
- **O5. How this PR merges, if `dart format` moves many files** (§3.6). Put
  to you only once §6 step 4 has counted them and the count passes about ten;
  below that, the usual squash. *Recommended then: a merge commit.*
  - **A merge commit** keeps the reformat as its own commit, listed in
    `.git-blame-ignore-revs`, so `git blame` skips it, as #286 did at 3.7.
  - **The usual squash** mixes it with the SDK move; `git blame` then credits
    those lines to the toolchain PR.

## 9. What this will NOT verify

- **A physical device**, unless the owner looks: VoiceOver headings, sign-in, a
  push, the animations. The repo observes no device; the simulator checks of
  §6 steps 9–10 are the nearest it gets.
- **Android on a device.** Android has not shipped; only the APK builds.
- **Engine rasterization outside the goldens.** The goldens prove Linux draws
  the same bytes, not that a phone does.
- **The admin console's look** on 3.47's web engine. It has no goldens, only
  the build job.
- **App Store acceptance before the merge** (§3.5, O2).

## 10. Definition of done

- [ ] `flutter analyze --fatal-infos --fatal-warnings` = 0; `dart format` clean.
- [ ] The full `flutter test` green; the web and backend parsers green if
      touched.
- [ ] Goldens regenerated on Linux, measured, and every changed PNG looked at.
- [ ] Every new guard (pins, headings, the title widget if C) watched red.
- [ ] Accessibility Inspector recorded: control on 3.44.9, absent on 3.47.9
      without the fix, present with it (§6 step 10).
- [ ] The APNs probe's three cases on 3.47.9 recorded (§6 step 9).
- [ ] No framework whose binary `minos` is above its `MinimumOSVersion`, with
      the 719 control (§6 step 9).
- [ ] `ios/Podfile.lock` and both `Package.resolved` committed from one build.
- [ ] CI fully green, APK MB recorded against 21.40.
- [ ] Feature branch and PR, authored by the owner, with no Claude author or
      co-author.
- [ ] After the merge: O2's validation recorded; this spec's status and
      outcome updated; the ROADMAP entry added; batch 13 updated.
