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

### Running the funnel e2e locally (Q1)

The CI job does this for you on every PR; this is for when you are changing the
funnel itself. Spec: [`../docs/design/backend-q1-funnel-smoke.md`](../docs/design/backend-q1-funnel-smoke.md).

```bash
docker run -d --name myweli-smoke-pg \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=myweli_smoke \
  -p 5433:5432 postgres:16
```

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5433/myweli_smoke \
       JWT_SECRET=local-smoke-secret ENV=dev PORT=8099 \
       AUTH_METHODS=google,apple,email \
       ADMIN_EMAIL=smoke-admin@myweli.test ADMIN_PASSWORD=smoke-not-a-secret
```

Then build, boot and run — the harness is **fail-closed**, so it throws rather
than skipping if `SMOKE_BASE_URL` is unset:

```bash
dart pub global run dart_frog_cli:dart_frog build && dart build/bin/server.dart
```

```bash
SMOKE_BASE_URL=http://localhost:8099 dart test tool/smoke/funnel_smoke_test.dart
```

Three things that will waste your afternoon otherwise:

- **`dart_frog build` COPIES `lib/` into `build/`**, and `build/` is its own
  package root. A change under `lib/` does not reach the running server until
  you rebuild — a mutation-testing run reported four assertions as blind before
  this was understood.
- **`dart_frog dev` keeps serving the last good build** when new code fails to
  compile, so a green run can be a run against stale code. Prefer
  `dart build/bin/server.dart` here.
- The harness lives in `tool/`, not `test/`, precisely so a bare `dart test`
  never collects it. Run it by path.

## Build

```sh
dart_frog build      # emits build/ with a Dockerfile-ready server
```

## Status

- **B0 (this):** project scaffold, `/health`, contract seed, CI. No database yet.
- Next: provider read slice → auth → Postgres persistence (`docs/ROADMAP.md`).

Real Mobile Money, WhatsApp/SMS, and FCM are deferred (see PRD OQ-1 / §8).
