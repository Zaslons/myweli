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

- **APNs.** ~~The simulator has no push token.~~ **This was wrong** — see §5b. On Apple silicon with macOS 13+ the simulator registers with APNs for real and is issued a token, which is how #328 was finally checked. What a simulator still cannot answer is the **production** APNs environment: a debug build is signed `development` and gets a SANDBOX token, so a production FCM send to it is dropped.
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

## 5b. APNs — measured, and the section above was wrong about it

§4 said the simulator has no push token, and §7 called APNs "the single largest
remaining gap". Both were inherited from older tooling. On **Apple silicon with
macOS 13+**, the simulator registers with APNs for real.

Driven by `mobile/tool/apns_probe.dart` — the app itself only asks for
permission after a login, so reaching the token through the UI needs live
credentials it does not have. The probe drives the **same** adapter
(`FcmPushNotificationService`, real Firebase, nothing mocked). On an iPhone 13
mini simulator, iOS 26.5:

| Step | Result |
|---|---|
| `Firebase.initializeApp()` | `true` — the per-flavour `GoogleService-Info.plist` is read from the bundle |
| Permission prompt | rendered, titled « **MyWeli** » |
| After granting | `granted` |
| **`getAPNSToken()`** | **a real 160-character token** — #328's `aps-environment` entitlement works |
| **FCM token** | **issued** — Firebase accepted the APNs token and minted its own |

That is the entitlement chain proven end to end on the client: entitlement →
APNs registration → token → Firebase → FCM token. It had never been observed.

**Delivery and handling**, with a payload mirroring `booking_notifier`'s
`data{route, providerId}` exactly as FCM would deliver it
(`xcrun simctl push`, app backgrounded):

| Claim | Evidence |
|---|---|
| The notification renders | Banner with the brand icon, « Rendez-vous confirmé » / « Barber King a confirmé votre rendez-vous. » |
| A tap launches the app | It did, from the home screen |
| The tap **routes** to the deep link | **NOT observed, and not claimed.** The app landed on Accueil. That is what the design specifies for an unauthenticated tap — `push_message_handler.dart:72-75` buffers the payload and replays it after auth, so the splash/login redirect cannot eat it — but with no session there is no way to tell a correct buffer from a silent drop from the outside. The buffering logic is unit-tested; the integration is not. |

**Still unproven, precisely:**

- The **server → APNs leg**. `simctl push` injects locally; it does not exercise
  FCM's own delivery. Closing that needs the service-account credentials, which
  live in Secret Manager and not on a developer machine.
- **Production APNs.** A debug build is signed `development` and holds a sandbox
  token. The Release/production split `setup_flavours.rb` writes is still
  untested.
- **Routing on a real tap with a session**, per the table above.

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

## 6b. A stale generated file will tell you the deployment target regressed

It did not. After #333 raised the target to 15.0, a later build still failed
with *"the package product 'firebase-core' requires minimum platform version
15.0 … but this target supports 13.0"* while all **27** entries in
`project.pbxproj` read 15.0.

The 13.0 lives in `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`,
which Flutter **generates** — and does not regenerate when the target moves. It
was written during an earlier build, back when the project really did say 13.0.
The directory is gitignored, so this is a stale local artifact and never a repo
defect, which is precisely what makes the error message misleading: the project
is right and the build still fails.

    rm -rf mobile/ios/Flutter/ephemeral    # or `flutter clean`

Worth knowing before anyone "re-fixes" a deployment target that was never broken.

## 7. Open questions

- **Does the later plugin registration affect a launch-from-notification?**
  UIScene moved registration out of `didFinishLaunchingWithOptions`.
  `firebase_messaging` swizzles the app delegate, and a push that cold-launches
  the app is the case where timing could matter. Needs a device.
- ~~**APNs remains entirely unverified.**~~ **Closed on the client — see §5b.**
  The simulator DOES issue a push token on Apple silicon, and #328's
  entitlements are proven: real APNs token, real FCM token. What remains is
  narrower and stated there — the server→APNs leg, the production environment,
  and routing on an authenticated tap.
- Does the RunnerTests xcconfig gap matter? `pod install` warns on all six
  configurations that it could not set the base configuration for
  **RunnerTests**, because `setup_flavours.rb` points that target at
  `Flutter/<name>.xcconfig`, which includes `Pods-Runner` but not
  `Pods-RunnerTests`. Nothing runs those native tests today, so this is a
  latent break rather than a live one — but the script's own comment claims the
  test target resolves, and it does not.
