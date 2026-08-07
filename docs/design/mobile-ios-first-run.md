# iOS — building it, and running it

| | |
|---|---|
| **Module** | mobile (iOS), cross-cutting: CI, the release path |
| **Status** | **Both flavours build and run** — 2026-08-07 |
| **Related** | [mobile-ios-flavours.md](mobile-ios-flavours.md) · [push-notifications-app.md](push-notifications-app.md) · [app-auth-social.md](app-auth-social.md) · [mobile-flutter-3.44-upgrade.md](mobile-flutter-3.44-upgrade.md) |

## 1. What is actually unverified

**Correcting the premise this slice was scoped on.** iOS *has* been built —
`build/ios/Debug-consumer-iphoneos/` and `Debug-pro-iphoneos/` are dated
2026-08-04, so the flavour split compiles for device. The claim "never compiled"
was wrong and is recorded here so it is not repeated.

What is genuinely unverified is everything **after** the compile, plus
everything the last three days changed:

| Written | Compiled? | Run? |
|---|---|---|
| Flavour split, schemes, bundle ids (#317) | ✅ 08-04 | ❔ |
| `GoogleService-Info.plist` copy phase (#324) | ✅ 08-04 | ❌ — nothing has read the plist from a bundle |
| APNs entitlements wiring (#328) | ✅ 08-04 | ❌ — no token has ever been issued |
| Apple Sign-In default-on (#330) | ❌ — after the last build | ❌ |
| Pro Apple **registration** (#330) | ❌ | ❌ — the backend branch has never been called |
| Flutter 3.44.9 (#332) | ❌ | ❌ |

The last three rows postdate every iOS build that exists. **CI does not build
iOS at all**, so nothing has looked at them.

## 2. What the first build after the upgrade found

**Flutter 3.44 adds Swift Package Manager integration on its own**, and it
failed — 964 s spent, then `Could not resolve package dependencies`, with seven
Firebase binary targets each reporting `already exists in file system` against
`~/Library/Caches/org.swift.swiftpm/artifacts`.

Only **two** artifacts were actually present in that cache when inspected
afterwards, against seven named in the error: the signature of an interrupted
download leaving partial entries behind, not of a genuine conflict.

This is a **consequence of the 3.44.9 upgrade**, not a pre-existing fault: 3.38.6
did not attempt SPM integration. Flutter's own message calls the feature
experimental while also stating that *"disabling Swift Package Manager will not
be allowed in a future version"* — so the fix is to make it work, and disabling
it is a stopgap to be recorded rather than a resolution.

It is also a **local-machine** fault (a user-level cache), which is exactly the
kind that a repo cannot hold and that the next machine hits from scratch —
hence writing it down here.

## 3. Order of work

1. Clear the SwiftPM artifact cache; rebuild. If SPM integration still fails,
   disable it explicitly, record it as a follow-up, and continue — the goal is
   the runtime evidence, not the packaging debate.
2. Run the **consumer** flavour on the simulator. Verify what only a run can:
   - the Apple button renders at all (it is iOS-gated, so no test or golden has
     ever drawn it — SYSTEM.md §21 row 87);
   - Google and Apple sit as one family, matching `components_buttons.png`;
   - `GoogleService-Info.plist` is **in the bundle** and Firebase initialises.
3. Run the **pro** flavour. Same, plus « S'inscrire avec Apple » — new client
   code against a register route whose Apple branch has never been called.
4. Push on a **real device** (the simulator cannot receive APNs): confirm a
   token is issued at all, which is what #328's entitlements exist for.
5. Decide on a CI iOS job — at minimum `build ios --no-codesign`, so the next
   framework bump cannot silently break the platform CI has never looked at.

## 4. What a simulator cannot answer

Stated up front so no result is over-claimed:

- **APNs.** The simulator has no push token. Anything about #328 needs hardware.
- **Sign in with Apple** works in the simulator only against a signed-in Apple
  account, and the credential it returns is not the production path.
- **Release signing / the archive.** A debug simulator build proves nothing
  about the store submission.

## 5. What the run proved

Both flavours built for the simulator and were driven by hand.

| Claim | Evidence |
|---|---|
| The Apple button renders on iOS | **Seen, for the first time in the product's history.** Consumer login, pro login, pro register — black, marked, matching Google beside it and matching `components_buttons.png` |
| It is wired, not merely drawn | Tapping it ran `_handleApple` through to the mandatory contact-phone step (mock backend) |
| Pro Apple **registration** exists | « S'inscrire avec Apple » renders on the register screen — the control that was `onPressed: () {}` |
| `GoogleService-Info.plist` reaches the bundle | Present in both builds — and **each flavour got its own**: `com.myweli.app` for consumer, `com.myweli.pro` for pro, matching each app's own bundle id. The failure this rules out is shipping one Firebase project to both apps |
| The flavour split is real at runtime | `com.myweli.app`/`MyWeli` vs `com.myweli.pro`/`MyWeli Pro` |

## 6. Three things the upgrade changed under iOS

**(a) Almost the entire dependency graph moved from CocoaPods to SPM.**
`Podfile.lock` collapsed from ~150 lines to ~12: only `add_2_calendar` and
`flutter_image_compress_common` remain pods, being the two Flutter names as not
supporting SPM. Everything else — Firebase, GoogleSignIn, AppAuth,
DKImagePickerController — is now a Swift package.

**(b) `[CP] Copy Pods Resources` disappeared from the build phases**, which
looks alarming and is correct: the pods that owned resource bundles are no
longer pods. **Verified rather than assumed** — the built `.app` contains
`DKImagePickerController_DKImagePickerController.bundle`,
`DKPhotoGallery_…`, `GoogleSignIn_…` and the four Firebase bundles. SPM embeds
its own resources. Nothing was lost.

**(c) Flutter migrated the app to the UIScene lifecycle** on its own, rewriting
`Info.plist` and moving plugin registration in `AppDelegate.swift` from
`didFinishLaunchingWithOptions` to `didInitializeImplicitFlutterEngine`. Every
key survived the rewrite — `UIBackgroundModes: remote-notification`,
`GIDClientID`, `CFBundleURLTypes`, all usage descriptions — but it **dropped a
comment**, which is restored. The registration now happens later in launch;
whether that affects `firebase_messaging`'s AppDelegate swizzling for a
notification that *launches* the app is **not answerable on a simulator** and
is carried into §7.

## 7. Open questions

- **Does the later plugin registration affect a launch-from-notification?**
  UIScene moved registration out of `didFinishLaunchingWithOptions`.
  `firebase_messaging` swizzles the app delegate, and a push that cold-launches
  the app is the case where timing could matter. Needs a device.
- **APNs remains entirely unverified.** The simulator issues no push token, so
  #328's entitlements are still unproven — the single largest remaining gap.
- Does the RunnerTests xcconfig gap matter? `pod install` warns on all six
  configurations that it could not set the base configuration for
  **RunnerTests**, because `setup_flavours.rb` points that target at
  `Flutter/<name>.xcconfig`, which includes `Pods-Runner` but not
  `Pods-RunnerTests`. Nothing runs those native tests today, so this is a
  latent break rather than a live one — but the script's own comment claims the
  test target resolves, and it does not.
