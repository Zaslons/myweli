# Brand & launch-asset integration (logo · mark · loader · icons · splash)

| | |
|---|---|
| **Requirement** | Launch polish — apply the delivered MyWeli brand identity to every surface |
| **Phase** | Accounts / launch |
| **Status** | **Approved** — phased build (one phase per PR/message) |
| **Decision** | Client branding in the **default/main** source set (permanent base); **pro** added as a **build flavor** that overrides icon/splash (no rework). Logo is always the **wordmark/lockup SVG**, never typed text. |
| **Asset source** | 6 designer bundles (icons · brand · launch · loader v2 · qr · brand-book) — extracted; PDFs archived in `docs/brand/` |

## 1. Goal & scope
Wire the professionally-generated brand kit into all four surfaces — **consumer app**, **pro app**, **admin (Flutter web)**, **Next.js web** — so each carries the MyWeli identity. The system is **pure monochrome**: client = **white mark on `#000000`**, pro = **black mark on `#FAFAFA`**, which matches our tokens exactly (`primary #000`, `surface #FAFAFA`, `secondary #FFF`) → **no token changes**.

**In scope:** favicons/manifest/OG (web + admin), app launcher icons (iOS + Android, client + pro), native splash, brand SVGs (mark/wordmark/lockup + `currentColor` tintable), Lottie loader (all loading states + app-open animation), build flavors for pro.
**Out of scope:** store screenshots (need real in-app screens), the QR sticker (marketing collateral), store-listing copy.

## 2. Decisions
- **Naming / brand text:** the brand is **MyWeli** (capital W). The visible logo is **always the `wordmark`/`lockup` SVG** (vector — tinted via `currentColor` for dark mode), never typed. Only truly text-only spots (`<title>`, SMS body/sender, `alt`/`aria`, store name) use the string **"MyWeli"**.
- **Client = default/main; pro = flavor override.** Installing client into `res/main` + `Runner` AppIcon is the permanent base; the pro flavor overrides only what differs → nothing is thrown away when pro lands.
- **Two distinct loaders (corrected per designer):**
  - **App-open** → the **`loader_v2`** animation (style **`mixed`** — only `mixed` ships an HTML variant, so it's the intended one; `caps` is the alternative). Sequence: **static native splash → `loader_v2` animation** while the app initialises.
  - **In-app loading / refresh / pull-to-refresh / page loads** → the **`mark_loader`**: **standard** (~2.7 s) full-screen, **fast** (~1.2 s) inline/button/list.
- **Light/dark variants:** every asset ships **black** (for light backgrounds) and **white** (for dark backgrounds). The **normal (light) app uses the black variants now**; the **white variants are copied in but reserved for dark mode** (future). Launch-surface exceptions: the **client** icon + splash are intentionally **white-on-black** → their overlaid app-open loader uses the **white** `loader_v2`; **pro** icon + splash are **black-on-#FAFAFA** → black loader.

## 3. Asset → destination map
| Source (bundle) | Destination |
|---|---|
| `app_icons/client/ios/AppIcon.appiconset` | `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset` (replace) |
| `app_icons/client/android/{mipmap-*,drawable-*,values,mipmap-anydpi-v26,playstore}` | `mobile/android/app/src/main/res/` (merge) |
| `app_icons/pro/*` | pro **flavor** dirs (P5) |
| `app_icons/client/web` + `launch/og_image` | `web/public/` + Next metadata |
| `app_icons/pro/web` | `mobile/web/` (admin) |
| `brand_assets/{mark,wordmark,lockup_h,lockup_v}` (black+white) + `launch/vector_currentcolor` | `mobile/assets/brand/` (flutter_svg) + `web/public/brand/` |
| `loader_v2/lottie` — **app-open** (`mixed` + `mixed_white`) | `mobile/assets/lottie/open/` (+ `lottie` pkg) + web splash |
| `brand_assets/mark_loader/lottie` — **in-app** load/refresh (std + fast, +`_white`) | `mobile/assets/lottie/loader/` + web |
| `launch/splash/{client,pro}` | `flutter_native_splash` config (+ dev-dep) |
| `files12/*.pdf` (brand book) | `docs/brand/` ✅ done |

## 4. Phases (one per message; PRs grouped web / mobile)
- **P0 — spec + plan** *(this)*: recommendation, mapping, brand book archived, branch created.
- **P1 — Web branding** ✅ — Next file-convention icons (`app/icon.svg` favicon · `apple-icon.png` · `favicon.ico`) + `app/manifest.ts` (android-chrome/maskable, monochrome theme) + **static branded OG** (`opengraph-image.png` + `.alt.txt`, replacing the dynamic generator); **header renders the lockup SVG**; brand name → **MyWeli** across metadata/jsonld/copy (generated schema untouched); Organization `logo` → raster PNG. Both light + dark brand SVGs staged in `public/brand/`. tsc · lint · 87 unit · 25 e2e green.
- **P2 — Admin (Flutter web) branding** ✅ — `mobile/web/` favicon (SVG + PNG) + apple-touch + `icons/Icon-*` (client white-on-black) + `manifest.json` (name "MyWeli Admin", monochrome `#000` theme) + `index.html` title/description/`theme-color`. Manifest JSON validated; full build verified on the `deploy-admin` workflow (not in PR CI, which doesn't build the admin web).
- **P3 — App brand assets + loaders** ✅ — brand SVGs (mark/wordmark/lockup, black + white + `currentColor`) → `assets/brand`; both Lottie sets → `assets/lottie/{open,loader}`; added `lottie`. New **`BrandLoader`** (the `mark_loader`, std/fast, light/dark) now backs **`LoadingIndicator`** → **every in-app loading/refresh state is on-brand**; the login screen shows the **vertical lockup SVG**. `flutter analyze` 0 · **338 tests** green (Lottie loader verified test-safe). *(Polish 2026-07-02: swept the remaining 26 files' raw `CircularProgressIndicator` → `BrandLoader`/`LoadingIndicator` incl. `AppButton` (white cut on the black primary); determinate upload-progress bars kept as-is; splash holds ~3.8 s to show the open animation. **Pull-to-refresh** also uses the `mark_loader` now — a `BrandRefresh` wrapper over `custom_refresh_indicator`'s `CustomMaterialIndicator` replaced all 13 `RefreshIndicator`s → **loaders fully unified.**)*
- **P4 — Consumer icon + native splash + open animation** ✅ — client `AppIcon.appiconset` (iOS, white-on-black) + Android adaptive mipmaps (`ic_launcher` + round + monochrome + notification `ic_stat`) + manifest `roundIcon`; `flutter_native_splash` generates the native launch screen (**`#FAFAFA`, black mark — light**, to flow seamlessly into the light app; `web: false` so the admin keeps its P2 template); `/splash` plays the **`loader_v2` (`mixed`)** open animation on the light bg → `/home`. iOS `CFBundleDisplayName`/`CFBundleName` + permission strings → **MyWeli**. `flutter analyze` 0 · 338 tests green. Icon/splash visuals verify on a device build. *(Revised 2026-07-02: splash + loader switched black→light per "white = normal app, black = dark mode"; app icon stays white-on-black.)*
- **P5 — Flavors + pro icon/splash** — 🟡 **partial (Android pro icon done; iOS + pro splash = machine playbook §8):** Android `productFlavors` (`consumer` = `com.myweli.app` · `pro` = `com.myweli.pro`) **already existed** → installed the **pro launcher icon** (black-on-`#FAFAFA`) into `android/app/src/pro/res` (consumer keeps the P4 icon in `main/res`) + set launcher names **MyWeli / MyWeli Pro**. **Remaining — needs your Mac + a real build (can't be CI-verified, and blind `project.pbxproj` edits break the build):** pro **native splash** + **iOS flavor schemes**. See §8.

## 5. Security · performance · testing
- **No secrets**; assets are static art only. gitleaks stays green.
- **Performance:** web favicons tiny + cached; OG is a static PNG (no runtime gen); Lottie JSON is small (vector) and the SVGs are vectors → APK/CWV budgets respected; watch APK size after P3–P4.
- **Testing:** P1 — `next build` + web unit/e2e + Lighthouse budgets green; P2 — admin build; P3 — `flutter analyze` 0 + widget test for `BrandLoader`/login; P4–P5 — build succeeds, verified on device/preview. Design-standards **consistency sweep** after P3.

## 6. Rollout
Per-phase commits; web PR (P1–P2) then mobile PR(s) (P3–P5); **refresh `docs/ROADMAP.md`** as phases land; verify web on the preview + app on device. Feature-branch + PR, authored as the user (no Claude attribution).

## 7. Open questions
1. **Text rename scope:** change literal "Myweli" → "MyWeli" in French copy / SMS templates / meta now, or leave until a copy pass? (recommend: switch the visible brand string to **MyWeli**, keep it minimal.)
2. **Pro flavor bundle-id scheme** (e.g. `com.myweli.app` / `com.myweli.pro`) — confirm at P5.
3. **Admin** uses the **client** (dark) branding — confirmed.

## 8. P5 machine playbook — finish the pro flavor (run on your Mac, verify with builds)
The Android `pro` launcher icon is installed. The rest must be done where you can build (Xcode + Gradle); blind `project.pbxproj` edits break the iOS build and can't be CI-verified. Do this with the **mobile store-deploy** work (signing/versioning/listings) — pro isn't in the first launch.

### 8.1 Pro native splash (bg `#FAFAFA`, black mark)
1. Copy `launch_assets/splash/pro/splash_logo*.png` → `mobile/assets/splash/pro/`.
2. Add `mobile/flutter_native_splash-pro.yaml`:
   `color: "#FAFAFA"` · `image: assets/splash/pro/splash_logo.png` · `fullscreen: true` · `web: false` · `android_12:` `{ image: assets/splash/pro/splash_logo_android12.png, color: "#FAFAFA", icon_background_color: "#FAFAFA" }`.
3. `dart run flutter_native_splash:create --flavors pro` (consumer's P4 splash is unaffected).

### 8.2 iOS flavor schemes (Xcode — `open ios/Runner.xcworkspace`)
1. **Build configs:** duplicate Debug/Release/Profile → `*-consumer` and `*-pro` (Project ▸ Info ▸ Configurations).
2. **Bundle IDs:** `PRODUCT_BUNDLE_IDENTIFIER` = `com.myweli.app` on `-consumer`, `com.myweli.pro` on `-pro` (Runner ▸ Build Settings, per config).
3. **Schemes:** create shared schemes **`consumer`** and **`pro`**, each mapped to its configs (Product ▸ Scheme ▸ Manage Schemes).
4. **Pro app icon:** add a second icon set `AppIcon-pro` to `Assets.xcassets` from `pro/ios/AppIcon.appiconset`; set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-pro` on `-pro` (consumer stays `AppIcon`).
5. **Display name:** `Bundle display name` = `MyWeli` / `MyWeli Pro` per config.

### 8.3 Verify with real builds
`flutter run --flavor consumer -t lib/main.dart` and `flutter run --flavor pro -t lib/main_pro.dart` (iOS + Android) → two apps with distinct icons/names/bundle IDs/splashes; then `flutter build appbundle`/`ipa --flavor …` succeed.
