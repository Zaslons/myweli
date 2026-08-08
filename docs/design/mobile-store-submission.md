# Store submission — release signing and the prep that precedes it

| | |
|---|---|
| **Module** | release engineering (`mobile/ios`, `mobile/android`) |
| **Status** | Repo side **done**; the account side is a runbook (§5) |
| **Related** | [mobile-ios-first-run.md](mobile-ios-first-run.md) · [mobile-ios-flavours.md](mobile-ios-flavours.md) · [DEPLOYMENT.md](../DEPLOYMENT.md) |

## 1. Three things made submission impossible

Not "not yet done" — **impossible**, each with a failure that arrives late and
reads as something else.

**(a) Android release builds were signed with the DEBUG key.** The Flutter
template's `signingConfig = signingConfigs.getByName("debug")` was still there,
TODO and all. Play rejects a debug-signed bundle at upload. Nothing in the build
says so; you find out after the upload.

**(b) The app had no privacy manifest.** Every third-party SDK in the tree ships
a `PrivacyInfo.xcprivacy` — eighteen of them. The app itself had none. Apple's
enforcement is an email after upload, then a rejection.

**(c) No `ITSAppUsesNonExemptEncryption`.** Every single upload stops to ask
about export compliance, and the answer depends on whoever happens to be doing
the upload rather than on the repo.

## 2. Android signing — and the rule it encodes

`key.properties` is gitignored (it already was; nothing read it). The release
build now uses the upload key when that file is present.

**When it is absent the build is left UNSIGNED, deliberately.** The obvious
alternative — fall back to the debug key so `flutter run --release` keeps
working — is what produced (a): an artifact indistinguishable from a shippable
one that the store rejects. Unsigned fails loudly, at signing time, on the
machine that can still do something about it.

Verified: `flutter build appbundle --flavor consumer --release` succeeds without
`key.properties`, and the resulting `.aab` contains **no** `META-INF/*.RSA` —
unsigned, not debug-signed.

**R8 is deliberately still off.** Enabling `isMinifyEnabled` is right for a Play
release and was reverted out of this slice: its failure mode is runtime-only —
R8 strips a reflectively-reached class and push, or a plugin, stops working in
**release builds only** — and no gate in this repo can see that. Its own slice,
with a device run. Note the Firebase and Flutter plugin keeps will be needed.

## 3. The privacy manifest, and why it declares nothing

`ios/Runner/PrivacyInfo.xcprivacy`, wired into the Runner target's **Resources**
build phase by `setup_flavours.rb` — a manifest that is not copied into the
bundle is invisible to review, and that failure is silent.

`NSPrivacyAccessedAPITypes` is **empty**, which was measured rather than copied.
The four categories a Flutter app usually declares:

| Category | Who covers it |
|---|---|
| UserDefaults | `shared_preferences_foundation` ships its own manifest |
| SQLite | `sqflite_darwin` ships its own |
| File timestamp | would be ours (`flutter_cache_manager` is pure Dart, so it compiles into *our* binary) — but it decides freshness from its own sqflite `validTill`, not `File.lastModified()` |
| Disk space | nothing in our Dart or in the cache manager queries it |

Over-declaring is not free: Apple asks for the APIs actually called, and a
declaration no caller can be pointed at is one we cannot defend. **If a future
dependency reaches one of these from Dart, add it with the caller named.**

## 4. Data collection — App Store Connect is the source of truth

`NSPrivacyCollectedDataTypes` is **absent by owner decision**. The App Store
Connect questionnaire is the authoritative declaration; a second copy in the
repo that drifts from it is worse than one copy. Draft answers, derived from
what the code actually sends, for §5 step 6:

| Data | Collected? | Linked to identity | Used for tracking | Where in the code |
|---|---|---|---|---|
| Email address | Yes | Yes | No | auth (Google/Apple/OTP) |
| Name | Yes | Yes | No | Google/Apple credential |
| Phone number | Yes | Yes | No | mandatory contact phone |
| User ID | Yes | Yes | No | account id |
| Precise location | Yes | Yes | No | « Près de moi » (`Geolocator.getCurrentPosition`) |
| Photos | Yes | Yes | No | salon gallery, review photos, deposit screenshot |
| Purchase history | **No** | — | — | MyWeli holds no funds (PRD OQ-1) |
| Usage / diagnostics | **No** | — | — | no analytics or crash SDK |

**Tracking is `false` across the board** and the manifest says so: there is no
ad, analytics or attribution SDK in the tree. Confirm each row before answering
— this table is derived from code, not from a lawyer.

## 5. Runbook — the account side (owner only)

These need the Apple/Google accounts. They are not things this repo can do, and
nothing here should be handed credentials.

1. **Android upload key.** `keytool -genkey -v -keystore ~/myweli-upload.jks
   -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Then create
   `mobile/android/key.properties` with `storeFile`, `storePassword`,
   `keyAlias`, `keyPassword`. **Never commit it** (already gitignored), and back
   the keystore up — losing it means losing the ability to update the listing.
2. **Play Console** — create both apps (`com.myweli.app`, `com.myweli.pro`),
   enrol in Play App Signing, upload the `.aab`.
3. **Apple certificates and profiles** — Distribution certificate, App Store
   provisioning profiles for both bundle ids, with the **Push Notifications**
   capability enabled (the entitlement is already in the project; the profile
   has to allow it or the signed build fails).
4. **App Store Connect** — create both app records; the bundle ids must match
   `com.myweli.app` / `com.myweli.pro` exactly.
5. **Archive and upload** — `flutter build ipa --flavor consumer --release`
   (without `--no-codesign`) once signing exists, then Xcode Organizer or
   `xcrun altool`.
6. **The privacy questionnaire** — §4's table.
7. **Sign in with Apple** — already working (2026-08-07). Rule **4.8** requires
   it wherever another third-party provider ships, which is why
   `FeatureFlags.appleSignIn` defaults on.

## 6. What this did NOT verify

- **Signed builds.** The archive was produced with `--no-codesign`, so the
  production `aps-environment` is *configured* (Release → `RunnerRelease.entitlements`,
  measured as 3 configurations production / 6 development) but not *baked*. A
  production APNs send to a sandbox token is silently dropped, and that is the
  failure that looks like nothing happening.
- **The upload itself**, and everything App Store Connect / Play Console
  validates on receipt.
- **R8**, per §2.
- **Store assets** — screenshots, descriptions, age rating. Not started.

## 7. Verified here

| Claim | Evidence |
|---|---|
| The iOS release archive builds | `Runner.xcarchive`, 217.6 MB — **the first release archive this project has produced** |
| The Android release bundle builds | `app-consumer-release.aab`, 64.0 MB |
| It is not silently debug-signed | no `META-INF/*.RSA` in the `.aab` |
| The privacy manifest reaches the bundle | present in `Runner.app/` inside the archive |
| Export compliance is declared | `ITSAppUsesNonExemptEncryption = false` in the built `Info.plist` |
| Identity is right | `com.myweli.app` / « MyWeli » in the built plist |
