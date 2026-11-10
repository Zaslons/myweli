# Myweli API (dart_frog) — multi-stage build to a minimal runtime image.
# Host-agnostic: runs on Fly.io / Cloud Run / Render / any Docker host.
#
#   docker build -t myweli-api backend/
#   docker run -p 8080:8080 -e ENV=prod -e JWT_SECRET=… -e DATABASE_URL=… myweli-api
#
# All config comes from env (never baked into the image) — see backend/.env.example
# and docs/DEPLOYMENT.md. Migrations run automatically on boot when DATABASE_URL
# is set. The server reads PORT (default 8080) and binds 0.0.0.0.
#
# **The SDK is pinned by exact version AND digest, and never floats.** The
# server's outbound TLS — Apple and Google sign-in, FCM, R2, Resend, Sentry, the
# web rebuild hook — is verified by the BoringSSL compiled into this binary, so
# the SDK version IS the TLS verifier production runs. Dart < 3.13.7 trusts
# eight compromised eMudhra intermediates (GHSA-frr6-h895-5pxp); 3.13.7 blocks
# them. `dart:stable` happened to resolve to 3.13.7 on the day production was
# last built — luck, not a control.
#
# The version must equal `sdk:` in .github/workflows/ci.yml (both backend jobs),
# so the tests run on the compiler that ships, and must not go below the
# advisory floor: test/infra/dart_sdk_pin_test.dart fails the PR otherwise. To
# bump, change the tag, the digest and ci.yml together.
# Design: docs/design/backend-dart-sdk-pin.md
FROM dart:3.13.7@sha256:854f3c50b1cbd4a5a54c9fa67d4f5b6702ac49b4a26d21a80e7712a72528b215 AS build

WORKDIR /app

# Resolve dependencies first for better layer caching.
COPY pubspec.* ./
RUN dart pub get

# Generate the dart_frog server, then compile a self-contained executable.
# The CLI version is the one CI's boot smoke builds with (same guard).
COPY . .
RUN dart pub global activate dart_frog_cli 1.2.14 \
 && dart pub global run dart_frog_cli:dart_frog build
RUN cd build \
 && dart pub get \
 && dart compile exe bin/server.dart -o bin/server

# Minimal runtime: the compiled server (which carries the Dart runtime) plus
# the base image's /runtime/ — the glibc pieces it links against, and
# /etc/ssl/certs, which dart:io on Linux reads as its root store. That bundle
# is frozen at the base image's build: it changes only when the digest above
# does.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bin/server /app/bin/server

EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]
