# iOS flavours — two apps from one codebase, matching Android

> Module: **mobile / release engineering**. Unblocks Sign in with Apple
> registration (`APPLE_CLIENT_IDS`) and the two App Store records.
> Prior art: `mobile/android/app/build.gradle.kts` (the flavour split this
> mirrors), [`DEPLOYMENT.md`](../DEPLOYMENT.md) §B4.

## 1. The problem

MyWeli ships **two apps from one codebase** (PRD §427) — consumer
(`lib/main.dart`) and pro (`lib/main_pro.dart`). Android encodes that properly:

```kotlin
create("consumer") { applicationId = "com.myweli.app"; app_name = "MyWeli" }
create("pro")      { applicationId = "com.myweli.pro"; app_name = "MyWeli Pro" }
```

**iOS has none of it.** The Xcode project is stock single-flavour:

- one bundle ID, `com.sadreddine.myweli.pro` — a personal-namespace identifier
  that matches neither Android convention;
- it says `.pro` while `Info.plist` says `CFBundleDisplayName = MyWeli`, the
  *consumer* name, so the one configuration that exists is internally
  contradictory;
- one scheme (`Runner`), three configurations (`Debug`/`Profile`/`Release`);
- **no way to build the consumer app for iOS at all.**

### Why it is being fixed now, ahead of anything else

Sign in with Apple puts a **different value in the ID token's `aud` depending on
the platform**: for a native iOS app it is the **bundle ID**, for web/Android it
is the Services ID. `APPLE_CLIENT_IDS` is the allowlist the backend checks
against (`id_token_verifier.dart:94`), so **the bundle IDs are an input to Apple
portal registration**, and an App ID in that portal is effectively permanent
once an app ships under it. Registering `com.sadreddine.myweli.pro` would bake a
placeholder into the App Store record and the auth allowlist at the same time.

This is also a launch blocker in its own right: two App Store records need two
bundle IDs.

## 2. Decision

| | Android (existing) | iOS (this change) |
|---|---|---|
| consumer | `com.myweli.app` | **`com.myweli.app`** |
| pro | `com.myweli.pro` | **`com.myweli.pro`** |
| consumer name | MyWeli | MyWeli |
| pro name | MyWeli Pro | MyWeli Pro |

Identical identifiers across platforms. `com.sadreddine.myweli.pro` is retired
and was never published, so nothing depends on it.

**`main_admin.dart` gets no flavour.** Admin is Flutter *Web* only — it is not a
store app and does not need a bundle ID.

## 3. Design

Flutter's iOS flavour support is a naming contract, not a feature flag: a scheme
named after the flavour, and build configurations named `<Action>-<flavour>`.

### 3.1 Build configurations — six, replacing nothing

Added alongside the existing three, which stay so a plain `flutter build ios`
(and `flutter test`) keeps working:

```
Debug-consumer    Profile-consumer    Release-consumer
Debug-pro         Profile-pro         Release-pro
```

Each is cloned from its base (`Debug`/`Profile`/`Release`) so it inherits every
setting **and** the `baseConfigurationReference` — the Flutter and Pods xcconfig
chain. Cloning rather than authoring from scratch is the point: a hand-written
configuration silently loses whatever Flutter adds next release.

### 3.2 The display name comes from a build setting

`Info.plist` currently hard-codes `MyWeli`. It becomes `$(APP_DISPLAY_NAME)`,
with the value set per configuration — the exact shape of Android's
`resValue("string", "app_name", …)`.

### 3.3 Schemes

Two shared schemes, `consumer` and `pro`, each wiring Run/Test/Analyze →
`Debug-<flavour>`, Profile → `Profile-<flavour>`, Archive →
`Release-<flavour>`. Shared (`xcshareddata`), so they are committed and every
machine and CI runner sees them.

`Runner.xcscheme` stays for the flavourless path.

### 3.4 Editing the project with `xcodeproj`, not by hand

`project.pbxproj` is a UUID-keyed object graph; a hand edit that looks right can
produce a project Xcode opens but `xcodebuild` rejects. The change is scripted
with the **`xcodeproj` gem** — the same library CocoaPods itself uses — kept at
`mobile/ios/tool/setup_flavours.rb` so it is re-runnable and reviewable rather
than a one-off mutation nobody can audit.

**`pod install` must follow.** CocoaPods generates one xcconfig per build
configuration; new configurations without them fail with *"Unable to open base
configuration reference file"*. The script does not hide this — it prints the
next command.

## 4. Verification

**CI does not build iOS at all** — the mobile job is Android-only (`ci.yml`,
`Mobile — APK size`). So this cannot be proven in CI and is verified locally,
and that fact is recorded here rather than left implicit:

- `xcodebuild -list` shows both schemes and all nine configurations.
- `flutter build ios --flavor consumer --no-codesign` and `--flavor pro`
  both succeed. `--no-codesign` keeps it runnable without certificates.
- The built `Info.plist` of each carries the right
  `CFBundleIdentifier` + `CFBundleDisplayName` — asserted on the **build
  output**, not the source, because that is what the store and Apple's `aud`
  actually see.

## 5. What this unblocks

1. Apple portal: two App IDs (`com.myweli.app`, `com.myweli.pro`) + one Services
   ID → `APPLE_CLIENT_IDS`.
2. Firebase: two iOS apps registered, two `GoogleService-Info.plist`
   (mirroring §B4's two `google-services.json`, which are **also still missing**
   — `mobile/` has no Firebase client config for any platform, so push is unwired
   client-side regardless of the FCM server secrets).
   *Done (recorded 2026-09-24): `mobile/ios/config/{consumer,pro}/GoogleService-Info.plist`
   and both `google-services.json` exist, and the signed Pro IPA of
   2026-08-29 carries the `com.myweli.pro` config (project `myweli`). Whether
   the APNs auth key is uploaded to Firebase is still unrecorded.*
3. Two App Store Connect records. *(2026-09-24: the Pro record is unverified —
   [app-store-forms.md](app-store-forms.md) §3.)*

## 5.1 APNs entitlements (added with the push work)

`Runner.entitlements` declared `aps-environment` and had **zero**
`CODE_SIGN_ENTITLEMENTS` references — for months. The built app therefore
carried no push entitlement, iOS issued no APNs token, and every bit of
Apple/Firebase configuration would have looked correct while push stayed dead.

Now wired per configuration by the same script:

| Configurations | File | `aps-environment` |
|---|---|---|
| `Debug*`, `Profile*` | `Runner/Runner.entitlements` | `development` |
| `Release*` | `Runner/RunnerRelease.entitlements` | `production` |

The split is not cosmetic. A build signed `development` receives a **sandbox**
APNs token, and a production FCM send to it is silently dropped — the same class
of silent failure as the auth bug it sits next to.

Verified through `xcodebuild -showBuildSettings`, not just the project file:
`Debug-consumer` → development, `Release-pro` → production.

**Still owner-side:** the App IDs in the Apple portal need the **Push
Notifications** capability enabled. The earlier registration only ticked Sign in
with Apple, so a provisioning profile will not carry APNs until that is added
for `com.myweli.app` and `com.myweli.pro`. *Done for `com.myweli.pro`
(recorded 2026-09-24): the Xcode-managed App Store profile in the signed IPA
of 2026-08-29 grants `aps-environment = production` and Sign in with Apple, and
the entitlement is baked into the signed binary.*

## 6. Open

- **Signing** is untouched — no team, no provisioning profiles. Deliberate:
  those are account-bound and belong to the owner, and `--no-codesign` proves
  the project without them. *Since done (recorded 2026-09-24): automatic
  signing with team 5VWKJD956A; a signed Pro IPA was exported on 2026-08-29.*
- **Launcher icons per flavour** are not done here (§B4 item 3 territory). Both
  flavours currently share the default asset. *Since done (recorded
  2026-09-24): Pro builds with `AppIcon-pro` — all 13 PNGs present, the 1024
  marketing icon without alpha (checked on the asset set with `sips`) — and
  the signed IPA carries it.*
- *Added 2026-09-24:* `setup_flavours.rb` now also writes, per flavour, the
  **device family** (Pro `1`, iPhone-only; consumer `"1,2"`) and the three
  **purpose strings** (location, camera, photos) as build settings read by
  `Info.plist`, pinned by `mobile/test/infra/ios_store_readiness_test.dart` —
  [app-store-forms.md](app-store-forms.md) §1.
