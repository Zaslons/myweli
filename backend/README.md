# Myweli backend

The Myweli REST API ([dart_frog](https://dartfrog.vgv.dev)). It will replace the
Flutter app's mock `*ServiceInterface` implementations one interface at a time —
the interface→mock architecture in `mobile/` is what makes that swap localized
(see `docs/ROADMAP.md` Phase 3 and `docs/PRD.md` §8.2).

The **API contract is the source of truth**: [`docs/api/openapi.yaml`](../docs/api/openapi.yaml).
Both the Flutter app (Dart) and the future public web (Next.js, generated TS)
converge on those shapes.

## Prerequisites

- Dart SDK ≥ 3.10
- The dart_frog CLI (only needed to run the dev server):
  ```sh
  dart pub global activate dart_frog_cli
  ```

## Develop

```sh
dart pub get
dart_frog dev        # http://localhost:8080  (try GET /health)
```

## Quality gates (match CI)

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
dart test
```

## Build

```sh
dart_frog build      # emits build/ with a Dockerfile-ready server
```

## Status

- **B0 (this):** project scaffold, `/health`, contract seed, CI. No database yet.
- Next: provider read slice → auth → Postgres persistence (`docs/ROADMAP.md`).

Real Mobile Money, WhatsApp/SMS, and FCM are deferred (see PRD OQ-1 / §8).
