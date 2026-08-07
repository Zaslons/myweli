# Flutter 3.38.6 → 3.44.9

| | |
|---|---|
| **Module** | toolchain (cross-cutting: `mobile/`, CI, the golden baseline) |
| **Status** | in progress — 2026-08-07 |
| **Trigger** | dependabot #300 and #302 are unmergeable, and `pubspec.lock` drifted |
| **Related** | [SYSTEM.md §20.1](SYSTEM.md) (goldens), [#331](https://github.com/Zaslons/myweli/pull/331) (the lockfile fix this supersedes) |

## 1. Why now

Three separate symptoms turned out to be one cause.

**(a) Two dependabot PRs cannot merge.** Both fail at `Install dependencies`,
before a line compiles:

- **#300** — `sign_in_with_apple` 8.1.0 requires Dart `^3.11.0`; we ship 3.10.7.
- **#302** — `flutter_native_splash` 2.4.8 requires `meta ^1.18.0`; the
  `flutter_test` bundled with our SDK pins `meta 1.17.0`, so version solving
  fails outright.

**(b) The lockfile drifted.** #304 landed a `pubspec.lock` asking for
`meta 1.18.0`, which our SDK cannot honour. Nothing failed, because `pub get`
silently re-resolves and rewrites the file — so CI was green against a lockfile
that was not the one in git. [#331](https://github.com/Zaslons/myweli/pull/331)
restored it; this upgrade removes the reason it happened. Dependabot builds its
lockfiles with a current Flutter, so **every future bump reopens that gap until
we move**.

**(c) 73 packages are held back** by the SDK floor.

The common cause: `meta 1.18.0` arrives in **Flutter 3.44.0**, and Dart 3.11
arrives in **3.41.0**. Measured, not inferred:

| Flutter | Dart | `meta` |
|---|---|---|
| 3.38.6 (current) | 3.10.7 | 1.17.0 |
| 3.41.9 | 3.11.5 | 1.17.0 |
| 3.44.0 | 3.12.0 | **1.18.0** |
| 3.44.9 (stable) | 3.12.2 | **1.18.0** |

So **3.44.0 is the floor that unblocks both PRs**, and 3.44.9 is the current
stable.

## 2. Decision — target 3.44.9

Latest stable, nine patch releases ahead of the floor. The floor (3.44.0) was
considered and rejected: it buys one thing (see §3) at the cost of knowingly
shipping nine releases of fixed bugs.

**Not in scope: the backend.** `backend/pubspec.yaml` declares `sdk: ^3.10.0`
and CI pins Dart `3.10.7` through `dart-lang/setup-dart`, independent of
Flutter. It keeps working untouched, and moving it is a separate decision with
its own blast radius. This PR does not touch it.

## 3. The one thing 3.44.9 costs, stated plainly

`tool/update_goldens.sh` regenerates the baseline inside
`ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION}`. That registry publishes
**3.44.0 but not 3.44.9** (verified against the tag list: the 3.44 series stops
at `.0`, while 3.41 goes to `.9` — they lag, they do not skip).

The script's own comment states the invariant it exists to hold:

> Must match `.github/workflows/ci.yml` … If CI moves, move this in the same PR
> or the baseline silently rots.

Pointing it at a *different* version than CI is exactly the failure that
comment forbids — and exactly the class of defect this repo keeps finding, where
a tool reports success while measuring the wrong thing. Rasterization is
unlikely to move across a patch release, but "unlikely" is not the standard for
a byte-exact baseline.

**Resolution:** the script *verifies the image exists* and, when it does not,
fails with instructions rather than silently substituting a near-miss. The
authoritative path is unaffected — `goldens.yml` uses
`subosito/flutter-action`, which installs any published version, and that is
the path actually used to regenerate today's baseline. When cirruslabs
publishes 3.44.9, the script starts working again with no change.

## 4. Scope

| # | Change | Files |
|---|---|---|
| 1 | Local SDK → 3.44.9 | developer machine (not versioned) |
| 2 | CI pins | `ci.yml:36`, `ci.yml:471`, `goldens.yml:46`, `deploy-admin.yml:32` |
| 3 | Golden script pin + image guard | `tool/update_goldens.sh` |
| 4 | SDK constraints | `mobile/pubspec.yaml` (`sdk`, `flutter`, and the comment block that argues for the old floor) |
| 5 | Close #300 / #302 here | `sign_in_with_apple` ^8.1.0, `flutter_native_splash` ^2.4.8 |
| 6 | Breaking-change fixes | whatever `flutter analyze` and `flutter test` name |
| 7 | Golden baseline | regenerated on Linux, **every changed PNG inspected** |
| 8 | Docs | SYSTEM.md §20.1's version claim; specs asserting "verified against 3.38.6" |

**Explicitly out of scope:** the 73 other outdated packages. The SDK move is
already a wide diff; sweeping dependencies in the same PR would make a
regression impossible to attribute. Dependabot will re-propose them, and they
will resolve once the floor moves.

## 5. Risk, and what actually catches it

Six minor framework versions. The honest position is that **`analyze` and the
test suite catch API breaks, and only the goldens catch rendering drift** — and
rendering drift is the likely outcome, since Material and text layout move
between minors.

| Risk | What catches it | Residual |
|---|---|---|
| Removed/renamed APIs | `flutter analyze` = 0 | none — it is a compile error |
| Behaviour change under test | `flutter test` at **+1288 ~46** | tests only cover what they cover |
| **Rendering drift** | the 17 goldens, regenerated and **looked at** | this is the real work of the PR |
| Deprecation warnings | `analyze` (0 issues, not 0 errors) | none |
| Android/iOS build | `Mobile — APK size` job; iOS unverified as always | iOS is not built in CI |
| Dependency re-resolution | `pub get` + full suite | a transitive bump could change behaviour silently |

**The goldens are not a formality here.** A version bump that moves text metrics
will change most of the 17 PNGs, and a diff that large is where a real
regression hides. Each changed image gets looked at, and anything that is not
attributable to rasterization gets investigated rather than accepted.

**§21 rows 23/24 remain true** — the dashboard and journal goldens still read
the machine clock; unchanged by this work.

## 6. Order of work

1. Local SDK → 3.44.9; `flutter --version` confirms.
2. Move every pin (§4 rows 2–4) — **in one commit**, so no window exists where
   the script and CI disagree.
3. Raise the dependency floors that #300/#302 wanted; `flutter pub get`.
4. `flutter analyze` → 0. Fix what it names.
5. `flutter test` → the +1288 ~46 baseline, goldens skipping on macOS as always.
6. Push; regenerate goldens through `goldens.yml`; download, **inspect**, commit.
7. Full CI green, including `Mobile — APK size`.
8. Docs + ROADMAP; close #300/#302 as superseded.

## 7. The two open questions, answered

- **Does the APK grow? Yes, by 0.53 MB.** Measured on the same job, same
  flavour, one PR apart: **22.68 MB → 23.21 MB** (+2.3%), against the 30 MB
  budget (ROADMAP §6). Recorded rather than waved through, because it is the
  kind of number that only ever moves one way: six framework minors cost half a
  megabyte, and the budget has **6.8 MB** of headroom left. Nothing to act on
  now; worth knowing before the next three upgrades.
- **Do the 3.41 → 3.44 Material defaults move our theme? No.** The goldens
  answer it, not a prediction: across all 46, **37 pixels** differ by more than
  Δ100 and **8** shift colour, with 12 images pixel-identical and no image
  changing size. `app_theme.dart` overrides heavily enough that the defaults
  that moved are unreachable from our surfaces.

## 8. What this did NOT verify

- **iOS is not built in CI** and was not built here. The upgrade is unproven on
  that platform, exactly as every prior change has been.
- **Rendering on a device.** The goldens prove the framework draws the same
  bytes on Linux; they say nothing about an actual phone.
- **The 73 → 67 still-outdated packages.** Deliberately out of scope (§4).
