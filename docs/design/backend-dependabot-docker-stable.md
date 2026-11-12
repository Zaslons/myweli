# Backend — Dependabot proposes only stable `dart` tags for the build image

| | |
|---|---|
| **Status** | **Merged 2026-11-12** (`9ff96905`, #767). Read back on GitHub the same day (§7): the first run on the merged config loaded the nine ranges, and proposed no beta while the `latest` heuristic was still broken. #764 closed by Dependabot. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-12 |
| **PRD ref / phase** | Security, cross-cutting (CI / supply chain) · V1 |
| **ROADMAP entry** | [2026-11-12-dependabot-docker-stable.md](../roadmap/entries/2026-11-12-dependabot-docker-stable.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails |
| **Governs** | `.github/dependabot.yml` (the `docker` entry's `ignore`) · `backend/test/infra/dart_sdk_pin_test.dart` (group « Dependabot proposes stable dart tags only ») · `tool/dependabot_docker_ignore_probe.rb` |
| **Extends** | [backend-dart-sdk-pin.md](backend-dart-sdk-pin.md) §5 |

Each claim is marked **read** (observed, and how) or **inferred** (and from
what). Nothing was changed in the cloud, on GitHub or on Docker Hub. #764 was
left as it is.

## 1. Goal & scope

**Goal.** The weekly Dependabot `docker` run on `/backend` proposes a new
**stable** Dart for `backend/Dockerfile` and never a beta. A guard fails a PR
that removes or weakens that filter.

**In scope.** An `ignore` rule in `.github/dependabot.yml`. A guard in
`dart_sdk_pin_test.dart`. A probe that replays Dependabot's own code on the
real dart tag list.

**Out of scope (§8).** Moving to Dart 3.14.0, which shipped on 2026-11-11.
Closing #764, which is the owner's call. Reporting the Dependabot heuristic
upstream.

## 2. What happened: #764, read

Dependabot opened #764 (`dart` 3.13.7 → `3.15.0-118.1.beta`) at 00:16Z on
2026-11-12, in run
[43125959881](https://github.com/Zaslons/myweli/actions/runs/43125959881). That
was the first `docker` run after #757 added the entry. `dart_sdk_pin_test`
turned it red, as designed. Its job log (`gh run view --log`) says:

- updater image `ghcr.io/dependabot/dependabot-updater-docker:968bde86f9e0…`,
  which is dependabot-core commit `968bde86` (2026-11-11). The four docker
  files read here (`tag`, `version`, `requirement`, `update_checker`) are
  identical to `main` at `b1e19b20` (read; `cmp` and `diff`);
- `"ignore-conditions":[]`;
- « The `latest` tag points to the same image as the `3-sdk` image, so
  dependabot is treating `3.13.7` as a pre-release. »;
- « Latest version is 3.15.0-118.1.beta ».

**The premise was half wrong.** The brief said « the entry has no pre-release
filter ». Dependabot *does* have one for docker. `Tag#looks_like_prerelease?`
matches `beta`, `dev`, `rc` and seven other words. Run locally on dependabot's
own `tag.rb`, it returns `true` for `3.15.0-118.1.beta` and for
`3.14.0-1.0.dev`. **But the filter switched itself off.** The mechanism, read
in `docker/lib/dependabot/docker/update_checker.rb` at `968bde86`:

1. `fetch_latest_tag` → `remove_prereleases(candidates, version_tag)` returns
   every candidate unchanged when `prerelease?(version_tag)`, meaning when the
   **pinned** tag looks like a pre-release.
2. `prerelease?(tag)` is also true when the tag's version is greater than
   `latest_tag`'s. `latest_tag` is the highest *canonical* tag whose digest
   equals `latest`'s.
3. On 2026-11-12, `latest`, `stable`, `3` and `3-sdk` all point to index
   `sha256:754aaf77…`, and `3.14.0` / `3.14` point to `sha256:9ba97850…` (read:
   registry HEAD on each tag). The indexes differ by one platform: `latest`
   still carries a **riscv64 image built from 3.13.7**
   (`org.opencontainers.image.version: 3.13.7-sdk`, created 2026-11-07). The
   3.14.0 riscv64 build has not landed, and the `3.14.0` index has no riscv64
   at all (read: both index manifests). So no `X.Y.Z` tag shares `latest`'s
   digest. The highest canonical tag that does is `3`. The log shows the
   updater HEAD-ing 347 tags on the way down to it.
4. 3.13.7 > 3, so the pinned **stable** is classed as a pre-release. Every
   candidate passes, and the highest by RubyGems order wins.
5. In that order `3.15.0-118.1.beta` is **above** 3.14.0. Docker's
   `Version` turns `-` into `.`, so the tag is compared as
   `3.15.0.118.1.beta`, and RubyGems puts that between 3.15.0 and 3.15.1. A
   beta even sorts above its own release: `3.14.0-315.3.beta` > `3.14.0`.

**When it recurs (inferred from one observation).** It happens whenever a
weekly run falls inside a window where `latest` matches no `X.Y.Z` tag at or
above the pin. The trigger seen here is the riscv64 build lagging a stable
release. How long such windows last, and how often they occur, was not
measured. When the heuristic works, the same code picks **3.14.0** (§4, the
replay). So without a filter we would get a beta PR *intermittently*, not every
week, and the filter is what makes it never happen.

## 3. The options, read

Read in GitHub's
[Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
(source `github/docs`, last changed 2026-11-04 at `92ac1df`) and in
dependabot-core at `968bde86`.

| Option | What the docs and code say | Verdict |
|---|---|---|
| `versioning-strategy` | « Supported by: `bundler`, `cargo`, `composer`, `helm`, `mix`, `npm`, `pip`, `pub`, and `uv` »: not docker. It edits manifest ranges in any case, and filters nothing. | **Not available** |
| A pre-release toggle | None. None of the reference's 22 options (plus the top-level `registries` key) is one. The « versioning tags » table says docker detection is a « heuristic ». | **Does not exist** |
| `ignore.versions` with a glob (`"*beta*"`) | Docker `versions` « use Bundler version syntax »: `Docker::Requirement < Gem::Requirement`. Run on dependabot's own `requirement.rb`, it raises `Gem::Requirement::BadRequirementError: Illformed requirement ["*beta*"]`, which would fail the job. | **Rejected** |
| `ignore.update-types` | `IgnoreCondition` turns `semver-minor` into `">= 3.14.a, < 4"`. The probe shows it ignores the 3.x betas, but also **3.14.0, 3.14.1 and every later stable minor**. Adding `semver-major` (`">= 4.a"`) covers the 4.x betas and blocks every 4.x stable too. Dart ships a patch only for its newest minor: on Docker Hub, no 3.10.x, 3.11.x or 3.12.x tag appears after the next minor's `.0` (read: `last_updated`). 3.13.7's fix was such a patch. So this freezes the pin below every future fix, which defeats the point of the entry. | **Rejected** |
| `ignore.versions: [">= 3.14.0.a"]` | Ignores every stable from 3.14 on (probe). | **Rejected** |
| **`ignore.versions`: one `"> X.Y.0, < X.Y.1"` per minor** | Ignores every Dart pre-release of that minor and no stable (§4). | **Chosen** |

How a `versions` entry is applied (read in code): `filter_ignored` rejects a tag
when `Docker::Requirement.requirements_array(entry).any? { |r|
r.satisfied_by?(Docker::Version.new(tag.numeric_version)) }`, and
`satisfied_by?` tests the tag's `release_part`. That is
`Dependabot::Version.new(numeric_version.tr("-", "."))`, a `Gem::Version`. A
comma inside one entry is AND, and separate entries are OR. Ignore runs **after**
`remove_prereleases`, and it does not depend on the `latest` heuristic.

## 4. Decision: the filter

```yaml
  - package-ecosystem: "docker"
    directory: "/backend"
    ignore:
      - dependency-name: "dart"
        versions:
          - "> 3.13.0, < 3.13.1"
          - "> 3.14.0, < 3.14.1"
          # … one line per minor through 3.20
          - "> 4.0.0, < 4.0.1"
```

**Why one range per minor is enough.** In RubyGems order, a Dart pre-release
`X.Y.0-N.M.word` sits strictly between `X.Y.0` and `X.Y.1` whenever N.M is not
0.0. Dart publishes pre-releases only on a `.0` patch, and stable releases
never have a fourth segment. So `> X.Y.0, < X.Y.1` holds that minor's
pre-releases and no stable release.

**Read on Docker Hub, 2026-11-12** (registry `tags/list`, 512 tags):

- all 117 pre-release tags (without `-sdk`) have the shape `X.Y.0-N.M.beta`;
- none has N = 0, and none sits on a non-zero patch;
- there are no `dev`, `rc` or `alpha` tags;
- the only non-numeric tags are `beta`, `latest`, `stable`, `sdk` and their
  `-sdk` twins. None of these is comparable, so none is ever a candidate.

**Proved with Dependabot's own classes.** `tool/dependabot_docker_ignore_probe.rb`
loads dependabot-core's `docker/{tag,version,requirement}.rb` at `968bde86`
(small stubs stand in for sorbet-runtime and the two common base classes,
which are thin `Gem::Version` / `Gem::Requirement` subclasses). It reads the
filter from `.github/dependabot.yml`. Locally this runs RubyGems 3.0.3; the
updater's RubyGems is newer. The comparison rule used here (canonical
segments, string < number) is the same in both, but that is **inferred**, not
tested on the updater's version.

| Tag | Compared as | Ignored |
|---|---|---|
| `3.15.0-118.1.beta` (#764) | 3.15.0.118.1.beta | **yes** |
| `3.14.0-1.0.dev` | 3.14.0.1.0.dev | **yes** |
| `3.14.0-315.3.beta`, `3.14.0-0.1.dev`, `3.20.0-5.1.beta`, `4.0.0-12.1.beta` | … | **yes** |
| `3.13.7`, `3.13.8`, `3.14`, `3.14.0`, `3.14.1`, `3.15.0`, `3.15.9`, `3.20.0`, `4.0.0`, `4.0.1` | themselves | no |
| `3.14.0-0.0.dev` | 3.14.0.0.0.dev, which sorts *below* 3.14.0 | no: it escapes (below) |
| `3.21.0-5.1.beta` | outside the list | no: it escapes (below) |

**The replay, with a control.** On the 512 real tags, with the pin at 3.13.7,
the probe reruns `fetch_latest_tag`'s filters (comparable → no downgrade →
pre-release → ignore → sort):

| | `latest` heuristic broken (as logged) | heuristic working |
|---|---|---|
| no `ignore` (the control) | **`3.15.0-118.1.beta`**: #764 exactly | `3.14.0` |
| with the filter | **`3.14.0`** | `3.14.0` |

The control reproduces the logged pick. That shows the replay can tell the two
cases apart. Without it, a « 3.14.0 » answer could simply mean a replay that
never sees betas.

The replay picks which version would be chosen. It leaves out
`apply_cooldown`, which **delays** a pick: by default, a release is not
proposed until three days after it appears (§7, read after the merge).

**The horizon.** The filter must cover every minor whose betas can sort above
the pin. Docker Hub carries betas one minor beyond the newest stable (read
2026-11-12: stable 3.14, beta 3.15). The
list therefore runs from the pinned minor through the next four (a pin that is
three minors behind stable, about nine months at Dart's pace of four minors a
year), plus the next major's `.0`. It is written out to 3.20, so the next few
bumps do not touch it.

**What it cannot see.**

- `X.Y.0-0.0.*`: it sorts below `X.Y.0`, so a `>` range misses it. No such
  docker tag exists. A `>= X.Y.0.a, < X.Y.0` range would catch it if one
  appears.
- A minor beyond the list: the guard (§5) ties the list to the pin.
- Dart changing its scheme, for example a pre-release on a non-`.0` patch.
- Dependabot changing how `ignore` is applied. The probe is pinned to one
  dependabot-core commit, so re-run it against a newer one.

## 5. The guard

A new group in `backend/test/infra/dart_sdk_pin_test.dart`, « Dependabot
proposes stable dart tags only ». It parses `.github/dependabot.yml` as YAML,
so a comment can never satisfy it, and it reads the pin from the Dockerfile
with the existing helpers:

1. **exactly one** `docker` entry covers `/backend`;
2. it has an `ignore` rule whose `dependency-name` (a `*` glob, as Dependabot
   reads it) matches the Dockerfile's image, `dart`;
3. no `ignore` rule for that image has `update-types`, and none lacks
   `versions` (that would mean « all versions »). Either would block stable
   releases;
4. every `versions` entry of those rules has the proven shape
   `> X.Y.0, < X.Y.1`, with the same X.Y on both bounds and the next patch.
   Any other form is not covered by §4's proof;
5. the entries cover the **pinned minor through the next four**, plus
   **the next major's `.0`**. The message names the exact lines that are
   missing.

**Which event turns it red** (verification §15):

| Event | Red? | Defect or repair? |
|---|---|---|
| the `ignore` removed, or renamed away from `dart` | yes (2) | defect: #764 again in the next window |
| an `update-types` or version-less rule for `dart` | yes (3) | defect: stable minors frozen |
| a range in another form (`>= 3.15.0.a, < 3.16`, a glob) | yes (4) | defect, or a new form that must first pass the probe |
| a minor inside the horizon deleted | yes (5) | defect |
| a bump that outruns the horizon (pin 3.17.x needs 3.21) | yes (5) | **a repair turns it red, deliberately**: the filter must move with the pin. The message says which line to add. It is the same contract as ci.yml's `sdk:` in [backend-dart-sdk-pin.md](backend-dart-sdk-pin.md) §5, and it lands on a PR that is already red until ci.yml follows. |
| a correct bump within the horizon | no | repair |

**Mutations watched red** are listed in the commit message.

## 6. Testing — what was run

- The probe, against a filter that went through YAML. Results in §4.
- `dart_sdk_pin_test`: 13 green. 13 mutations watched red, each on its own
  rule (listed in the commit message). Restored from the commit, it is green
  again. The control, a correct bump to 3.14.0 in both the Dockerfile and
  ci.yml, stays green (§5's last row).
- The whole backend on Dart 3.13.7 (the SDK in Flutter 3.47.9's cache, the
  one CI sets up): `dart format` clean (436 files), `dart analyze
  --fatal-infos --fatal-warnings` 0 issues, `dart test` 2137 passed and 10
  skipped (the Postgres-backed tests, which need `DATABASE_URL`).

## 7. Rollout — read back after the merge

**Merged on 2026-11-12 at 09:49:50Z** (`9ff96905`, #767). Dependabot reads
`dependabot.yml` from the default branch only, so this is the first moment the
filter could act. Everything below was read on GitHub, nothing changed.

- **#764 closed by Dependabot itself at 09:49:57Z**, seven seconds after the
  merge, with « Looks like dart is no longer being updated by Dependabot, so
  this is no longer needed. » That wording is broader than what happened:
  dart **is** still checked (next bullet). **Inferred:** the service closed
  the PR because its version, `3.15.0-118.1.beta`, now falls in an ignored
  range.
- **The first `docker` run on the merged config,**
  [43194938363](https://github.com/Zaslons/myweli/actions/runs/43194938363)
  (base `9ff96905`, updater `950f027f`):
  - its job definition carries all nine `dart` ranges as
    `"ignore-conditions"`, and it logs them under « Ignored versions: »;
  - « Checking if dart 3.13.7 needs updating »: the image is still tracked;
  - « …dependabot is treating `3.13.7` as a pre-release »: the `latest`
    heuristic was **still broken**, so this was the case the filter exists
    for. **No beta was proposed.**
  - « Skipping tag 3.14.0 due to cooldown period », then « No update needed
    for dart 3.13.7 ».
- **The prediction this note made was wrong about the timing.** The replay
  (§4) leaves out `apply_cooldown`. GitHub's options reference says Dependabot
  applies « a **default cooldown period of 3 days** to version updates, even
  when `cooldown` is not configured ». Dart 3.14.0 appeared on Docker Hub at
  2026-11-11T19:53Z, so it cannot be proposed before about 2026-11-14T19:53Z.
  The reference gives Monday as the weekly default, but this repo's scheduled
  runs have fallen on Saturdays near 21:21Z (2026-10-24, 10-31 and 11-07).
  **Inferred, not verified:** the run of 2026-11-14 is the first that can
  propose 3.14.0. One more unknown: dependabot-core takes the cooldown date
  from the registry's `Last-Modified` header (`73dc4be`, « the only cooldown
  date source »). If the `3.14.0` index is republished when its riscv64 build
  lands, that date moves, and the wait restarts.
- **That 3.14.0 PR will be red by design** until ci.yml's `sdk:` follows
  ([backend-dart-sdk-pin.md](backend-dart-sdk-pin.md) §5). Moving to 3.14 is
  its own decision (§8).
- **Still worth knowing for later:** never answer a Dependabot `dart` PR with
  `@dependabot ignore this minor version`. That stores a central ignore for the
  whole minor, outside this file and this guard, and it would also block that
  minor's stable releases (comment-commands reference: « prevents Dependabot
  from creating any more pull requests for this minor version »).

## 8. Open questions & follow-ups

1. **Dart 3.14.0 shipped on 2026-11-11.** Moving to it touches the Dockerfile
   (tag and digest), ci.yml's two `sdk:` lines, any formatter or analyzer
   changes, and a check that it still blocks the eMudhra intermediates. The
   floor stays 3.13.7, and `verify-image-dart-sdk.sh` reads the built binary.
   This needs its own PR.
2. **Report the heuristic to dependabot-core?** `find_latest_tag` accepts a
   less precise canonical tag (`3`) and so classes a pinned stable as a
   pre-release. Any multi-arch image whose arches publish at different times
   would hit it. Opening an issue upstream publishes content, so it is the
   owner's call.
3. **The labels `dependencies` and `ci` do not exist in the repository**
   (read: `gh label list`). Every entry in `dependabot.yml` asks for them, so
   every Dependabot PR arrives unlabelled (#746–#749 and #764). Dependabot
   says so in a comment on each: « The following labels could not be found:
   `dependencies`. » Creating the two labels is a change to the repository,
   so it is the owner's call.
