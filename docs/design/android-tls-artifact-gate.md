# Android TLS gate: the built APK and AAB are read before they ship (GHSA-frr6-h895-5pxp)

| | |
|---|---|
| **Status** | **Built 2026-11-11, not merged**, stacked on [#758](https://github.com/Zaslons/myweli/pull/758). Approved by the owner the same day (« Build the gaps after #758 »). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-11 |
| **PRD ref / phase** | Security, cross-cutting · V1 |
| **Module** | toolchain (`mobile/` Android, CI, `tool/release_build.sh`) |
| **Builds on** | [mobile-flutter-3.47-upgrade.md](mobile-flutter-3.47-upgrade.md) (#758: every pin at 3.47.9, the headings, the goldens). This spec covers only the three things #758 does not. |
| **Related** | [backend-dart-sdk-pin.md](backend-dart-sdk-pin.md) (#757, the server side of the same advisory, and the image check this mirrors) · [play-store-forms.md](play-store-forms.md) (B0.10) · LAUNCH §6.3 |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `tool/verify_android_tls.py` · the `apk-size` job in `.github/workflows/ci.yml` · the Android branch of `tool/release_build.sh` · `backend/test/infra/android_tls_gate_test.dart` · the Android cases in `mobile/test/infra/release_build_test.dart` |

Every claim is **read** (observed, with how) or **inferred** (and from what).

## 1. Goal & scope

#758 moves every Flutter pin to 3.47.9. That fixes the advisory **in
configuration**, and its guard checks that the pins **agree**. Three gaps are
left:

1. **Nothing reads the artifact.** The Android gate is a checkbox in LAUNCH
   §6.3: « The AAB is built on Flutter ≥3.47.8 ». A sentence in a checklist is a
   wish (verification §9). The one thing that ships is the APK or AAB, and
   nothing looks inside it.
2. **Agreement is not safety.** #758's pin test passes if every pin moves back
   to 3.44.9 *together*. It checks that the pins match, not that they clear the
   advisory.
3. **The Android 14+ root store moves.** 3.47.8 makes `dart:io` read root
   certificates from the Conscrypt APEX on Android 14+. Nothing has shown that
   our hosts still verify that way on a real Android 14+ system.

**In scope:**
- **`tool/verify_android_tls.py`.** It reads every `libflutter.so` in an APK or
  AAB, and refuses unless each one carries Dart ≥ 3.13.7 **and** all eight
  blocked eMudhra key hashes.
- **It runs in two places:**
  - in CI's `apk-size` job, after the release APK is built, with a self-test
    first;
  - in `release_build.sh android`, on the AAB that would be uploaded. A refusal
    stops the script before any upload instruction is printed, and renames the
    AAB to `*.refused`.
- **An advisory floor**, separate from #758's agreement check. Every Flutter
  pin and the pubspec floor must be ≥ 3.47.8.
- **Wiring guards**, so the verifier cannot quietly drop out of CI or the
  script.
- **A device check** on the Android 16 emulator, against production, signed out.

**Out of scope:** everything #758 does. Also out: AGP 9 (#758's B13.6),
certificate pinning, iOS (not affected) and web (not affected).

## 2. The oracle, read from the bytes

The fix is BoringSSL's `check_blocklist()`. It hashes the SPKI of every
certificate in a chain and refuses any of eight. Its table, `kBlockList`, was
read in `crypto/x509/x509_vfy.cc` at BoringSSL `c7eb007fd106`, the roll that
Dart 3.13.7 takes.

**The test:** take the Android engine each Flutter release resolves through
Gradle (`io.flutter:arm64_v8a_release:1.0.0-<engine.version>` from
`download.flutter.io`), and search its `lib/arm64-v8a/libflutter.so`.

| Flutter | `engine.version` | VM version string | `kBlockList` hashes present |
|---|---|---|---|
| 3.44.9 | `5a2a6a42…` | `3.12.2 (stable) … on "android_arm64"` | **0 / 8** |
| 3.47.9 | `89c39edf…` | `3.13.7 (stable) … on "android_arm64"` | **8 / 8** |

Both signals tell the two engines apart, so the probe discriminates
(verification §4).

- **The version is the advisory's own criterion.**
- **The hashes are the fix itself.** Requiring both means a correct label on
  the wrong bytes is refused, and so is the right bytes behind an unreadable
  label.

## 3. Exposure, for the record (read from code)

On Android, `package:http`'s `Client()` is an `IOClient`
(`http-1.6.0/lib/src/client.dart:14`). It verifies with that `libflutter.so`.
`mobile/lib` has no `badCertificateCallback`, no `SecurityContext` and no
pinning.

| Through `dart:io` on Android | Code |
|---|---|
| Every API call: sign-in codes, Google ID tokens, **access and refresh tokens**, client names and phones, bookings | all `Api*Service` (`http.Client()`) |
| **KYC identity documents** and photos, PUT to presigned R2 URLs | `api_pro_kyc_service.dart:91`, `api_image_upload_service.dart:130` |
| `/client-version` (a forged `update_required` could carry any link) | `client_version_gate.dart:132` |
| Images; map tiles with **the Carto key in the URL** | `TimeoutCacheManager`, `NetworkImage`; flutter_map 8.3.2 `RetryClient(Client())` |

**Not `dart:io`:**
- **Sentry.** sentry_flutter 9.26.0 hands envelopes to sentry-android through
  `FileSystemTransport` (read). That sentry-android then uses Android's own
  stack is inferred.
- **FCM and Google sign-in** are native, but the Google ID token is then sent
  to our API (first row).
- **url_launcher** opens the browser.

**Who is exposed today: no store user** (inferred).
- iOS and web are not affected.
- Per the repo's B0.10 record, nothing has been uploaded to Play. The live
  console cannot be seen from here.
- Side-loaded APKs: unknown. Only the owner can say.

## 4. The verifier, `tool/verify_android_tls.py`

It uses the Python standard library only, and is run with `python3 -I`.

- **It finds every `libflutter.so`.** In an APK that is `lib/<abi>/libflutter.so`;
  in an AAB, `base/lib/<abi>/libflutter.so`. At least one must exist, so the
  check can never pass over an empty set (verification §2).
- **Each library must carry:**
  - exactly one VM version, shaped `X.Y.Z (stable) (…) on "android_<arch>"`,
    with X.Y.Z ≥ **3.13.7**. Versions are compared as numbers, so 3.13.10
    passes and 3.13.6 does not;
  - **all eight** hashes.
- **Every library must pass.** An AAB that mixes ABIs from two engines is
  refused.
- **It fails closed:** a missing file, a non-zip, no library, no version or two
  different versions, a non-stable channel (we ship no beta), or a missing
  hash is a refusal (exit 1). Each refusal says which rule failed.
- **`--self-test`** builds synthetic archives in a temporary folder and checks
  each verdict:
  - the fixed APK and AAB layouts pass;
  - an engine above the floor passes, so a future SDK stays green;
  - each refusal case above fails.

  CI runs it before the real check, so the refusal paths cannot rot unseen.
- **`--write-fixture {fixed,vulnerable} PATH`** writes one of those synthetic
  AABs. It exists for the release-script test's stub `flutter`, so the test
  runs the real verifier against an AAB it knows.

**The floor lives in one place, `MIN_DART = (3, 13, 7)`.** The guard in §5
refuses any value below it.

**The hashes are copied from BoringSSL**, and the provenance sits next to them
in the script. They are public data: SHA-256 hashes of public keys.

## 5. The guards, and which event turns them red

`backend/test/infra/android_tls_gate_test.dart` sits beside #758's
`flutter_pin_test.dart`. It runs in the backend job on every PR, because the
backend has `yaml`. Shell text is read with comment and `echo` lines stripped.

| Rule | Red on |
|---|---|
| The `environment.flutter` floor in `mobile/pubspec.yaml`, every `flutter-version:` in every workflow, and `update_goldens.sh`'s pin are each **≥ 3.47.8** | any of them below the advisory floor, including all of them moving back together. #758's test cannot see that case |
| The verifier's `MIN_DART` is ≥ (3, 13, 7) and `BLOCKLIST` holds 8 distinct 64-hex entries | the floor lowered, or a hash dropped or mistyped |
| `ci.yml` `apk-size` runs `--self-test` and then the verifier on `app-consumer-release.apk`, both **after** the build step, with no `if:` and no `continue-on-error` | the check removed, moved before the build, or made skippable |

`mobile/test/infra/release_build_test.dart` already **runs** the script with a
stubbed `flutter`. The stub now writes an AAB built by `--write-fixture`, and
the real verifier reads it:

| Case | Expected |
|---|---|
| fixed AAB | exit 0, the Sentry notes printed |
| vulnerable AAB | **exit 1**, no Sentry/upload notes, the AAB renamed `*.refused` |
| no AAB written | **exit 1**, refused by the check, not by a crash |

**What each guard cannot see** (verification §12):
- The pin floor reads configuration only. The verifier covers that gap.
- The verifier reads what CI and the script build. It cannot see:
  - **an APK built by hand outside the script.** `release_build.sh` is the only
    sanctioned path (LAUNCH §6.3), and the checkbox stays as the human half;
  - **an AAB swapped after the check.**
- The device check (§6) runs once. It is evidence for 3.47.9, not a monitor.

**Every row's red event is a defect.** A newer SDK that keeps the blocklist
stays green. One honest ambiguity remains. A future BoringSSL might restructure
or drop the static table, for example once Android's root store no longer
needs it. That would turn the hash rule red on a repair. If that happens,
re-read the advisory and change the rule. The refusal message says so.

## 6. The device check (once, recorded in the PR)

- **Device:** the AVD `a11_360dp`. *Read* from its `config.ini`:
  `system-images/android-36/google_apis/arm64-v8a`. That is Android 16, so the
  new Conscrypt APEX root path applies.
- **Build:** a release APK, consumer flavour, built on 3.47.9 with the two
  defines `build_config_guard` requires (`USE_API_BACKEND=true`,
  `API_BASE_URL=https://api.myweli.com`). No Sentry DSN or Carto key is used:
  no secret is read for this.
- **The verifier first.** It must accept this APK, which is the real-artifact
  positive case.
- **Pass:** opened **signed out**, the home screen reaches the state production
  data implies. `GET /providers` is re-read at the time; today it has 0 public
  salons, so the expected state is the empty state.
- **Control:** the same APK with the network off must show the error state. So
  the pass is not a page that looks the same either way.
- **No sign-in with any production account.**

### 6.1 Result, 2026-11-11 (read here)

**The real APK.** It was built on this branch with Flutter 3.47.9
(`flutter build apk --release --flavor consumer --target-platform
android-arm64` plus the two defines), in 139 s, at 27.4 MB.
- **Gradle printed exactly the three warnings §5.1 of the 3.47 spec
  predicts:** Gradle 8.14.0 < 9.1.0, AGP 8.11.1 < 9.0.1 and KGP 2.2.20 < 2.3.20,
  each « will soon be dropped ». That is B13.6.
- **Its `libflutter.so` is stripped** (11.8 MB against the Maven jar's
  165 MB), and the verifier still reads `Dart 3.13.7 (stable), blocklist 8/8`.
  So stripping keeps both the version string and the table.
- **The two other ABIs a release AAB carries were checked the same way**, from
  their Maven engines. 3.47.9's `armeabi-v7a` and `x86_64` both read
  `Dart 3.13.7 (stable), blocklist 8/8`, and 3.44.9's are both refused at
  3.12.2. So B0.10's three-ABI bundle will not be refused for a format
  difference between architectures.
- **The APK is unsigned.** There is no upload key in a worktree, and CI's APK
  is unsigned the same way. To install it, a copy was zipaligned and signed
  with this Mac's standard Android debug key. Its `libflutter.so` has the same
  SHA-256 as the unsigned build, and the verifier accepts the signed copy too.

**The device.** It reports Android 16, API 36
(`getprop ro.build.version.release` / `.sdk`). The AVD held an older debug
build from 2026-10-22, in demo mode. It was updated in place, then its data
was cleared, so the run starts signed out.

| Run | Screen | Production's request log |
|---|---|---|
| **Online**, 01:10:30 UTC | « Aucun salon trouvé », the empty state. `GET /providers` answered `total: 0` the same minute. | 01:10:32 `GET /client-version?app=com.myweli.app&platform=android&build=1…` **200**; 01:10:39 `GET /providers?page=1&pageSize=3` and `…pageSize=20` **200**. All three with user agent **`Dart/3.13 (dart:io)`**. |
| **Control, airplane mode**, 01:11 UTC (`ping` « Network is unreachable ») | « Chargement impossible — Pas de connexion. Réessayez. », the error state. | nothing |

No `HandshakeException`, `CERTIFICATE_VERIFY_FAILED` or `SocketException`
appeared in logcat during the online run. **So on Android 16 the 3.47.9
`dart:io` verified `api.myweli.com` against the Conscrypt APEX roots.** It is
the user agent that ties those requests to this engine, and
`platform=android` and the minute tie them to this emulator.

## 7. Rollout

- **Merging deploys nothing.**
- **The PR is stacked on #758,** with its base set to `chore/flutter-3.47.9`.
  CI runs only on PRs into `main`. So once #758 is squashed:
  1. `git rebase --onto origin/main <#758's tip> <this branch>`;
  2. retarget the base to `main` **before** pushing;
  3. the first CI run is the real one. On it, `apk-size` reads a real APK on
     Linux.
- **B0.10:** the AAB is built after both PRs are on `main`. `release_build.sh`
  then refuses a vulnerable one by itself.

### 7.1 Mutations watched red (2026-11-11)

All 24 were run from a committed tree. The harness asserts that each edit
applied (a non-applying edit is no result) and restores between runs.

- **`android_tls_gate_test`:**
  - **M1:** every pin, the golden script and the floor back to 3.44.9;
  - **M2–M4:** one pin, the golden script, or the floor alone below 3.47.8;
  - **M5:** `MIN_DART` lowered;
  - **M6–M7:** a hash deleted, or a hash duplicated;
  - **M8–M13:** the CI step deleted, made `if: false`, made
    `continue-on-error`, moved before the build, swallowed by `|| true`, or
    reduced to an `echo` of itself.
- **`release_build_test`:**
  - **M14:** the stale AAB is no longer removed;
  - **M15:** the verifier never runs;
  - **M16:** a refused AAB is left uploadable;
  - **M17:** a refusal does not stop the script;
  - **M18:** there is no check that a bundle was written.
- **`--self-test`:**
  - **M19:** versions compared as strings;
  - **M20:** the channel rule dropped;
  - **M21:** two versions tolerated;
  - **M22:** the hash rule dropped;
  - **M23:** an empty archive accepted;
  - **M24:** only the first ABI checked.

**The control behind gap 2 had to be run twice.**
- **The first run was imprecise.** It moved the pins and the floor to 3.44.9
  but left the ceiling at `<3.48.0`. #758's test then went red, but on its
  ceiling rule (the ceiling must be the floor's next minor), not on any floor.
- **The fair downgrade** also moved the ceiling: `'>=3.44.9 <3.45.0'`, every
  pin and the golden script at 3.44.9. On that, **#758's `flutter_pin_test`
  stays GREEN (4/4) and `android_tls_gate_test` goes RED.**

## 8. What this does NOT verify

- That anyone was attacked.
- The live Play Console.
- A physical phone, or Android below 14 (no older emulator image here). The
  `/system/etc/security/cacerts` path is not exercised.
- Whether any host we call chains to an eMudhra root (chains not inspected).
- R2 images and Carto tiles on the device: production has no public salon and
  this build carries no Carto key. Only `api.myweli.com` is exercised.
- A real **AAB** through `release_build.sh`. That needs `origin/main`, the
  Sentry DSN and the Carto key, so it happens at B0.10. The script's path is
  exercised with stubbed builds, and the verifier with the real APK and the
  two real engines.
- **CI's own `apk-size` run.** A PR into #758's branch gets no CI. The first
  Linux run is after the retarget to `main` (§7).
